import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private(set) var shell: MacShell?
  private var flutterViewController: FlutterViewController?
  var flutterView: NSView? { flutterViewController?.view }
  /// The blurred desktop behind Flutter while a glass skin sees through.
  private let behind = NSVisualEffectView()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.flutterViewController = flutterViewController
    // Flutter's view sits in a plain container, over the desktop blur.
    let container = NSViewController()
    container.view = NSView(frame: flutterViewController.view.frame)
    container.addChild(flutterViewController)
    behind.frame = container.view.bounds
    behind.autoresizingMask = [.width, .height]
    behind.blendingMode = .behindWindow
    behind.state = .followsWindowActiveState
    behind.isHidden = true
    container.view.addSubview(behind)
    flutterViewController.view.frame = container.view.bounds
    flutterViewController.view.autoresizingMask = [.width, .height]
    container.view.addSubview(flutterViewController.view)
    self.contentViewController = container
    self.initialFirstResponder = flutterViewController.view
    self.makeFirstResponder(flutterViewController.view)
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

  /// The desktop shows, blurred, wherever Flutter leaves the window clear.
  func setSeeThrough(_ on: Bool, dark: Bool) {
    behind.material = .underWindowBackground
    behind.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    behind.isHidden = !on
    isOpaque = !on
    backgroundColor = on ? .clear : .windowBackgroundColor
    flutterViewController?.backgroundColor = on ? .clear : .black
    invalidateShadow()
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
