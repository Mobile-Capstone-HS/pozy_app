// Ultralytics AGPL-3.0 License - https://ultralytics.com/license

import CoreGraphics
import CoreVideo
import Foundation

private struct RoiTrackPoint {
  var x: Float
  var y: Float
  var patch: [Float]
}

private struct RoiTrackMatch {
  let previous: RoiTrackPoint
  let next: RoiTrackPoint
}

private struct RoiTemplate {
  let samplesX: Int
  let samplesY: Int
  let data: [Float]
}

final class PixelBufferReader {
  let pixelBuffer: CVPixelBuffer
  let width: Int
  let height: Int
  private let bytesPerRow: Int
  private let buffer: UnsafeMutablePointer<UInt8>?

  init(pixelBuffer: CVPixelBuffer) {
    self.pixelBuffer = pixelBuffer
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    width = CVPixelBufferGetWidth(pixelBuffer)
    height = CVPixelBufferGetHeight(pixelBuffer)
    bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    buffer = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self)
  }

  deinit {
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
  }

  func lumaAt(x: Int, y: Int) -> Float {
    guard let buffer = buffer, width > 0, height > 0 else { return 0.5 }
    let safeX = min(max(x, 0), width - 1)
    let safeY = min(max(y, 0), height - 1)
    let offset = safeY * bytesPerRow + safeX * 4
    let b = Float(buffer[offset]) / 255.0
    let g = Float(buffer[offset + 1]) / 255.0
    let r = Float(buffer[offset + 2]) / 255.0
    return 0.299 * r + 0.587 * g + 0.114 * b
  }
}

final class LockedRoiTracker {
  private var roi: CGRect?
  private var trackPoints: [RoiTrackPoint] = []
  private var template: RoiTemplate?
  private var failures = 0
  private let patchRadiusPx = 4
  private let maxTrackPoints = 28

  func setLockedRoi(_ next: CGRect?) {
    roi = next.map(clampNormalizedRoi)
    trackPoints.removeAll()
    template = nil
    failures = 0
  }

  func currentRoi() -> CGRect? {
    roi
  }

  func update(pixelBuffer: CVPixelBuffer) -> (roi: CGRect, confidence: Float)? {
    guard let current = roi else { return nil }
    let reader = PixelBufferReader(pixelBuffer: pixelBuffer)
    let currentRoi = clampNormalizedRoi(current)
    guard currentRoi.width >= 0.015, currentRoi.height >= 0.015 else { return nil }

    if trackPoints.count < 4 {
      trackPoints = initializeTrackPoints(reader: reader, roi: currentRoi)
      template = extractTemplate(reader: reader, roi: currentRoi)
      failures = 0
      roi = currentRoi
      return (currentRoi, (trackPoints.count >= 4 || template != nil) ? 1.0 : 0.0)
    }

    let templateTrack = template.flatMap { trackTemplate(reader: reader, template: $0, roi: currentRoi) }
    let previousPoints = trackPoints
    var trackedPoints: [RoiTrackPoint] = []
    var matches: [RoiTrackMatch] = []
    var dxs: [Float] = []
    var dys: [Float] = []

    for point in previousPoints {
      guard let next = trackPoint(reader: reader, point: point, roi: currentRoi) else { continue }
      trackedPoints.append(next)
      matches.append(RoiTrackMatch(previous: point, next: next))
      dxs.append(next.x - point.x)
      dys.append(next.y - point.y)
    }

    let pointConfidence = min(max(Float(trackedPoints.count) / Float(max(1, previousPoints.count)), 0), 1)
    if templateTrack != nil || (trackedPoints.count >= 3 && pointConfidence >= 0.12) {
      let templateRoi = templateTrack?.roi
      let templateConfidence = templateTrack?.confidence ?? 0
      let mdx = median(dxs)
      let mdy = median(dys)
      let pointRoi: CGRect? =
        trackedPoints.count >= 3 && pointConfidence >= 0.12
        ? clampNormalizedRoi(
          currentRoi.offsetBy(dx: CGFloat(mdx), dy: CGFloat(mdy))
        )
        : nil

      let bestRoi: CGRect
      if let templateRoi = templateRoi, let pointRoi = pointRoi {
        let templateWeight = CGFloat(min(max(0.58 + templateConfidence * 0.22, 0.58), 0.80))
        let pointWeight = 1.0 - templateWeight
        bestRoi = clampNormalizedRoi(
          CGRect(
            x: templateRoi.minX * templateWeight + pointRoi.minX * pointWeight,
            y: templateRoi.minY * templateWeight + pointRoi.minY * pointWeight,
            width: templateRoi.width * templateWeight + pointRoi.width * pointWeight,
            height: templateRoi.height * templateWeight + pointRoi.height * pointWeight
          )
        )
      } else {
        bestRoi = templateRoi ?? pointRoi ?? currentRoi
      }

      roi = bestRoi
      if trackedPoints.count >= 3 {
        trackPoints = trackedPoints
      }

      if let nextTemplate = extractTemplate(
        reader: reader,
        roi: bestRoi,
        samplesX: template?.samplesX ?? 14,
        samplesY: template?.samplesY ?? 14
      ) {
        template = template.map { blendTemplates(previous: $0, next: nextTemplate) } ?? nextTemplate
      }

      failures = 0
      return (bestRoi, max(pointConfidence * 0.82, templateConfidence))
    }

    failures += 1
    if failures >= 3 {
      trackPoints.removeAll()
      template = nil
    }
    return (currentRoi, max(pointConfidence * 0.5, templateTrack?.confidence ?? 0))
  }

  private func initializeTrackPoints(reader: PixelBufferReader, roi: CGRect) -> [RoiTrackPoint] {
    var candidates: [RoiTrackPoint] = []
    let grid = 7
    for gy in 1..<grid {
      for gx in 1..<grid {
        let nx = Float(roi.minX + roi.width * CGFloat(gx) / CGFloat(grid))
        let ny = Float(roi.minY + roi.height * CGFloat(gy) / CGFloat(grid))
        guard let patch = extractNormalizedPatch(reader: reader, nx: nx, ny: ny) else { continue }
        candidates.append(RoiTrackPoint(x: nx, y: ny, patch: patch))
      }
    }
    candidates.sort {
      $0.patch.reduce(0) { $0 + abs($1) } > $1.patch.reduce(0) { $0 + abs($1) }
    }
    return Array(candidates.prefix(maxTrackPoints))
  }

  private func trackPoint(reader: PixelBufferReader, point: RoiTrackPoint, roi: CGRect) -> RoiTrackPoint? {
    let radiusX = max(0.035, min(0.085, Float(roi.width) * 0.55))
    let radiusY = max(0.035, min(0.085, Float(roi.height) * 0.55))
    let stepX = max(2.0 / Float(reader.width), Float(roi.width) * 0.08)
    let stepY = max(2.0 / Float(reader.height), Float(roi.height) * 0.08)

    var bestX = point.x
    var bestY = point.y
    var bestPatch: [Float]?
    var bestScore = Float.greatestFiniteMagnitude

    var dy = -radiusY
    while dy <= radiusY + 0.0001 {
      var dx = -radiusX
      while dx <= radiusX + 0.0001 {
        let nx = min(max(point.x + dx, 0), 1)
        let ny = min(max(point.y + dy, 0), 1)
        if let patch = extractNormalizedPatch(reader: reader, nx: nx, ny: ny) {
          let score = meanSquaredError(point.patch, patch)
          if score < bestScore {
            bestScore = score
            bestX = nx
            bestY = ny
            bestPatch = patch
          }
        }
        dx += stepX
      }
      dy += stepY
    }

    guard let patch = bestPatch, bestScore <= 0.030 else { return nil }
    return RoiTrackPoint(x: bestX, y: bestY, patch: blendArrays(previous: point.patch, next: patch, alpha: 0.06))
  }

  private func trackTemplate(reader: PixelBufferReader, template: RoiTemplate, roi: CGRect)
    -> (roi: CGRect, confidence: Float)?
  {
    let radiusX = max(0.04, min(0.14, Float(roi.width) * 0.90))
    let radiusY = max(0.04, min(0.14, Float(roi.height) * 0.90))
    let stepX = max(2.0 / Float(reader.width), min(0.014, Float(roi.width) * 0.10))
    let stepY = max(2.0 / Float(reader.height), min(0.014, Float(roi.height) * 0.10))

    var bestRoi: CGRect?
    var bestScore = Float.greatestFiniteMagnitude
    var dy = -radiusY
    while dy <= radiusY + 0.0001 {
      var dx = -radiusX
      while dx <= radiusX + 0.0001 {
        let candidate = clampNormalizedRoi(roi.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy)))
        if abs(candidate.width - roi.width) < 0.002 && abs(candidate.height - roi.height) < 0.002,
          let nextTemplate = extractTemplate(
            reader: reader,
            roi: candidate,
            samplesX: template.samplesX,
            samplesY: template.samplesY
          )
        {
          let score = meanSquaredError(template.data, nextTemplate.data)
          if score < bestScore {
            bestScore = score
            bestRoi = candidate
          }
        }
        dx += stepX
      }
      dy += stepY
    }

    guard let matched = bestRoi, bestScore <= 0.055 else { return nil }
    return (matched, min(max(1.0 - bestScore / 0.055, 0), 1))
  }

  private func extractTemplate(
    reader: PixelBufferReader,
    roi: CGRect,
    samplesX: Int = 14,
    samplesY: Int = 14
  ) -> RoiTemplate? {
    let clipped = clampNormalizedRoi(roi)
    guard clipped.width >= 0.015, clipped.height >= 0.015 else { return nil }

    var data = Array(repeating: Float(0), count: samplesX * samplesY)
    var sum: Float = 0
    var index = 0
    for sy in 0..<samplesY {
      for sx in 0..<samplesX {
        let nx = clipped.minX + clipped.width * (CGFloat(sx) + 0.5) / CGFloat(samplesX)
        let ny = clipped.minY + clipped.height * (CGFloat(sy) + 0.5) / CGFloat(samplesY)
        let x = Int(nx * CGFloat(reader.width))
        let y = Int(ny * CGFloat(reader.height))
        let value = reader.lumaAt(x: x, y: y)
        data[index] = value
        sum += value
        index += 1
      }
    }
    normalize(&data, sum: sum, minVariance: 0.0004)
    guard !data.isEmpty else { return nil }
    return RoiTemplate(samplesX: samplesX, samplesY: samplesY, data: data)
  }

  private func extractNormalizedPatch(reader: PixelBufferReader, nx: Float, ny: Float) -> [Float]? {
    let cx = Int(nx * Float(reader.width))
    let cy = Int(ny * Float(reader.height))
    if cx - patchRadiusPx < 0 || cy - patchRadiusPx < 0
      || cx + patchRadiusPx >= reader.width || cy + patchRadiusPx >= reader.height
    {
      return nil
    }

    let side = patchRadiusPx * 2 + 1
    var patch = Array(repeating: Float(0), count: side * side)
    var sum: Float = 0
    var index = 0
    for py in -patchRadiusPx...patchRadiusPx {
      for px in -patchRadiusPx...patchRadiusPx {
        let value = reader.lumaAt(x: cx + px, y: cy + py)
        patch[index] = value
        sum += value
        index += 1
      }
    }
    normalize(&patch, sum: sum, minVariance: 0.0008)
    return patch.isEmpty ? nil : patch
  }

  private func normalize(_ values: inout [Float], sum: Float, minVariance: Float) {
    guard !values.isEmpty else { return }
    let mean = sum / Float(values.count)
    var variance: Float = 0
    for i in values.indices {
      values[i] -= mean
      variance += values[i] * values[i]
    }
    if variance / Float(values.count) < minVariance {
      values.removeAll()
      return
    }
    let norm = max(sqrt(variance), 0.0001)
    for i in values.indices {
      values[i] /= norm
    }
  }

  private func meanSquaredError(_ a: [Float], _ b: [Float]) -> Float {
    let n = min(a.count, b.count)
    guard n > 0 else { return .greatestFiniteMagnitude }
    var sum: Float = 0
    for i in 0..<n {
      let d = a[i] - b[i]
      sum += d * d
    }
    return sum / Float(n)
  }

  private func blendArrays(previous: [Float], next: [Float], alpha: Float) -> [Float] {
    let n = min(previous.count, next.count)
    return (0..<n).map { previous[$0] * (1 - alpha) + next[$0] * alpha }
  }

  private func blendTemplates(previous: RoiTemplate, next: RoiTemplate, alpha: Float = 0.035) -> RoiTemplate {
    RoiTemplate(
      samplesX: previous.samplesX,
      samplesY: previous.samplesY,
      data: blendArrays(previous: previous.data, next: next.data, alpha: alpha)
    )
  }

  private func median(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }

  private func clampNormalizedRoi(_ roi: CGRect) -> CGRect {
    let left = min(max(roi.minX, 0), 1)
    let top = min(max(roi.minY, 0), 1)
    let right = min(max(roi.maxX, 0), 1)
    let bottom = min(max(roi.maxY, 0), 1)
    return CGRect(
      x: min(left, right),
      y: min(top, bottom),
      width: abs(right - left),
      height: abs(bottom - top)
    )
  }
}
