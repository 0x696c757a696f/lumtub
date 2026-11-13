import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Videos keep their sound with the silent switch on and while the app
    // is in the background, as in other video apps.
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    } catch {
      NSLog("Lumtub: could not set the audio session: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LumtubShell") {
      LumtubShell.register(with: registrar)
    }
  }
}

/// The few system calls the Dart side asks for on 'lumtub/windows_shell',
/// with the method names the Android version uses.
final class LumtubShell: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "lumtub/windows_shell", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LumtubShell(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openUrl":
      guard let text = call.arguments as? String, let url = URL(string: text) else {
        result(FlutterError(code: "bad_url", message: "Not an address", details: nil))
        return
      }
      UIApplication.shared.open(url) { opened in
        result(opened ? nil : FlutterError(code: "not_opened", message: "Nothing opened \(text)", details: nil))
      }
    case "shareText":
      guard let text = call.arguments as? String, let root = LumtubShell.topController() else {
        result(FlutterError(code: "no_window", message: "Nothing to share from", details: nil))
        return
      }
      let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      // An iPad shows the sheet as a popover, which needs an anchor.
      if let popover = sheet.popoverPresentationController {
        popover.sourceView = root.view
        popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }
      root.present(sheet, animated: true)
      result(nil)
    case "isTv":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
