// Lumtub: libmpv's avfoundation video output (vo=avfoundation, see
// media_kit_libs_ios_video/ios/patch) hands its pictures to a `VideoSink`,
// which shows them in an AVSampleBufferDisplayLayer instead of an OpenGL ES
// texture. That layer is what iOS picture in picture takes, and frames
// decoded by VideoToolbox go to it as they are. Each player has one layer,
// shown in whichever `PlayerLayerView` Flutter made last, and kept for as
// long as the app runs: mpv holds the sink's address (--wid) for as long as
// the player lives.

import AVFoundation
import AVKit
import Flutter
import UIKit

final class PlayerLayer: NSObject {
  typealias EventSink = (_ event: String, _ seconds: Double?) -> Void

  let displayLayer: AVSampleBufferDisplayLayer
  /// Holds `displayLayer`, moved into the newest host view.
  let surface = PlayerSurface()
  /// What libmpv's video output draws through.
  private let sink: VideoSink
  private let events: EventSink
  private let timebase: CMTimebase?
  private var hosts = [WeakHost]()

  private var duration = 0.0
  private var playing = false
  private var live = false
  private var pipObject: AnyObject?

  init(events: @escaping EventSink) {
    self.events = events
    let displayLayer = AVSampleBufferDisplayLayer()
    displayLayer.videoGravity = .resizeAspect
    displayLayer.backgroundColor = UIColor.black.cgColor
    var timebase: CMTimebase?
    CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault,
      sourceClock: CMClockGetHostTimeClock(),
      timebaseOut: &timebase
    )
    if let timebase {
      CMTimebaseSetTime(timebase, time: .zero)
      CMTimebaseSetRate(timebase, rate: 0)
      displayLayer.controlTimebase = timebase
    }
    self.displayLayer = displayLayer
    self.timebase = timebase
    sink = VideoSink(displayLayer: displayLayer, timebase: timebase)
    super.init()
    surface.displayLayer = displayLayer
    surface.subtitleLayer = sink.subtitles
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
  }

  /// The address mpv takes as --wid: the sink's host, not a layer.
  var address: Int64 {
    Int64(Int(bitPattern: sink.host))
  }

  // MARK: Host views

  func attach(_ host: PlayerLayerView) {
    hosts.removeAll { $0.view == nil || $0.view === host }
    hosts.append(WeakHost(view: host))
    host.adopt(surface)
    // Made ahead: picture in picture becomes possible only a while after
    // its controller sees the layer on screen with a picture.
    if #available(iOS 15.0, *) { _ = pip }
  }

  func detach(_ host: PlayerLayerView) {
    hosts.removeAll { $0.view == nil || $0.view === host }
    guard surface.superview === host else { return }
    surface.removeFromSuperview()
    if let last = hosts.last?.view { last.adopt(surface) }
  }

  // MARK: Playback state, for the picture-in-picture window

  /// Where playback is, from Dart: the layer's clock follows it, and picture
  /// in picture shows it.
  func update(position: Double, duration: Double, playing: Bool, rate: Double, live: Bool) {
    self.duration = duration
    self.playing = playing
    self.live = live
    if let timebase {
      CMTimebaseSetRateAndAnchorTime(
        timebase,
        rate: playing ? rate : 0,
        anchorTime: CMTime(seconds: max(0, position), preferredTimescale: 1000),
        immediateSourceTime: CMClockGetTime(CMClockGetHostTimeClock())
      )
    }
    if #available(iOS 15.0, *) {
      (pipObject as? AVPictureInPictureController)?.invalidatePlaybackState()
    }
  }

  /// The eye-care warm light, multiplied over the picture (opaque white:
  /// none); see `PlayerSurface.warm`.
  func setWarmth(argb: UInt32) {
    surface.setWarmth(argb: argb)
  }

  /// Mirrors the picture (mpv's hflip filter can't take VideoToolbox
  /// frames).
  func setMirror(_ on: Bool) {
    sink.setMirror(on)
  }

  /// Subtitles are drawn by libmpv and shown in a layer of their own above
  /// the picture; picture in picture shows only the picture, so while it is
  /// open they go into the frames instead.
  private func compositeSubtitles(_ on: Bool) {
    sink.setCompositing(on)
  }

  /// One subtitle line the app shows where libmpv draws none, for picture
  /// in picture: its size and outline in canvas pixels.
  struct AppSubtitle {
    let text: String
    let font: String
    let size: CGFloat
    let color: UIColor
    let outline: CGFloat
    let bold: Bool
    let box: UIColor?
  }

  /// Drawn here with Core Text, not by Flutter: iOS gives a backgrounded
  /// app no GPU, so Flutter can't make pictures while the window shows.
  private static let subtitleQueue = DispatchQueue(label: "lumtub.pip.subtitles", qos: .userInitiated)

  /// Subtitles the app shows, for picture in picture where libmpv draws
  /// none: [lines] top to bottom, centred on a [canvas] the picture's shape,
  /// the last line's bottom at [bottom]. No lines take them away.
  func setAppSubtitles(_ lines: [AppSubtitle], canvas: CGSize, bottom: CGFloat, spacing: CGFloat) {
    let sink = self.sink
    Self.subtitleQueue.async {
      guard let drawn = Self.drawSubtitles(lines, canvas: canvas, bottom: bottom, spacing: spacing) else {
        sink.setAppOverlay(nil, box: .zero, canvas: .zero)
        return
      }
      sink.setAppOverlay(drawn.image, box: drawn.box, canvas: canvas)
    }
  }

  private static func subtitleFont(_ family: String, size: CGFloat, bold: Bool) -> UIFont {
    var font = !family.isEmpty && !UIFont.fontNames(forFamilyName: family).isEmpty
      ? UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: family]), size: size)
      : UIFont.systemFont(ofSize: size)
    if bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
      font = UIFont(descriptor: descriptor, size: size)
    }
    return font
  }

  private static func drawSubtitles(_ lines: [AppSubtitle], canvas: CGSize, bottom: CGFloat, spacing: CGFloat) -> (image: CGImage, box: CGRect)? {
    guard canvas.width > 0, canvas.height > 0 else { return nil }
    let room = canvas.width * 0.9
    var laid = [(fill: NSAttributedString, stroke: NSAttributedString?, size: CGSize)]()
    for line in lines where !line.text.isEmpty {
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      paragraph.lineBreakMode = .byWordWrapping
      paragraph.minimumLineHeight = line.size * 1.3
      paragraph.maximumLineHeight = line.size * 1.3
      var look: [NSAttributedString.Key: Any] = [
        .font: subtitleFont(line.font, size: line.size, bold: line.bold),
        .foregroundColor: line.color,
        .paragraphStyle: paragraph,
      ]
      if let box = line.box { look[.backgroundColor] = box }
      let fill = NSAttributedString(string: line.text, attributes: look)
      var stroke: NSAttributedString?
      if line.outline > 0 {
        var outline = look
        outline.removeValue(forKey: .backgroundColor)
        var alpha: CGFloat = 1
        line.color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        outline[.strokeColor] = UIColor.black.withAlphaComponent(alpha)
        // A positive width strokes without filling, in percent of the size;
        // half of it falls outside the letters.
        outline[.strokeWidth] = line.outline * 2 / line.size * 100
        stroke = NSAttributedString(string: line.text, attributes: outline)
      }
      let bounds = fill.boundingRect(
        with: CGSize(width: room, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
      laid.append((fill, stroke, CGSize(width: ceil(bounds.width), height: ceil(bounds.height))))
    }
    guard !laid.isEmpty else { return nil }
    let pad = ceil(lines.map(\.outline).max() ?? 0) + 1
    let width = (laid.map(\.size.width).max() ?? 0) + 2 * pad
    let height = laid.reduce(0) { $0 + $1.size.height } + spacing * CGFloat(laid.count - 1) + 2 * pad
    guard width > 0, height > 0 else { return nil }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
      context.cgContext.setLineJoin(.round)
      context.cgContext.setLineCap(.round)
      var top = pad
      for line in laid {
        let rect = CGRect(x: (width - line.size.width) / 2, y: top, width: line.size.width, height: line.size.height)
        line.stroke?.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        line.fill.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        top += line.size.height + spacing
      }
    }
    guard let picture = image.cgImage else { return nil }
    let y = max(0, min(bottom, canvas.height) - height)
    return (picture, CGRect(x: (canvas.width - width) / 2, y: y, width: width, height: height))
  }

  @objc private func didBecomeActive() {
    // iOS interrupts the layer while the app is in the background.
    sink.resume()
  }

  /// Back from the background, the video belongs in the app again: the
  /// floating window closes. Only a return from the background counts, so a
  /// window opened with the app on screen stays.
  @objc private func willEnterForeground() {
    stopPip()
  }

  // MARK: Picture in picture

  @available(iOS 15.0, *)
  private var pip: AVPictureInPictureController? {
    if let made = pipObject as? AVPictureInPictureController { return made }
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return nil }
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let made = AVPictureInPictureController(contentSource: source)
    made.delegate = self
    made.requiresLinearPlayback = false
    pipObject = made
    return made
  }

  var pipSupported: Bool {
    if #available(iOS 15.0, *) { return AVPictureInPictureController.isPictureInPictureSupported() }
    return false
  }

  var pipActive: Bool {
    if #available(iOS 15.0, *) { return (pipObject as? AVPictureInPictureController)?.isPictureInPictureActive ?? false }
    return false
  }

  /// Starts picture in picture; false when this device or the moment can't.
  func startPip() -> Bool {
    guard #available(iOS 15.0, *) else { return false }
    guard let pip else { return false }
    if pip.isPictureInPictureActive { return true }
    if pip.isPictureInPicturePossible {
      pip.startPictureInPicture()
      return true
    }
    // Not yet possible (the controller was just made, or the picture just
    // came): one more try a moment later.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak pip] in
      guard let self, let pip else { return }
      if pip.isPictureInPicturePossible {
        pip.startPictureInPicture()
      } else {
        self.events("failed:picture in picture is not possible now", nil)
      }
    }
    return true
  }

  func stopPip() {
    if #available(iOS 15.0, *) {
      (pipObject as? AVPictureInPictureController)?.stopPictureInPicture()
    }
  }

  /// Whether going to the Home Screen while the video plays opens picture
  /// in picture.
  func setAutoPip(_ on: Bool) {
    if #available(iOS 15.0, *) {
      if on {
        pip?.canStartPictureInPictureAutomaticallyFromInline = true
      } else {
        (pipObject as? AVPictureInPictureController)?.canStartPictureInPictureAutomaticallyFromInline = false
      }
    }
  }
}

@available(iOS 15.0, *)
extension PlayerLayer: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    self.playing = playing
    events(playing ? "play" : "pause", nil)
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    if live || duration <= 0 {
      return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    return CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 1000))
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    !playing
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    events("skip", skipInterval.seconds)
    completionHandler()
  }
}

@available(iOS 15.0, *)
extension PlayerLayer: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    compositeSubtitles(true)
    events("willStart", nil)
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    events("started", nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    compositeSubtitles(false)
    events("failed:\(error.localizedDescription)", nil)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    compositeSubtitles(false)
    events("stopped", nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    events("restore", nil)
    completionHandler(true)
  }
}

private struct WeakHost {
  weak var view: PlayerLayerView?
}

/// Holds the display layer and keeps it the size of the view it is in.
final class PlayerSurface: UIView {
  var displayLayer: AVSampleBufferDisplayLayer? {
    didSet {
      oldValue?.removeFromSuperlayer()
      if let displayLayer { layer.insertSublayer(displayLayer, at: 0) }
    }
  }

  /// The subtitles, above the picture and below the warm light.
  var subtitleLayer: CALayer? {
    didSet {
      oldValue?.removeFromSuperlayer()
      if let subtitleLayer { layer.insertSublayer(subtitleLayer, below: warm) }
    }
  }

  /// The eye-care warm light: a colour multiplied into the picture by Core
  /// Animation, so black stays black and white takes the colour. Above the
  /// display layer, not in it: picture in picture shows the picture as it
  /// is.
  private let warm = CALayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    isUserInteractionEnabled = false
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    warm.compositingFilter = "multiplyBlendMode"
    warm.isHidden = true
    layer.addSublayer(warm)
  }

  func setWarmth(argb: UInt32) {
    let white = argb & 0x00FF_FFFF == 0x00FF_FFFF
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    warm.isHidden = white
    warm.backgroundColor = UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: 1
    ).cgColor
    CATransaction.commit()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    displayLayer?.frame = bounds
    subtitleLayer?.frame = bounds
    warm.frame = bounds
    CATransaction.commit()
  }
}

/// The view Flutter places where the picture goes (a UiKitView).
final class PlayerLayerView: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    isUserInteractionEnabled = false
    clipsToBounds = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func adopt(_ surface: PlayerSurface) {
    surface.removeFromSuperview()
    surface.frame = bounds
    addSubview(surface)
  }
}

/// Makes the `PlayerLayerView`s for Flutter's UiKitView.
final class PlayerLayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let layers: (Int64) -> PlayerLayer?

  init(layers: @escaping (Int64) -> PlayerLayer?) {
    self.layers = layers
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let handle = ((args as? [String: Any])?["handle"] as? NSNumber)?.int64Value
    return PlayerLayerPlatformView(frame: frame, layer: handle.flatMap(layers))
  }
}

final class PlayerLayerPlatformView: NSObject, FlutterPlatformView {
  private let host: PlayerLayerView
  private weak var player: PlayerLayer?

  init(frame: CGRect, layer: PlayerLayer?) {
    host = PlayerLayerView(frame: frame)
    player = layer
    super.init()
    layer?.attach(host)
  }

  deinit {
    let host = self.host
    let player = self.player
    if Thread.isMainThread {
      player?.detach(host)
    } else {
      DispatchQueue.main.async { player?.detach(host) }
    }
  }

  func view() -> UIView { host }
}
