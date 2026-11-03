import Cocoa
import FlutterMacOS
import MediaPlayer

/// The macOS side of lib/windows_shell.dart, on the same method channel:
/// the media keys and Now Playing in Control Center (MPRemoteCommandCenter),
/// the menu bar icon for "close to tray", and the installed font families.
final class MacShell: NSObject, NSWindowDelegate {
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var statusItem: NSStatusItem?
  private var closeToTray = false
  private var labels: [String: String] = [:]
  private var info: [String: Any] = [:]
  private var artworkAddress = ""
  private var playing = false

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "lumtub/windows_shell", binaryMessenger: messenger)
    self.window = window
    super.init()
    window.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    attachCommands()
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
    case "setTray":
      closeToTray = arguments["enabled"] as? Bool ?? false
      for key in ["show", "playPause", "next", "exit"] {
        if let label = arguments[key] as? String { labels[key] = label }
      }
      setStatusItem(closeToTray)
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
        self.info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.publish()
      }
    }.resume()
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

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard closeToTray else { return true }
    sender.orderOut(nil)
    return false
  }
}
