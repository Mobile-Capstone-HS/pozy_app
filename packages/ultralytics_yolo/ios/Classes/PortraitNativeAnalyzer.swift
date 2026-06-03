// Ultralytics AGPL-3.0 License - https://ultralytics.com/license

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import MLKitFaceDetection
import MLKitVision
import TensorFlowLite
import UIKit

private struct PortraitFaceMetrics {
  var detected = false
  var yaw: Double?
  var pitch: Double?
  var roll: Double?
  var leftEyeOpen: Double?
  var rightEyeOpen: Double?
  var smile: Double?
  var bounds: CGRect?
}

private struct PortraitLightingMetrics {
  var code = 5.0
  var confidence = 0.0
}

final class PortraitNativeAnalyzer {
  private static let lightingSize = 224
  private static let lightingMinConfidence: Float = 0.55
  private static let defaultFaceIntervalMs = 180
  private static let defaultFaceIntervalFrames = 6

  private let queue = DispatchQueue(label: "portrait-native-analyzer", qos: .userInitiated)
  private let faceDetector: FaceDetector
  private var faceBusy = false
  private var lightingBusy = false
  private var faceFrameCounter = 0
  private var lightingFrameCounter = 0
  private var analyzerFrameCounter: Int64 = 0
  private var faceIntervalMs = defaultFaceIntervalMs
  private var faceIntervalFrames = defaultFaceIntervalFrames
  private var lastFaceAnalysisAtMs: Int64 = 0

  private var latestFaceMetrics = PortraitFaceMetrics()
  private var latestLightingMetrics = PortraitLightingMetrics()
  private var latestFacePayload: [String: Any] = [:]
  private var lightingInterpreter: Interpreter?
  private var lightingLabels: [String] = []
  private var lightingLoaded = false

  init() {
    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.classificationMode = .all
    faceDetector = FaceDetector.faceDetector(options: options)
  }

  func setFaceAnalysisThrottle(intervalMs: Int?, intervalFrames: Int?) {
    faceIntervalMs = min(max(intervalMs ?? Self.defaultFaceIntervalMs, 0), 1000)
    faceIntervalFrames = min(max(intervalFrames ?? Self.defaultFaceIntervalFrames, 1), 120)
  }

  func schedule(
    sampleBuffer: CMSampleBuffer?,
    pixelBuffer: CVPixelBuffer,
    isFrontCamera: Bool,
    roiLeft: Double?,
    roiTop: Double?,
    roiRight: Double?,
    roiBottom: Double?
  ) {
    ensureReady()
    analyzerFrameCounter += 1
    faceFrameCounter += 1
    lightingFrameCounter += 1

    let nowMs = Self.nowMs()
    if let sampleBuffer = sampleBuffer,
      faceFrameCounter >= faceIntervalFrames,
      nowMs - lastFaceAnalysisAtMs >= faceIntervalMs
    {
      faceFrameCounter = 0
      lastFaceAnalysisAtMs = nowMs
      scheduleFaceAnalysis(
        sampleBuffer: sampleBuffer,
        isFrontCamera: isFrontCamera,
        frameNumber: analyzerFrameCounter
      )
    }

    if lightingFrameCounter >= 1 {
      lightingFrameCounter = 0
      scheduleLightingAnalysis(
        pixelBuffer: pixelBuffer,
        personBounds: normalizedRectToPixelRect(
          pixelBuffer: pixelBuffer,
          left: roiLeft,
          top: roiTop,
          right: roiRight,
          bottom: roiBottom
        )
      )
    }
  }

  func latestMetrics() -> [String: Any] {
    var metrics: [String: Any] = [
      "portraitFaceDetected": latestFaceMetrics.detected ? 1.0 : 0.0,
      "portraitLightingCode": latestLightingMetrics.code,
      "portraitLightingConfidence": latestLightingMetrics.confidence,
    ]
    latestFaceMetrics.yaw.map { metrics["portraitFaceYaw"] = $0 }
    latestFaceMetrics.pitch.map { metrics["portraitFacePitch"] = $0 }
    latestFaceMetrics.roll.map { metrics["portraitFaceRoll"] = $0 }
    latestFaceMetrics.leftEyeOpen.map { metrics["portraitLeftEyeOpen"] = $0 }
    latestFaceMetrics.rightEyeOpen.map { metrics["portraitRightEyeOpen"] = $0 }
    latestFaceMetrics.smile.map { metrics["portraitSmileProbability"] = $0 }
    return metrics
  }

  func latestFaceResults() -> [String: Any] {
    latestFacePayload
  }

  func dispose() {
    latestFaceMetrics = PortraitFaceMetrics()
    latestLightingMetrics = PortraitLightingMetrics()
    latestFacePayload = [:]
    lightingInterpreter = nil
    lightingLoaded = false
  }

  private func ensureReady() {
    if !lightingLoaded {
      loadLightingModel()
    }
  }

  private func scheduleFaceAnalysis(
    sampleBuffer: CMSampleBuffer,
    isFrontCamera: Bool,
    frameNumber: Int64
  ) {
    queue.async { [weak self] in
      guard let self = self else { return }
      if self.faceBusy { return }
      self.faceBusy = true

      let image = VisionImage(buffer: sampleBuffer)
      image.orientation = self.imageOrientation(isFrontCamera: isFrontCamera)
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
      let imageWidth = pixelBuffer.map(CVPixelBufferGetWidth) ?? 0
      let imageHeight = pixelBuffer.map(CVPixelBufferGetHeight) ?? 0
      let timestampMs = Self.nowMs()

      self.faceDetector.process(image) { [weak self] faces, error in
        guard let self = self else { return }
        defer { self.faceBusy = false }

        if error != nil {
          DispatchQueue.main.async {
            self.latestFaceMetrics = PortraitFaceMetrics()
            self.latestFacePayload = [:]
          }
          return
        }

        let faces = faces ?? []
        let payload = self.buildFacePayload(
          faces: faces,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          isFrontCamera: isFrontCamera,
          timestampMs: timestampMs,
          frameNumber: frameNumber
        )
        let bestFace = faces.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let metrics = bestFace.map { self.metrics(from: $0) } ?? PortraitFaceMetrics()

        DispatchQueue.main.async {
          self.latestFacePayload = payload
          self.latestFaceMetrics = metrics
        }
      }
    }
  }

  private func scheduleLightingAnalysis(pixelBuffer: CVPixelBuffer, personBounds: CGRect?) {
    queue.async { [weak self] in
      guard let self = self else { return }
      if self.lightingBusy { return }
      self.lightingBusy = true
      defer { self.lightingBusy = false }

      let result: PortraitLightingMetrics
      if let faceBounds = self.latestFaceMetrics.bounds {
        result = self.runLighting(pixelBuffer: pixelBuffer, faceBounds: faceBounds)
      } else {
        result = self.estimateBacklightFallback(pixelBuffer: pixelBuffer, personBounds: personBounds)
      }

      DispatchQueue.main.async {
        self.latestLightingMetrics = result
      }
    }
  }

  private func metrics(from face: Face) -> PortraitFaceMetrics {
    PortraitFaceMetrics(
      detected: true,
      yaw: Double(face.headEulerAngleY),
      pitch: Double(face.headEulerAngleX),
      roll: Double(face.headEulerAngleZ),
      leftEyeOpen: face.hasLeftEyeOpenProbability ? Double(face.leftEyeOpenProbability) : nil,
      rightEyeOpen: face.hasRightEyeOpenProbability ? Double(face.rightEyeOpenProbability) : nil,
      smile: face.hasSmilingProbability ? Double(face.smilingProbability) : nil,
      bounds: face.frame
    )
  }

  private func buildFacePayload(
    faces: [Face],
    imageWidth: Int,
    imageHeight: Int,
    isFrontCamera: Bool,
    timestampMs: Int64,
    frameNumber: Int64
  ) -> [String: Any] {
    let results = faces.map { face -> [String: Any] in
      let status = faceConfidenceStatus(
        bounds: face.frame,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        hasEyeProb: face.hasLeftEyeOpenProbability && face.hasRightEyeOpenProbability
      )
      var map: [String: Any] = [
        "left": Double(face.frame.minX),
        "top": Double(face.frame.minY),
        "right": Double(face.frame.maxX),
        "bottom": Double(face.frame.maxY),
        "imageWidth": imageWidth,
        "imageHeight": imageHeight,
        "rotationDegrees": rotationDegreesForCurrentDevice(),
        "isFrontCamera": isFrontCamera,
        "timestampMs": timestampMs,
        "frameNumber": frameNumber,
        "confidenceStatus": status,
      ]
      if face.hasLeftEyeOpenProbability {
        map["leftEyeOpenProbability"] = Double(face.leftEyeOpenProbability)
      }
      if face.hasRightEyeOpenProbability {
        map["rightEyeOpenProbability"] = Double(face.rightEyeOpenProbability)
      }
      if face.hasSmilingProbability {
        map["smilingProbability"] = Double(face.smilingProbability)
      }
      map["headEulerAngleY"] = Double(face.headEulerAngleY)
      map["headEulerAngleZ"] = Double(face.headEulerAngleZ)
      map["headEulerAngleX"] = Double(face.headEulerAngleX)
      return map
    }

    return [
      "count": results.count,
      "imageWidth": imageWidth,
      "imageHeight": imageHeight,
      "rotationDegrees": rotationDegreesForCurrentDevice(),
      "isFrontCamera": isFrontCamera,
      "timestampMs": timestampMs,
      "frameNumber": frameNumber,
      "faces": results,
    ]
  }

  private func runLighting(pixelBuffer: CVPixelBuffer, faceBounds: CGRect) -> PortraitLightingMetrics {
    guard lightingInterpreter != nil else { return PortraitLightingMetrics() }
    let expanded = expandFaceRect(faceBounds, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
    let input = lightingInputData(pixelBuffer: pixelBuffer, rect: expanded)

    do {
      try lightingInterpreter?.copy(input, toInputAt: 0)
      try lightingInterpreter?.invoke()
      guard let output = try lightingInterpreter?.output(at: 0) else {
        return PortraitLightingMetrics()
      }
      let probabilities = output.data.withUnsafeBytes { rawBuffer -> [Float32] in
        Array(rawBuffer.bindMemory(to: Float32.self))
      }
      guard let max = probabilities.enumerated().max(by: { $0.element < $1.element }),
        max.offset < lightingLabels.count
      else {
        return PortraitLightingMetrics()
      }
      let confidence = max.element
      guard confidence >= Self.lightingMinConfidence else { return PortraitLightingMetrics() }
      return PortraitLightingMetrics(
        code: labelToCode(lightingLabels[max.offset]),
        confidence: Double(confidence)
      )
    } catch {
      return PortraitLightingMetrics()
    }
  }

  private func lightingInputData(pixelBuffer: CVPixelBuffer, rect: CGRect) -> Data {
    let reader = PixelBufferReader(pixelBuffer: pixelBuffer)
    var floats = Array(repeating: Float32(0), count: Self.lightingSize * Self.lightingSize * 3)
    var index = 0
    let safeRect = clampPixelRect(rect, width: reader.width, height: reader.height)

    for y in 0..<Self.lightingSize {
      for x in 0..<Self.lightingSize {
        let px = Int(safeRect.minX + safeRect.width * (CGFloat(x) + 0.5) / CGFloat(Self.lightingSize))
        let py = Int(safeRect.minY + safeRect.height * (CGFloat(y) + 0.5) / CGFloat(Self.lightingSize))
        let luminance = Float32(reader.lumaAt(x: px, y: py) * 255.0)
        floats[index] = luminance
        floats[index + 1] = luminance
        floats[index + 2] = luminance
        index += 3
      }
    }

    return floats.withUnsafeBufferPointer { Data(buffer: $0) }
  }

  private func estimateBacklightFallback(pixelBuffer: CVPixelBuffer, personBounds: CGRect?) -> PortraitLightingMetrics {
    guard let subjectBounds = personBounds else { return PortraitLightingMetrics() }
    let reader = PixelBufferReader(pixelBuffer: pixelBuffer)
    let frameArea = CGFloat(reader.width * reader.height)
    let subjectArea = subjectBounds.width * subjectBounds.height
    guard frameArea > 0, subjectArea / frameArea >= 0.06 else { return PortraitLightingMetrics() }

    let upperSubject = CGRect(
      x: subjectBounds.minX + subjectBounds.width * 0.20,
      y: subjectBounds.minY + subjectBounds.height * 0.08,
      width: subjectBounds.width * 0.60,
      height: subjectBounds.height * 0.47
    )
    let topBand = CGRect(x: 0, y: 0, width: CGFloat(reader.width), height: CGFloat(reader.height) * 0.35)
    guard let subjectLum = averageLuminance(reader: reader, rect: upperSubject),
      let backgroundLum = averageLuminance(reader: reader, rect: topBand)
    else {
      return PortraitLightingMetrics()
    }

    let contrast = backgroundLum - subjectLum
    if backgroundLum >= 165.0 && subjectLum <= 95.0 && contrast >= 75.0 {
      return PortraitLightingMetrics(
        code: 4.0,
        confidence: min(0.76, 0.62 + ((contrast - 75.0) / 220.0))
      )
    }
    return PortraitLightingMetrics()
  }

  private func averageLuminance(reader: PixelBufferReader, rect: CGRect) -> Double? {
    let safe = clampPixelRect(rect, width: reader.width, height: reader.height)
    guard safe.width > 0, safe.height > 0 else { return nil }
    let stepX = max(1, Int(safe.width) / 24)
    let stepY = max(1, Int(safe.height) / 24)
    var sum = 0.0
    var count = 0
    var y = Int(safe.minY)
    while y < Int(safe.maxY) {
      var x = Int(safe.minX)
      while x < Int(safe.maxX) {
        sum += Double(reader.lumaAt(x: x, y: y) * 255.0)
        count += 1
        x += stepX
      }
      y += stepY
    }
    return count > 0 ? sum / Double(count) : nil
  }

  private func loadLightingModel() {
    guard !lightingLoaded else { return }
    guard let modelPath = findFlutterAssetPath(candidates: [
      "assets/models/lighting_model.tflite",
      "models/lighting_model.tflite",
      "lighting_model.tflite",
    ]),
      let labelPath = findFlutterAssetPath(candidates: [
        "assets/models/lighting_labels.txt",
        "models/lighting_labels.txt",
        "lighting_labels.txt",
      ])
    else {
      return
    }

    do {
      var options = Interpreter.Options()
      options.threadCount = 2
      lightingInterpreter = try Interpreter(modelPath: modelPath, options: options)
      try lightingInterpreter?.allocateTensors()
      lightingLabels = try String(contentsOfFile: labelPath)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      lightingLoaded = true
    } catch {
      lightingInterpreter = nil
      lightingLabels = []
      lightingLoaded = false
    }
  }

  private func findFlutterAssetPath(candidates: [String]) -> String? {
    for candidate in candidates {
      let fileName = (candidate as NSString).lastPathComponent
      let directory = (candidate as NSString).deletingLastPathComponent
      let flutterDirectory = directory.isEmpty ? "flutter_assets" : "flutter_assets/\(directory)"
      if let path = Bundle.main.path(forResource: fileName, ofType: nil, inDirectory: flutterDirectory) {
        return path
      }
      let components = fileName.components(separatedBy: ".")
      if components.count > 1 {
        let name = components.dropLast().joined(separator: ".")
        let ext = components.last
        if let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: flutterDirectory) {
          return path
        }
      }
    }
    return nil
  }

  private func normalizedRectToPixelRect(
    pixelBuffer: CVPixelBuffer,
    left: Double?,
    top: Double?,
    right: Double?,
    bottom: Double?
  ) -> CGRect? {
    guard let left = left, let top = top, let right = right, let bottom = bottom,
      right > left, bottom > top
    else {
      return nil
    }
    let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
    let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
    return CGRect(
      x: CGFloat(left) * width,
      y: CGFloat(top) * height,
      width: CGFloat(right - left) * width,
      height: CGFloat(bottom - top) * height
    )
  }

  private func expandFaceRect(_ faceRect: CGRect, width: Int, height: Int) -> CGRect {
    let center = CGPoint(x: faceRect.midX, y: faceRect.midY)
    let expandedWidth = faceRect.width * 1.35
    let expandedHeight = faceRect.height * 1.55
    return clampPixelRect(
      CGRect(
        x: center.x - expandedWidth / 2,
        y: center.y - expandedHeight / 2,
        width: expandedWidth,
        height: expandedHeight
      ),
      width: width,
      height: height
    )
  }

  private func clampPixelRect(_ rect: CGRect, width: Int, height: Int) -> CGRect {
    let left = min(max(rect.minX, 0), CGFloat(max(0, width - 1)))
    let top = min(max(rect.minY, 0), CGFloat(max(0, height - 1)))
    let right = min(max(rect.maxX, left + 1), CGFloat(width))
    let bottom = min(max(rect.maxY, top + 1), CGFloat(height))
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  private func labelToCode(_ label: String) -> Double {
    switch label {
    case "front_light": return 0.0
    case "short_light": return 1.0
    case "side_light": return 2.0
    case "rim_light": return 3.0
    case "back_light": return 4.0
    default: return 5.0
    }
  }

  private func faceConfidenceStatus(
    bounds: CGRect,
    imageWidth: Int,
    imageHeight: Int,
    hasEyeProb: Bool
  ) -> String {
    guard imageWidth > 0, imageHeight > 0, bounds.width > 0, bounds.height > 0 else {
      return "uncertain"
    }
    if bounds.minX < 0 || bounds.minY < 0 || bounds.maxX > CGFloat(imageWidth)
      || bounds.maxY > CGFloat(imageHeight)
    {
      return "out_of_bounds"
    }
    let imageArea = Double(imageWidth * imageHeight)
    let faceArea = Double(bounds.width * bounds.height)
    if imageArea <= 0 || faceArea / imageArea < 0.006 { return "small" }
    if !hasEyeProb { return "uncertain" }
    return "usable"
  }

  private func imageOrientation(isFrontCamera: Bool) -> UIImage.Orientation {
    switch UIDevice.current.orientation {
    case .portraitUpsideDown:
      return isFrontCamera ? .downMirrored : .down
    case .landscapeLeft:
      return isFrontCamera ? .leftMirrored : .left
    case .landscapeRight:
      return isFrontCamera ? .rightMirrored : .right
    default:
      return isFrontCamera ? .upMirrored : .up
    }
  }

  private func rotationDegreesForCurrentDevice() -> Int {
    switch UIDevice.current.orientation {
    case .landscapeLeft: return 90
    case .portraitUpsideDown: return 180
    case .landscapeRight: return 270
    default: return 0
    }
  }

  private static func nowMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }
}
