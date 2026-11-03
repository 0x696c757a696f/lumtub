import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private(set) var shell: MacShell?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Lumtub"
    self.minSize = NSSize(width: 480, height: 360)

    RegisterGeneratedPlugins(registry: flutterViewController)
    shell = MacShell(window: self, messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
