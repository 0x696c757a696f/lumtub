import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private(set) var shell: MacShell?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(MainFlutterWindow.firstFrame(for: self), display: true)
    self.title = "Lumtub"
    self.minSize = NSSize(width: 480, height: 360)

    RegisterGeneratedPlugins(registry: flutterViewController)
    shell = MacShell(window: self, messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // Opens centred on the main screen at up to 1280 × 800, like on Windows.
  private static func firstFrame(for window: NSWindow) -> NSRect {
    guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return window.frame }
    let content = NSSize(width: min(1280, max(visible.width - 40, 640)), height: min(800, max(visible.height - 40, 480)))
    var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
    frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
    return frame
  }

  // Picture in picture makes the window borderless, which by default
  // could take neither the keyboard nor the menu bar.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  // The yellow button and ⌘M hide the window to the menu bar icon when the
  // setting is on.
  override func miniaturize(_ sender: Any?) {
    if shell?.minimizeToTray == true {
      orderOut(nil)
    } else {
      super.miniaturize(sender)
    }
  }
}
