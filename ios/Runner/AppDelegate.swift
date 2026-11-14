import AVFoundation
import AuthenticationServices
import Flutter
import UIKit
import WebKit

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
final class LumtubShell: NSObject, FlutterPlugin, UIDocumentPickerDelegate, ASWebAuthenticationPresentationContextProviding {
  /// The answer to the 'saveFile' call whose picker is open.
  private var saving: FlutterResult?
  private var savedFile: URL?
  /// Google's sign-in page, shown over the app while it is open.
  private var signIn: ASWebAuthenticationSession?
  /// The page signing in to YouTube for its cookies, while it is open.
  private var webSignIn: WebSignInController?

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
    case "saveFile":
      saveFile(call.arguments as? [String: Any], result: result)
    case "signInPage":
      // Google sends the page back to a server Lumtub runs on 127.0.0.1.
      // Safari would send Lumtub to the background, where iOS suspends it
      // and the server cannot answer; this sheet keeps Lumtub in front.
      guard let text = call.arguments as? String, let url = URL(string: text) else {
        result(FlutterError(code: "bad_url", message: "Not an address", details: nil))
        return
      }
      signIn?.cancel()
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lumtub") { [weak self] _, _ in
        self?.signIn = nil
      }
      session.presentationContextProvider = self
      signIn = session
      result(session.start() ? nil : FlutterError(code: "not_opened", message: "The sign-in page did not open", details: nil))
    case "closeSignInPage":
      signIn?.cancel()
      signIn = nil
      result(nil)
    case "webSignIn":
      // No other app's cookies can be read, so Google's sign-in opens in a
      // page of Lumtub's own, as on Android (WebSignInActivity.kt).
      guard let root = LumtubShell.topController() else {
        result(FlutterError(code: "no_window", message: "Nothing to sign in from", details: nil))
        return
      }
      webSignIn?.finish(nil)
      let page = WebSignInController { [weak self] path in
        self?.webSignIn = nil
        result(path)
      }
      webSignIn = page
      root.present(page.wrapped, animated: true)
    case "isTv":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Hands {name, mime, bytes} to the system's "Save to Files" sheet;
  /// answers true once saved, false when cancelled.
  private func saveFile(_ arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let name = arguments?["name"] as? String,
      let bytes = arguments?["bytes"] as? FlutterStandardTypedData,
      let root = LumtubShell.topController()
    else {
      result(FlutterError(code: "bad_arguments", message: "Nothing to save", details: nil))
      return
    }
    if let pending = saving {
      pending(false)
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent((name as NSString).lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try bytes.data.write(to: file, options: .atomic)
    } catch {
      result(FlutterError(code: "write_failed", message: "\(error)", details: nil))
      return
    }
    saving = result
    savedFile = file
    let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
    picker.delegate = self
    root.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishSaving(true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishSaving(false)
  }

  private func finishSaving(_ saved: Bool) {
    saving?(saved)
    saving = nil
    if let file = savedFile {
      try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
    savedFile = nil
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first ?? ASPresentationAnchor()
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

/// Google's sign-in to YouTube in a page of Lumtub's own, for the cookies
/// members-only videos and community posts need. Only the sign-in is shown;
/// nothing is played in it. The page keeps nothing on the device: once YouTube
/// shows signed in, the youtube.com cookies go to a file only this app can
/// read (the core takes them and wipes it), and the page's data goes with it.
final class WebSignInController: UIViewController, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
  private static let signInAddress = "https://accounts.google.com/ServiceLogin?service=youtube&passive=true"
    + "&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26next%3Dhttps%253A%252F%252Fm.youtube.com%252F"

  private let done: (String?) -> Void
  private var finished = false
  private var web: WKWebView?

  init(done: @escaping (String?) -> Void) {
    self.done = done
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  /// The page inside a bar with a Cancel button.
  lazy var wrapped: UINavigationController = {
    let navigation = UINavigationController(rootViewController: self)
    navigation.presentationController?.delegate = self
    return navigation
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    // Google turns away pages that call themselves an app's web view;
    // this one is only the sign-in, as in Safari.
    let major = UIDevice.current.systemVersion.split(separator: ".").first ?? "18"
    configuration.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"
    let web = WKWebView(frame: view.bounds, configuration: configuration)
    web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    web.navigationDelegate = self
    web.isOpaque = false
    web.backgroundColor = .systemBackground
    view.addSubview(web)
    self.web = web
    if let url = URL(string: WebSignInController.signInAddress) {
      web.load(URLRequest(url: url))
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let scheme = navigationAction.request.url?.scheme?.lowercased()
    decisionHandler(scheme == "https" || scheme == "http" || scheme == "about" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    title = webView.url?.host
    guard let host = webView.url?.host?.lowercased(), host == "youtube.com" || host.hasSuffix(".youtube.com") else { return }
    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
      self?.take(cookies)
    }
  }

  /// Keeps the cookies once YouTube shows the account signed in.
  private func take(_ cookies: [HTTPCookie]) {
    if finished { return }
    var seen = Set<String>()
    var pairs: [String] = []
    for cookie in cookies {
      let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
      guard domain == "youtube.com" || domain.hasSuffix(".youtube.com"), seen.insert(cookie.name).inserted else { continue }
      pairs.append("\(cookie.name)=\(cookie.value)")
    }
    guard seen.contains("SAPISID") || seen.contains("__Secure-3PAPISID") else { return }
    let manager = FileManager.default
    guard let folder = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let file = folder.appendingPathComponent("web-sign-in.txt")
    do {
      try manager.createDirectory(at: folder, withIntermediateDirectories: true)
      try? manager.removeItem(at: file)
      manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600, .protectionKey: FileProtectionType.complete])
      try Data(pairs.joined(separator: "; ").utf8).write(to: file, options: [.completeFileProtection])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var marked = file
      try? marked.setResourceValues(values)
    } catch {
      NSLog("Lumtub: could not keep the sign-in: \(error)")
      return
    }
    finish(file.path)
  }

  @objc private func cancel() {
    finish(nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(nil)
  }

  /// Answers once, closes the page and drops everything it held.
  func finish(_ path: String?) {
    if finished { return }
    finished = true
    if let web = web {
      web.stopLoading()
      web.navigationDelegate = nil
      web.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
    web = nil
    if wrapped.presentingViewController != nil {
      wrapped.dismiss(animated: true)
    }
    done(path)
  }
}
