// Ultralytics AGPL-3.0 License - https://ultralytics.com/license

import CoreVideo
import Foundation

struct ImageMetricsAnalyzer {
  static func analyze(
    pixelBuffer: CVPixelBuffer,
    roiLeft: Double? = nil,
    roiTop: Double? = nil,
    roiRight: Double? = nil,
    roiBottom: Double? = nil
  ) -> [String: Any] {
    let targetWidth = 160
    let targetHeight = 120
    let luma = sampleLuma(pixelBuffer: pixelBuffer, width: targetWidth, height: targetHeight)
    return analyzeLuma(
      luma,
      width: targetWidth,
      height: targetHeight,
      roiLeft: roiLeft,
      roiTop: roiTop,
      roiRight: roiRight,
      roiBottom: roiBottom
    )
  }

  private static func sampleLuma(pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Double] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return Array(repeating: 127.5, count: width * height)
    }

    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
    var values = Array(repeating: 0.0, count: width * height)

    for y in 0..<height {
      let sourceY = min(sourceHeight - 1, max(0, y * sourceHeight / height))
      for x in 0..<width {
        let sourceX = min(sourceWidth - 1, max(0, x * sourceWidth / width))
        let offset = sourceY * bytesPerRow + sourceX * 4
        let b = Double(buffer[offset])
        let g = Double(buffer[offset + 1])
        let r = Double(buffer[offset + 2])
        values[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
      }
    }

    return values
  }

  private static func analyzeLuma(
    _ luma: [Double],
    width: Int,
    height: Int,
    roiLeft: Double?,
    roiTop: Double?,
    roiRight: Double?,
    roiBottom: Double?
  ) -> [String: Any] {
    let hasRoi =
      roiLeft != nil && roiTop != nil && roiRight != nil && roiBottom != nil
      && roiRight! > roiLeft! && roiBottom! > roiTop!

    let roiX0 = hasRoi ? clamp(Int(roiLeft! * Double(width)), 0, width - 1) : 0
    let roiY0 = hasRoi ? clamp(Int(roiTop! * Double(height)), 0, height - 1) : 0
    let roiX1 = hasRoi ? clamp(Int(roiRight! * Double(width)), 0, width - 1) : width - 1
    let roiY1 = hasRoi ? clamp(Int(roiBottom! * Double(height)), 0, height - 1) : height - 1

    let roiWidth = max(1, roiX1 - roiX0 + 1)
    let roiHeight = max(1, roiY1 - roiY0 + 1)
    let nearPadX = max(8, Int(Double(roiWidth) * 0.45))
    let nearPadY = max(8, Int(Double(roiHeight) * 0.45))
    let nearX0 = hasRoi ? clamp(roiX0 - nearPadX, 0, width - 1) : 0
    let nearY0 = hasRoi ? clamp(roiY0 - nearPadY, 0, height - 1) : 0
    let nearX1 = hasRoi ? clamp(roiX1 + nearPadX, 0, width - 1) : width - 1
    let nearY1 = hasRoi ? clamp(roiY1 + nearPadY, 0, height - 1) : height - 1

    var globalSum = 0.0
    var subjectSum = 0.0
    var backgroundSum = 0.0
    var nearBackgroundSum = 0.0
    var globalCount = 0
    var subjectCount = 0
    var backgroundCount = 0
    var nearBackgroundCount = 0
    var highlightCount = 0
    var shadowCount = 0
    var subjectHighlightCount = 0
    var subjectShadowCount = 0
    var nearBackgroundHighlightCount = 0

    let midX = width / 2
    let midY = height / 2
    var sumLeft = 0.0
    var sumRight = 0.0
    var sumTop = 0.0
    var sumBottom = 0.0
    var countLeft = 0
    var countRight = 0
    var countTop = 0
    var countBottom = 0

    for y in 0..<height {
      for x in 0..<width {
        let value = luma[y * width + x]
        globalSum += value
        globalCount += 1
        if value >= 235.0 { highlightCount += 1 }
        if value <= 35.0 { shadowCount += 1 }

        if x < midX {
          sumLeft += value
          countLeft += 1
        } else {
          sumRight += value
          countRight += 1
        }
        if y < midY {
          sumTop += value
          countTop += 1
        } else {
          sumBottom += value
          countBottom += 1
        }

        let inRoi = hasRoi && x >= roiX0 && x <= roiX1 && y >= roiY0 && y <= roiY1
        if inRoi {
          subjectSum += value
          subjectCount += 1
          if value >= 235.0 { subjectHighlightCount += 1 }
          if value <= 35.0 { subjectShadowCount += 1 }
        } else if hasRoi {
          backgroundSum += value
          backgroundCount += 1
          let inNearBackground = x >= nearX0 && x <= nearX1 && y >= nearY0 && y <= nearY1
          if inNearBackground {
            nearBackgroundSum += value
            nearBackgroundCount += 1
            if value >= 235.0 { nearBackgroundHighlightCount += 1 }
          }
        }
      }
    }

    let globalBrightness = globalCount > 0 ? globalSum / Double(globalCount) / 255.0 : 0.5
    let subjectBrightness =
      subjectCount > 0 ? subjectSum / Double(subjectCount) / 255.0 : globalBrightness
    let backgroundBrightness =
      backgroundCount > 0 ? backgroundSum / Double(backgroundCount) / 255.0 : globalBrightness
    let nearBackgroundBrightness =
      nearBackgroundCount > 0
      ? nearBackgroundSum / Double(nearBackgroundCount) / 255.0 : backgroundBrightness

    let globalBlurScore = laplacianVariance(
      luma: luma, width: width, height: height, x0: 0, y0: 0, x1: width - 1, y1: height - 1)
    let subjectBlurScore =
      hasRoi && subjectCount > 4
      ? laplacianVariance(
        luma: luma, width: width, height: height, x0: roiX0, y0: roiY0, x1: roiX1, y1: roiY1)
      : globalBlurScore

    let lightDirectionIndex = estimateLightDirection(
      countLeft: countLeft,
      countRight: countRight,
      countTop: countTop,
      countBottom: countBottom,
      sumLeft: sumLeft,
      sumRight: sumRight,
      sumTop: sumTop,
      sumBottom: sumBottom,
      hasRoi: hasRoi,
      subjectSum: subjectSum,
      subjectCount: subjectCount,
      backgroundSum: backgroundSum,
      backgroundCount: backgroundCount
    )

    return [
      "brightness": globalBrightness,
      "subjectBrightness": subjectBrightness,
      "backgroundBrightness": backgroundBrightness,
      "nearBackgroundBrightness": nearBackgroundBrightness,
      "highlightRatio": globalCount > 0 ? Double(highlightCount) / Double(globalCount) : 0.0,
      "shadowRatio": globalCount > 0 ? Double(shadowCount) / Double(globalCount) : 0.0,
      "subjectHighlightRatio": subjectCount > 0
        ? Double(subjectHighlightCount) / Double(subjectCount)
        : (globalCount > 0 ? Double(highlightCount) / Double(globalCount) : 0.0),
      "subjectShadowRatio": subjectCount > 0
        ? Double(subjectShadowCount) / Double(subjectCount)
        : (globalCount > 0 ? Double(shadowCount) / Double(globalCount) : 0.0),
      "nearBackgroundHighlightRatio": nearBackgroundCount > 0
        ? Double(nearBackgroundHighlightCount) / Double(nearBackgroundCount)
        : (globalCount > 0 ? Double(highlightCount) / Double(globalCount) : 0.0),
      "globalBlurScore": globalBlurScore,
      "subjectBlurScore": subjectBlurScore,
      "lightDirectionIndex": lightDirectionIndex,
    ]
  }

  private static func laplacianVariance(
    luma: [Double], width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int
  ) -> Double {
    var sum = 0.0
    var sumSquare = 0.0
    var count = 0
    if x1 - x0 < 2 || y1 - y0 < 2 { return 999.0 }

    for y in (y0 + 1)..<y1 {
      for x in (x0 + 1)..<x1 {
        let lap =
          -luma[(y - 1) * width + x]
          - luma[y * width + (x - 1)]
          + 4.0 * luma[y * width + x]
          - luma[y * width + (x + 1)]
          - luma[(y + 1) * width + x]
        sum += lap
        sumSquare += lap * lap
        count += 1
      }
    }
    if count == 0 { return 999.0 }
    let mean = sum / Double(count)
    return sumSquare / Double(count) - mean * mean
  }

  private static func estimateLightDirection(
    countLeft: Int,
    countRight: Int,
    countTop: Int,
    countBottom: Int,
    sumLeft: Double,
    sumRight: Double,
    sumTop: Double,
    sumBottom: Double,
    hasRoi: Bool,
    subjectSum: Double,
    subjectCount: Int,
    backgroundSum: Double,
    backgroundCount: Int
  ) -> Int {
    guard countLeft > 0, countRight > 0, countTop > 0, countBottom > 0 else { return 0 }

    if hasRoi && subjectCount > 0 && backgroundCount > 0 {
      let subjectAverage = subjectSum / Double(subjectCount)
      let backgroundAverage = backgroundSum / Double(backgroundCount)
      if backgroundAverage > 150.0 && backgroundAverage - subjectAverage > 50.0 {
        return 5
      }
    }

    let horizontalDiff = sumRight / Double(countRight) - sumLeft / Double(countLeft)
    let verticalDiff = sumBottom / Double(countBottom) - sumTop / Double(countTop)
    let threshold = 20.0

    if abs(horizontalDiff) < threshold && abs(verticalDiff) < threshold { return 0 }
    if abs(horizontalDiff) >= abs(verticalDiff) {
      return horizontalDiff > 0 ? 2 : 1
    }
    return verticalDiff > 0 ? 4 : 3
  }

  private static func clamp(_ value: Int, _ minValue: Int, _ maxValue: Int) -> Int {
    min(max(value, minValue), maxValue)
  }
}
