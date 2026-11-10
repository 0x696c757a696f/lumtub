import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt
import MediaPlayer

/// The macOS side of lib/windows_shell.dart, on the same method channel:
/// the media keys and Now Playing in Control Center (MPRemoteCommandCenter),
/// the menu bar icon for "close to tray", the installed font families, and
/// the window kept on top or made a picture-in-picture window.
final class MacShell: NSObject, NSWindowDelegate {
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var statusItem: NSStatusItem?
  private var closeToTray = false
  private(set) var minimizeToTray = false
  private var labels: [String: String] = [:]
  private var info: [String: Any] = [:]
  private var artworkAddress = ""
  private var playing = false
  private var pipBefore: (frame: NSRect, style: NSWindow.StyleMask, minSize: NSSize)?
  private var lastPipOrigin: NSPoint?
  private var dragMonitor: Any?
  private var awake: IOPMAssertionID = 0

  /// The app's own title bar (lib/window_frame.dart), on a channel of its
  /// own. The last left press is kept for `performDrag`, as the platform
  /// message arrives after the event is over.
  private let frameChannel: FlutterMethodChannel
  private var customFrame = false
  private var pressMonitor: Any?
  private var lastPress: NSEvent?
  private var reportedMaximized = false

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "lumtub/windows_shell", binaryMessenger: messenger)
    frameChannel = FlutterMethodChannel(name: "lumtub/window_frame", binaryMessenger: messenger)
    self.window = window
    super.init()
    window.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    frameChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleFrame(call, result: result)
    }
    pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      self?.lastPress = event
      return event
    }
    attachCommands()
  }

  // MARK: Own title bar

  private func handleFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let window else {
      result(FlutterMethodNotImplemented)
      return
    }
    switch call.method {
    case "state":
      result(["maximized": window.isZoomed, "active": window.isKeyWindow])
      return
    case "setCustom":
      customFrame = call.arguments as? Bool ?? false
      if pipBefore == nil { applyFrame(to: window) }
    case "minimize":
      window.miniaturize(nil)
    case "toggleMaximize":
      window.zoom(nil)
    case "close":
      window.performClose(nil)
    case "startDrag":
      let current = NSApp.currentEvent?.type == .leftMouseDown ? NSApp.currentEvent : lastPress
      if NSEvent.pressedMouseButtons & 1 != 0, let event = current { window.performDrag(with: event) }
    case "startResize", "setCaption":
      break
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  /// The title bar is hidden and the content runs under it, keeping the
  /// system's shadow, edges and zoom.
  private func applyFrame(to window: NSWindow) {
    window.titlebarAppearsTransparent = customFrame
    window.titleVisibility = customFrame ? .hidden : .visible
    if customFrame {
      window.styleMask.insert(.fullSizeContentView)
    } else {
      window.styleMask.remove(.fullSizeContentView)
    }
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(kind)?.isHidden = customFrame
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "listSystemFonts":
      result(NSFontManager.shared.availableFontFamilies)
      return
    case "setMetadata":
      info[MPMediaItemPropertyTitle] = arguments["title"] as? String ?? ""
      info[MPMediaItemPropertyArtist] = arguments["artist"] as? String ?? ""
      info.removeValue(forKey: MPMediaItemPropertyArtwork)
      loadArtwork(arguments["thumbnail"] as? String ?? "")
      publish()
    case "setStatus":
      let status = call.arguments as? String ?? "stopped"
      playing = status == "playing"
      let center = MPNowPlayingInfoCenter.default()
      switch status {
      case "playing": center.playbackState = .playing
      case "paused": center.playbackState = .paused
      default:
        center.playbackState = .stopped
        info = [:]
      }
      publish()
      updateMenu()
    case "setKeepAwake":
      setKeepAwake(call.arguments as? Bool ?? false)
    case "setTopmost":
      window?.level = (call.arguments as? Bool ?? false) ? .floating : .normal
    case "enterPip":
      let width = arguments["width"] as? Double ?? 498
      let height = arguments["height"] as? Double ?? 280
      enterPip(aspect: arguments["aspect"] as? Double ?? 16 / 9, size: NSSize(width: width, height: height))
    case "exitPip":
      exitPip(keepOnTop: call.arguments as? Bool ?? false)
    case "setPipAspect":
      setPipAspect(call.arguments as? Double ?? 0)
    case "startDrag":
      follow(resize: false)
    case "startResize":
      follow(resize: true)
    case "setButtons":
      let commands = MPRemoteCommandCenter.shared()
      commands.nextTrackCommand.isEnabled = arguments["next"] as? Bool ?? false
      commands.previousTrackCommand.isEnabled = arguments["previous"] as? Bool ?? false
      updateMenu()
    case "setTimeline":
      let position = Double(arguments["position"] as? Int ?? 0) / 1000
      let duration = Double(arguments["duration"] as? Int ?? 0) / 1000
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
      if duration > 0 {
        info[MPMediaItemPropertyPlaybackDuration] = duration
      } else {
        info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
      }
      publish()
    case "setAppIcon":
      // The Dock shows it while Lumtub runs; the app bundle keeps the
      // classic icon, which Finder and the Dock show when it is closed.
      if let data = arguments["png"] as? FlutterStandardTypedData, let image = NSImage(data: data.data) {
        NSApp.applicationIconImage = image
      } else {
        NSApp.applicationIconImage = nil
      }
    case "setTray":
      closeToTray = arguments["enabled"] as? Bool ?? false
      minimizeToTray = arguments["minimize"] as? Bool ?? false
      for key in ["show", "playPause", "next", "exit"] {
        if let label = arguments[key] as? String { labels[key] = label }
      }
      setStatusItem(closeToTray || minimizeToTray)
      if !closeToTray, !minimizeToTray, window?.isVisible == false { showWindow() }
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  private func publish() {
    info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info.isEmpty ? nil : info
  }

  private func loadArtwork(_ address: String) {
    artworkAddress = address
    guard let url = URL(string: address), url.scheme == "https" else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = NSImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self, self.artworkAddress == address, !self.info.isEmpty else { return }
        self.info[MPMediaItemPropertyArtwork] = MacShell.artwork(image)
        self.publish()
      }
    }.resume()
  }

  /// Made outside the main queue's closures: MediaPlayer asks for the
  /// picture on a queue of its own.
  private nonisolated static func artwork(_ image: NSImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
  }

  /// Keeps the display from sleeping while a video plays.
  private func setKeepAwake(_ on: Bool) {
    if on, awake == 0 {
      var id: IOPMAssertionID = 0
      let made = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Lumtub is playing a video" as CFString, &id)
      if made == kIOReturnSuccess { awake = id }
    } else if !on, awake != 0 {
      IOPMAssertionRelease(awake)
      awake = 0
    }
  }

  private func send(_ button: String) {
    channel.invokeMethod("button", arguments: button)
  }

  private func attachCommands() {
    let commands = MPRemoteCommandCenter.shared()
    let buttons: [(MPRemoteCommand, String)] = [
      (commands.playCommand, "play"),
      (commands.pauseCommand, "pause"),
      (commands.togglePlayPauseCommand, "playpause"),
      (commands.stopCommand, "stop"),
      (commands.nextTrackCommand, "next"),
      (commands.previousTrackCommand, "previous"),
    ]
    for (command, button) in buttons {
      command.isEnabled = button != "next" && button != "previous"
      command.addTarget { [weak self] _ in
        self?.send(button)
        return .success
      }
    }
    commands.changePlaybackPositionCommand.isEnabled = true
    commands.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      self?.channel.invokeMethod("seek", arguments: Int(event.positionTime * 1000))
      return .success
    }
  }

  // MARK: Picture in picture

  private func enterPip(aspect: Double, size: NSSize) {
    guard let window, pipBefore == nil, !window.styleMask.contains(.fullScreen), aspect > 0 else { return }
    pipBefore = (window.frame, window.styleMask, window.minSize)
    window.styleMask = [.borderless, .resizable]
    window.hasShadow = true
    window.minSize = NSSize(width: 120, height: 120)
    window.level = .floating
    window.contentAspectRatio = NSSize(width: aspect, height: 1)
    let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
    var origin = NSPoint(x: area.maxX - size.width - 16, y: area.minY + 16)
    if let last = lastPipOrigin {
      origin.x = min(max(last.x, area.minX), max(area.minX, area.maxX - size.width))
      origin.y = min(max(last.y, area.minY), max(area.minY, area.maxY - size.height))
    }
    window.setFrame(NSRect(origin: origin, size: size), display: true)
    refocus(window)
  }

  /// A changed style mask can take the keyboard from the Flutter view.
  private func refocus(_ window: NSWindow) {
    window.makeKeyAndOrderFront(nil)
    if let view = (window as? MainFlutterWindow)?.flutterView ?? window.contentViewController?.view { window.makeFirstResponder(view) }
  }

  private func exitPip(keepOnTop: Bool) {
    guard let window, let before = pipBefore else { return }
    pipBefore = nil
    lastPipOrigin = window.frame.origin
    window.styleMask = before.style
    // Setting the increments clears the kept ratio.
    window.contentResizeIncrements = NSSize(width: 1, height: 1)
    window.minSize = before.minSize
    window.level = keepOnTop ? .floating : .normal
    window.setFrame(before.frame, display: true)
    applyFrame(to: window)
    refocus(window)
  }

  private func setPipAspect(_ aspect: Double) {
    guard let window, pipBefore != nil, aspect > 0 else { return }
    let frame = window.frame
    let height = frame.width / aspect
    window.contentAspectRatio = NSSize(width: aspect, height: 1)
    window.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
  }

  /// Moves the window with the pointer, or resizes it from the bottom-right
  /// corner keeping its ratio, until the button is released.
  private func follow(resize: Bool) {
    guard let window, NSEvent.pressedMouseButtons & 1 != 0 else { return }
    if let monitor = dragMonitor { NSEvent.removeMonitor(monitor) }
    let start = NSEvent.mouseLocation
    let frame = window.frame
    let ratio = window.contentAspectRatio
    dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
      guard let self, let window = self.window else { return event }
      if event.type == .leftMouseUp {
        if let monitor = self.dragMonitor { NSEvent.removeMonitor(monitor) }
        self.dragMonitor = nil
        return event
      }
      let now = NSEvent.mouseLocation
      let dx = now.x - start.x, dy = now.y - start.y
      if resize {
        let width = max(160, frame.width + dx)
        let height = ratio.width > 0 ? width * ratio.height / ratio.width : max(90, frame.height - dy)
        window.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height), display: true)
      } else {
        window.setFrameOrigin(NSPoint(x: frame.minX + dx, y: frame.minY + dy))
      }
      return event
    }
  }

  // MARK: Menu bar icon

  private func setStatusItem(_ on: Bool) {
    if !on {
      if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
      statusItem = nil
      return
    }
    if statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      let image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Lumtub")
      image?.isTemplate = true
      item.button?.image = image
      item.button?.toolTip = "Lumtub"
      statusItem = item
    }
    updateMenu()
  }

  private func updateMenu() {
    guard let item = statusItem else { return }
    let menu = NSMenu()
    func add(_ key: String, _ fallback: String, _ action: Selector, enabled: Bool = true) {
      let entry = NSMenuItem(title: labels[key] ?? fallback, action: action, keyEquivalent: "")
      entry.target = self
      entry.isEnabled = enabled
      menu.addItem(entry)
    }
    add("show", "Show", #selector(showWindow))
    menu.addItem(.separator())
    add("playPause", "Play/Pause", #selector(playPause))
    add("next", "Next", #selector(playNext), enabled: MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
    menu.addItem(.separator())
    add("exit", "Quit", #selector(quit))
    menu.autoenablesItems = false
    item.menu = menu
  }

  @objc func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  @objc private func playPause() { send("playpause") }
  @objc private func playNext() { send("next") }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  // MARK: NSWindowDelegate

  func windowDidResize(_ notification: Notification) {
    guard let window, window.isZoomed != reportedMaximized else { return }
    reportedMaximized = window.isZoomed
    frameChannel.invokeMethod("maximized", arguments: reportedMaximized)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    frameChannel.invokeMethod("active", arguments: true)
  }

  func windowDidResignKey(_ notification: Notification) {
    frameChannel.invokeMethod("active", arguments: false)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard closeToTray else { return true }
    sender.orderOut(nil)
    return false
  }
}
