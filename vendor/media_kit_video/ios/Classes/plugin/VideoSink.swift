// Lumtub: shows what libmpv's avfoundation video output hands over
// (media_kit_libs_ios_video/ios/patch/0004-avfoundation-video-output.patch).
// The output is plain C: it gives each picture (a CVPixelBuffer) and a
// picture of the subtitles and OSD (a CGImage) to this class through the
// struct whose address it takes as --wid, and holds no Objective-C or Swift
// object itself. Here they are turned, mirrored and zoomed, put in sample
// buffers for the AVSampleBufferDisplayLayer (which picture in picture
// takes), and the subtitles shown in a layer over the picture, or drawn into
// the frames while picture in picture is open (it shows the frames alone).

import AVFoundation
import CoreImage
import Metal
import UIKit

/// `struct lumtub_vo_host` in the patch: seven 8-byte slots.
private enum Host {
  static let size = 56
  /// "LUMTUBV1": the output checks it before it calls anything.
  static let magic: UInt64 = 0x4C55_4D54_5542_5631
  static let magicOffset = 0
  static let contextOffset = 8
  static let frameOffset = 16
  static let overlayOffset = 24
  static let clearOffset = 32
  static let maxHeightOffset = 40
  /// The view's shape, which the subtitles' canvas takes (0: the picture's).
  static let canvasAspectOffset = 48
}

private typealias FrameCall = @convention(c) (
  UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int64, Double
) -> Bool
private typealias OverlayCall = @convention(c) (
  UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Double, Double, Double, Double, Double, Double
) -> Void
private typealias ClearCall = @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void

/// The subtitles' picture and where it goes, handed to the main thread.
/// A CGImage never changes once made.
struct Overlay: @unchecked Sendable {
  var image: CGImage?
  /// Where the image goes in the canvas, from its top left.
  var box = CGRect.zero
  /// The canvas: the turned picture's shape, or the view's with the
  /// picture in its middle.
  var canvas = CGSize.zero
}

/// Unchecked: every stored `var` is read and written on `queue` only, and
/// the `let`s are thread-safe or used there only (the display layer's
/// enqueue and flush are made for a queue of their own).
final class VideoSink: @unchecked Sendable {
  /// The address libmpv takes as --wid. Never freed, and the sink it names
  /// is retained by it: mpv may hold the address for as long as the app
  /// runs (each player's layer is kept that long too).
  let host: UnsafeMutableRawPointer
  /// Above the picture; hidden while the frames carry the subtitles.
  let subtitles = SubtitleLayer()

  private let queue = DispatchQueue(
    label: "lumtub.video-sink", qos: .userInteractive, autoreleaseFrequency: .workItem)
  private let displayLayer: AVSampleBufferDisplayLayer
  private let timebase: CMTimebase?
  /// The screen's short side in pixels: no frame made here is taller, and
  /// the subtitles are drawn at that height.
  private let maxHeight: Int

  private var last: CVPixelBuffer?
  private var rotate = 0
  private var zoom = 1.0
  private var mirror = false
  private var compositing = false
  /// The subtitles in the canvas's coordinates (Core Image's, from the
  /// bottom left), made once per change so Core Image keeps its texture.
  private var overlay: CIImage?
  private var canvas = CGSize.zero
  /// Subtitles the app drew, in their canvas's coordinates, used while
  /// compositing in place of libmpv's (which draws none then).
  private var appOverlay: CIImage?
  private var appCanvas = CGSize.zero
  private var context: CIContext?
  private var pool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0
  private var poolFormat: OSType = 0
  private var frames = 0
  /// The subtitle layer's shape, on the main thread.
  private var viewAspect = 0.0

  init(displayLayer: AVSampleBufferDisplayLayer, timebase: CMTimebase?) {
    self.displayLayer = displayLayer
    self.timebase = timebase
    let screen = UIScreen.main.nativeBounds
    maxHeight = Int(min(screen.width, screen.height))
    host = UnsafeMutableRawPointer.allocate(byteCount: Host.size, alignment: 8)
    host.initializeMemory(as: UInt8.self, repeating: 0, count: Host.size)

    let frame: FrameCall = { context, picture, rotate, zoom in
      guard let context else { return false }
      let sink = Unmanaged<VideoSink>.fromOpaque(context).takeUnretainedValue()
      let buffer = picture.map { Unmanaged<CVPixelBuffer>.fromOpaque($0).takeUnretainedValue() }
      // mpv's thread never drains an autorelease pool of its own: without
      // this, what Core Image and Core Media leave autoreleased for each
      // frame is kept until iOS ends the app for its memory.
      return autoreleasepool { sink.frame(buffer, rotate: Int(rotate), zoom: zoom) }
    }
    let overlay: OverlayCall = { context, image, x, y, width, height, canvasWidth, canvasHeight in
      guard let context else { return }
      let sink = Unmanaged<VideoSink>.fromOpaque(context).takeUnretainedValue()
      autoreleasepool {
        sink.setOverlay(Overlay(
          image: image.map { Unmanaged<CGImage>.fromOpaque($0).takeUnretainedValue() },
          box: CGRect(x: x, y: y, width: width, height: height),
          canvas: CGSize(width: canvasWidth, height: canvasHeight)
        ))
      }
    }
    let clear: ClearCall = { context, remove in
      guard let context else { return }
      let sink = Unmanaged<VideoSink>.fromOpaque(context).takeUnretainedValue()
      autoreleasepool { sink.clear(remove: remove) }
    }

    host.storeBytes(of: Host.magic, toByteOffset: Host.magicOffset, as: UInt64.self)
    host.storeBytes(
      of: UInt(bitPattern: Unmanaged.passRetained(self).toOpaque()),
      toByteOffset: Host.contextOffset, as: UInt.self)
    host.storeBytes(of: unsafeBitCast(frame, to: UInt.self), toByteOffset: Host.frameOffset, as: UInt.self)
    host.storeBytes(of: unsafeBitCast(overlay, to: UInt.self), toByteOffset: Host.overlayOffset, as: UInt.self)
    host.storeBytes(of: unsafeBitCast(clear, to: UInt.self), toByteOffset: Host.clearOffset, as: UInt.self)
    host.storeBytes(of: Int64(maxHeight), toByteOffset: Host.maxHeightOffset, as: Int64.self)
    host.storeBytes(of: 0.0, toByteOffset: Host.canvasAspectOffset, as: Double.self)
    subtitles.resized = { [weak self] size in
      self?.viewAspect = size.width > 0 && size.height > 0 ? Double(size.width / size.height) : 0
      self?.storeCanvas()
    }
  }

  /// The subtitles are drawn on a canvas the shape of the view the picture
  /// is fitted into, so they can use the bars beside a portrait picture.
  /// While picture in picture is open the frames carry them, and the canvas
  /// is the picture's own shape. Main thread only; the output reads it at
  /// its next picture.
  private func storeCanvas() {
    host.storeBytes(of: compositingShown ? 0 : viewAspect, toByteOffset: Host.canvasAspectOffset, as: Double.self)
  }

  /// [compositing] as last set from the main thread.
  private var compositingShown = false

  // MARK: From libmpv's video output thread

  private func frame(_ picture: CVPixelBuffer?, rotate: Int, zoom: Double) -> Bool {
    queue.sync {
      if let picture { last = picture }
      self.rotate = rotate
      self.zoom = zoom.isFinite && zoom > 0 ? zoom : 1
      frames += 1
      if frames >= 60 {
        // Buffers the pool no longer needs go now and then, not every frame.
        frames = 0
        if let pool { CVPixelBufferPoolFlush(pool, .excessBuffers) }
      }
      return show()
    }
  }

  private func setOverlay(_ content: Overlay) {
    queue.sync {
      canvas = content.canvas
      overlay = content.image.map {
        CIImage(cgImage: $0).transformed(by: CGAffineTransform(
          translationX: content.box.minX, y: content.canvas.height - content.box.maxY))
      }
    }
    let subtitles = self.subtitles
    DispatchQueue.main.async { subtitles.show(content) }
  }

  private func clear(remove: Bool) {
    queue.sync {
      last = nil
      overlay = nil
      if remove {
        displayLayer.flushAndRemoveImage()
        if let pool { CVPixelBufferPoolFlush(pool, .excessBuffers) }
      } else {
        // A seek or a new file: what waits goes, the picture shown stays
        // until the next one comes.
        displayLayer.flush()
      }
    }
    let subtitles = self.subtitles
    DispatchQueue.main.async { subtitles.show(Overlay()) }
  }

  // MARK: From the main thread

  /// Mirrors the picture (mpv's hflip filter can't take VideoToolbox
  /// frames).
  func setMirror(_ on: Bool) {
    queue.async { [self] in
      guard mirror != on else { return }
      mirror = on
      show()
    }
  }

  /// Subtitles the app drew (Flutter's, where libmpv has no font for a
  /// line), for picture in picture; nil takes them away.
  func setAppOverlay(_ image: CGImage?, box: CGRect, canvas: CGSize) {
    let content = image.map {
      CIImage(cgImage: $0).transformed(by: CGAffineTransform(
        translationX: box.minX, y: canvas.height - box.maxY))
    }
    queue.async { [self] in
      appOverlay = content
      appCanvas = canvas
      // Shown at once, also while paused.
      if compositing { _ = show() }
    }
  }

  /// While picture in picture is open the frames carry the subtitles.
  func setCompositing(_ on: Bool) {
    queue.async { [self] in
      guard compositing != on else { return }
      compositing = on
      if !on, let pool { CVPixelBufferPoolFlush(pool, .excessBuffers) }
      show()
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    subtitles.isHidden = on
    CATransaction.commit()
    compositingShown = on
    storeCanvas()
  }

  /// The app came back: iOS may have interrupted the layer.
  func resume() {
    queue.async { [self] in resumeIfInterrupted() }
  }

  // MARK: On the queue

  @discardableResult
  private func show() -> Bool {
    guard let picture = last else { return false }
    return enqueue(compose(picture) ?? picture)
  }

  /// The picture turned, mirrored, zoomed and with the subtitles, made
  /// anew; nil when it is shown as it is.
  private func compose(_ picture: CVPixelBuffer) -> CVPixelBuffer? {
    let useApp = compositing && appOverlay != nil && appCanvas.width > 0 && appCanvas.height > 0
    let subsCanvas = useApp ? appCanvas : canvas
    let subs = useApp ? appOverlay : compositing && canvas.width > 0 && canvas.height > 0 ? overlay : nil
    let zoomed = abs(zoom - 1) > 1e-3
    guard subs != nil || rotate != 0 || mirror || zoomed else { return nil }

    let videoWidth = CVPixelBufferGetWidth(picture)
    let videoHeight = CVPixelBufferGetHeight(picture)
    guard videoWidth > 0, videoHeight > 0 else { return nil }

    // At most the screen's height (a 4K frame made anew for each frame is
    // 33-66 MB, and iOS ends an app in the background, as in picture in
    // picture, that holds a few), and up to it for crisp subtitles.
    // The picture in picture window is a few hundred points tall at its
    // largest: 720 lines are crisp there at less than half the memory,
    // which keeps older iPhones with 2 or 3 GB from being ended for it.
    let limit = compositing ? min(maxHeight, 720) : maxHeight
    var width = videoWidth
    var height = videoHeight
    if limit > 0, videoHeight > limit || (subs != nil && videoHeight < limit) {
      width = max(2, (videoWidth * limit / videoHeight) & ~1)
      height = limit
    }
    let sideways = rotate == 90 || rotate == 270
    let frameWidth = sideways ? height : width
    let frameHeight = sideways ? width : height
    let bounds = CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)

    // Half floats only for HDR: 8 and 10-bit SDR fit BGRA at half the
    // memory.
    let format = isHDR(picture) ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
    guard let output = makeBuffer(width: frameWidth, height: frameHeight, format: format) else {
      return nil
    }
    copyColorAttachments(from: picture, to: output)

    // Core Image reads the picture's colours from its attachments; the
    // frame made keeps them (copied above).
    let space = colorSpace(of: picture)
    var image = CIImage(cvPixelBuffer: picture)
    if width != videoWidth || height != videoHeight {
      image = image.transformed(by: CGAffineTransform(
        scaleX: CGFloat(width) / CGFloat(videoWidth),
        y: CGFloat(height) / CGFloat(videoHeight)))
    }
    // video-rotate turns clockwise.
    if rotate != 0 {
      let turn: CGImagePropertyOrientation = rotate == 90 ? .right : rotate == 180 ? .down : .left
      image = image.oriented(turn)
      image = image.transformed(by: CGAffineTransform(
        translationX: -image.extent.origin.x, y: -image.extent.origin.y))
    }
    if mirror {
      image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: CGFloat(frameWidth), ty: 0))
    }
    if zoomed {
      let x = CGFloat(frameWidth) / 2
      let y = CGFloat(frameHeight) / 2
      image = image.transformed(by: CGAffineTransform(translationX: x, y: y)
        .scaledBy(x: CGFloat(zoom), y: CGFloat(zoom))
        .translatedBy(x: -x, y: -y))
    }
    // Black where a zoomed-out picture leaves room.
    image = image.cropped(to: bounds).composited(over: CIImage(color: .black).cropped(to: bounds))
    if let subs {
      image = subs.transformed(by: CGAffineTransform(
        scaleX: CGFloat(frameWidth) / subsCanvas.width,
        y: CGFloat(frameHeight) / subsCanvas.height)).composited(over: image)
    }
    imageContext().render(image, to: output, bounds: bounds, colorSpace: space)
    return output
  }

  private func enqueue(_ buffer: CVPixelBuffer) -> Bool {
    var format: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format) == noErr,
      let format
    else { return false }
    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: timebase.map { CMTimebaseGetTime($0) } ?? .invalid,
      decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format,
      sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
      let sample
    else { return false }
    if timebase == nil,
       let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as NSArray?,
       let first = attachments.firstObject as? NSMutableDictionary {
      first.setObject(true, forKey: kCMSampleAttachmentKey_DisplayImmediately as NSString)
    }
    resumeIfInterrupted()
    displayLayer.enqueue(sample)
    return true
  }

  /// A layer iOS interrupted in the background shows nothing more until it
  /// is flushed.
  private func resumeIfInterrupted() {
    if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
      displayLayer.flush()
    }
  }

  private func isHDR(_ picture: CVPixelBuffer) -> Bool {
    guard let transfer = CVBufferCopyAttachment(picture, kCVImageBufferTransferFunctionKey, nil) as? String
    else { return false }
    return transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String
      || transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String
  }

  /// The colour space the frame made is drawn in, by the picture's
  /// transfer function and primaries (BT.709 when it has none).
  private func colorSpace(of picture: CVPixelBuffer) -> CGColorSpace? {
    let transfer = CVBufferCopyAttachment(picture, kCVImageBufferTransferFunctionKey, nil) as? String
    let primaries = CVBufferCopyAttachment(picture, kCVImageBufferColorPrimariesKey, nil) as? String
    let name: CFString
    if transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String {
      name = CGColorSpace.itur_2100_PQ
    } else if transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String {
      name = CGColorSpace.itur_2100_HLG
    } else if primaries == kCVImageBufferColorPrimaries_ITU_R_2020 as String {
      name = CGColorSpace.itur_2020
    } else if primaries == kCVImageBufferColorPrimaries_P3_D65 as String {
      name = CGColorSpace.displayP3
    } else {
      name = CGColorSpace.itur_709
    }
    return CGColorSpace(name: name)
  }

  private func copyColorAttachments(from picture: CVPixelBuffer, to output: CVPixelBuffer) {
    let keys = [
      kCVImageBufferTransferFunctionKey,
      kCVImageBufferColorPrimariesKey,
      kCVImageBufferYCbCrMatrixKey,
      kCVImageBufferMasteringDisplayColorVolumeKey,
      kCVImageBufferContentLightLevelInfoKey,
    ]
    for key in keys {
      if let value = CVBufferCopyAttachment(picture, key, nil) {
        CVBufferSetAttachment(output, key, value, .shouldPropagate)
      }
    }
  }

  private func makeBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
    if pool == nil || poolWidth != width || poolHeight != height || poolFormat != format {
      if let pool { CVPixelBufferPoolFlush(pool, .excessBuffers) }
      pool = nil
      let poolAttributes: [String: Any] = [
        kCVPixelBufferPoolMinimumBufferCountKey as String: 3,
        kCVPixelBufferPoolMaximumBufferAgeKey as String: 1.0,
      ]
      let bufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: format,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ]
      var made: CVPixelBufferPool?
      guard CVPixelBufferPoolCreate(
        kCFAllocatorDefault, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &made)
        == kCVReturnSuccess,
        let made
      else { return nil }
      pool = made
      poolWidth = width
      poolHeight = height
      poolFormat = format
    }
    guard let pool else { return nil }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess
    else { return nil }
    return buffer
  }

  /// Core Image on Metal, made the first time a frame is made anew; its
  /// working space holds HDR's values above 1.
  private func imageContext() -> CIContext {
    if let context { return context }
    var options: [CIContextOption: Any] = [
      .highQualityDownsample: false,
      .useSoftwareRenderer: false,
    ]
    if let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) {
      options[.workingColorSpace] = space
    }
    let made = MTLCreateSystemDefaultDevice().map { CIContext(mtlDevice: $0, options: options) }
      ?? CIContext(options: options)
    context = made
    return made
  }
}

/// The subtitles and OSD over the picture: a layer the size of the view,
/// with the subtitles' picture placed where the video shows (aspect fit, as
/// the display layer shows it). Used on the main thread only.
final class SubtitleLayer: CALayer, @unchecked Sendable {
  private let content = CALayer()
  private var overlay = Overlay()
  /// Called with the layer's size whenever it is laid out at another.
  var resized: ((CGSize) -> Void)?
  private var laidOut = CGSize.zero

  override init() {
    super.init()
    isOpaque = false
    content.contentsGravity = .resize
    content.isHidden = true
    addSublayer(content)
  }

  // Core Animation's copies for presentation.
  override init(layer: Any) {
    super.init(layer: layer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show(_ overlay: Overlay) {
    self.overlay = overlay
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    content.contents = overlay.image
    place()
    CATransaction.commit()
  }

  override func layoutSublayers() {
    super.layoutSublayers()
    if bounds.size != laidOut {
      laidOut = bounds.size
      resized?(bounds.size)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    place()
    CATransaction.commit()
  }

  private func place() {
    let canvas = overlay.canvas
    guard overlay.image != nil, canvas.width > 0, canvas.height > 0,
          bounds.width > 0, bounds.height > 0
    else {
      content.isHidden = true
      return
    }
    let scale = min(bounds.width / canvas.width, bounds.height / canvas.height)
    let x = bounds.midX - canvas.width * scale / 2
    let y = bounds.midY - canvas.height * scale / 2
    let box = overlay.box
    content.frame = CGRect(
      x: x + box.minX * scale, y: y + box.minY * scale,
      width: box.width * scale, height: box.height * scale)
    content.isHidden = false
  }
}
