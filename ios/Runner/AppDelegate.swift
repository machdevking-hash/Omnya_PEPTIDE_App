import Flutter
import HealthKit
import UIKit
import UserNotifications
import Vision
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Reminders show while the app is open, and taps reach flutter_local_notifications.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OmnyaNative")!
    let channel = FlutterMethodChannel(name: "omnya/native", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler(OmnyaNative.handle)
  }
}

/// Everything here runs on the phone. Nothing is sent anywhere.
enum OmnyaNative {
  static let health = HKHealthStore()
  static let appGroup = "group.com.omnya.omnya"

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "latestWeightLbs": latestWeight(result)
    case "scorePhoto": scorePhoto(args["path"] as? String ?? "", result)
    case "blurFaces": blurFaces(args["path"] as? String ?? "", result)
    case "updateWidget":
      UserDefaults(suiteName: appGroup)?.set(args["json"] as? String, forKey: "widget")
      WidgetCenter.shared.reloadAllTimelines()
      if #available(iOS 16.2, *) { ShotDayActivity.sync(args["activity"] as? [String: Any]) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  // Apple Health ------------------------------------------------------------

  /// Her most recent body weight in pounds, or nil when Health has none or she declined.
  static func latestWeight(_ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable(), let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
      return result(nil)
    }
    health.requestAuthorization(toShare: nil, read: [type]) { _, _ in
      let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
      let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
        let sample = samples?.first as? HKQuantitySample
        let value = sample?.quantity.doubleValue(for: .pound())
        DispatchQueue.main.async {
          result(value == nil ? nil : ["lbs": value!, "at": sample!.endDate.timeIntervalSince1970 * 1000])
        }
      }
      health.execute(query)
    }
  }

  // Photos ------------------------------------------------------------------

  /// Two measures from the largest face, both independent of distance and exposure:
  /// fullness (face width over height) and evenness (1 minus the spread of skin brightness).
  static func scorePhoto(_ path: String, _ result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = upright(path) else { return reply(result, nil) }
      let request = VNDetectFaceLandmarksRequest()
      try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
      guard let face = (request.results ?? []).max(by: { area($0) < area($1) }) else { return reply(result, nil) }

      var fullness = Double(face.boundingBox.width * CGFloat(image.width)) / Double(face.boundingBox.height * CGFloat(image.height))
      if let contour = face.landmarks?.faceContour?.normalizedPoints, contour.count > 2 {
        // The jaw contour is steadier than the box: its width over the box height.
        let xs = contour.map { $0.x }
        fullness = Double((xs.max()! - xs.min()!) * face.boundingBox.width * CGFloat(image.width))
          / Double(face.boundingBox.height * CGFloat(image.height))
      }
      let evenness = skinEvenness(image, face.boundingBox)
      reply(result, ["fullness": fullness, "evenness": evenness as Any])
    }
  }

  static func area(_ f: VNFaceObservation) -> CGFloat { f.boundingBox.width * f.boundingBox.height }

  /// Brightness spread over the middle of the face, scaled so 1 is perfectly even.
  static func skinEvenness(_ image: CGImage, _ box: CGRect) -> Double? {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    // Cheeks and forehead: the centre of the face box, away from eyes, brows and hair.
    let rect = CGRect(
      x: (box.minX + box.width * 0.25) * w,
      y: (1 - box.maxY + box.height * 0.3) * h,
      width: box.width * 0.5 * w,
      height: box.height * 0.4 * h
    ).integral
    guard let crop = image.cropping(to: rect) else { return nil }
    let side = 48
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let ctx = CGContext(
      data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
    var lum = [Double]()
    for i in stride(from: 0, to: pixels.count, by: 4) {
      lum.append(0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2]))
    }
    let mean = lum.reduce(0, +) / Double(lum.count)
    guard mean > 0 else { return nil }
    let sd = sqrt(lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count))
    return max(0, 1 - sd / mean)
  }

  /// The photo as JPEG with every face heavily blurred, for sharing.
  static func blurFaces(_ path: String, _ result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let cg = upright(path) else { return reply(result, nil) }
      let request = VNDetectFaceRectanglesRequest()
      try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
      let input = CIImage(cgImage: cg)
      let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: Double(max(cg.width, cg.height)) / 25).cropped(to: input.extent)
      var output = input
      for face in request.results ?? [] {
        let b = face.boundingBox
        // Pad the box so hairline and chin are covered too.
        let rect = CGRect(
          x: (b.minX - b.width * 0.25) * CGFloat(cg.width), y: (b.minY - b.height * 0.25) * CGFloat(cg.height),
          width: b.width * 1.5 * CGFloat(cg.width), height: b.height * 1.6 * CGFloat(cg.height))
        output = blurred.cropped(to: rect).composited(over: output)
      }
      let context = CIContext()
      guard let out = context.createCGImage(output, from: input.extent),
        let data = UIImage(cgImage: out).jpegData(compressionQuality: 0.9)
      else { return reply(result, nil) }
      reply(result, FlutterStandardTypedData(bytes: data))
    }
  }

  /// Camera JPEGs carry their rotation in EXIF; Vision and Core Image want the pixels upright.
  static func upright(_ path: String) -> CGImage? {
    guard let ui = UIImage(contentsOfFile: path) else { return nil }
    if ui.imageOrientation == .up { return ui.cgImage }
    let format = UIGraphicsImageRendererFormat()
    format.scale = ui.scale
    return UIGraphicsImageRenderer(size: ui.size, format: format).image { _ in ui.draw(at: .zero) }.cgImage
  }

  static func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }
}
