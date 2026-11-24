import Flutter
import OpenGLES
import UIKit

/// Lumtub: iOS ends an app that sends OpenGL ES commands while it is in
/// the background, so nothing is drawn or resized then (VideoOutput); the
/// app also stops decoding the picture there (vid=no), and a frame
/// already on its way is dropped.
final class BackgroundState {
  static let shared = BackgroundState()
  /// Posted on the main thread once drawing is allowed again.
  static let resumed = Notification.Name("LumtubVideoDrawingResumed")

  private let lock = NSLock()
  private var background = false

  private init() {
    let center = NotificationCenter.default
    center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
      self?.set(true)
    }
    // Drawing resumes once the app is active again, as Apple asks of
    // OpenGL ES apps; whatever waited for it is drawn then.
    center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
      self?.set(false)
      NotificationCenter.default.post(name: BackgroundState.resumed, object: nil)
    }
    let read = { UIApplication.shared.applicationState == .background }
    // Never waits for the main thread, which may itself be waiting for mpv.
    if Thread.isMainThread {
      set(read())
    } else {
      DispatchQueue.main.async { [weak self] in self?.set(read()) }
    }
  }

  private func set(_ value: Bool) {
    lock.lock()
    background = value
    lock.unlock()
  }

  var inBackground: Bool {
    lock.lock()
    defer { lock.unlock() }
    return background
  }
}

public class TextureHW: NSObject, FlutterTexture, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  private let handle: OpaquePointer
  private let updateCallback: UpdateCallback
  private let context: EAGLContext
  private let textureCache: CVOpenGLESTextureCache
  private var renderContext: OpaquePointer?
  private var updateTarget: Unmanaged<TextureHWUpdateTarget>?
  private var textureContexts = SwappableObjectManager<TextureGLESContext>(
    objects: [],
    skipCheckArgs: true
  )

  init?(
    handle: OpaquePointer,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.updateCallback = updateCallback
    self.context = OpenGLESHelpers.createContext()
    self.textureCache = OpenGLESHelpers.createTextureCache(context)

    super.init()
    _ = BackgroundState.shared

    // Lumtub: a libmpv built without OpenGL ES rendering falls back to
    // software rather than ending the app.
    guard self.initMPV() else {
      return nil
    }
  }

  deinit {
    disposePixelBuffer()
    disposeMPV()
    OpenGLESHelpers.deleteTextureCache(textureCache)

    // Deleting the context may cause potential RAM or VRAM memory leaks, as it
    // is used in the `deinit` method of the `TextureGLESContext`.
    // Potential fix: use a counter, and delete it only when the counter reaches
    // zero
    OpenGLESHelpers.deleteContext(context)
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let textureContext = textureContexts.current
    if textureContext == nil {
      return nil
    }

    return Unmanaged.passRetained(textureContext!.pixelBuffer)
  }

  private func initMPV() -> Bool {
    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("initMPV")
      EAGLContext.setCurrent(nil)
    }

    var procAddress = mpv_opengl_init_params(
      get_proc_address: {
        (ctx, name) in
        return TextureHW.getProcAddress(ctx, name)
      },
      get_proc_address_ctx: nil
    )

    // Lumtub: the pointers handed to mpv are used only inside the closures
    // that make them.
    let created: CInt = MPV_RENDER_API_TYPE_OPENGL.withCString { api in
      withUnsafeMutableBytes(of: &procAddress) { procAddress -> CInt in
        var params: [mpv_render_param] = [
          mpv_render_param(
            type: MPV_RENDER_PARAM_API_TYPE,
            data: UnsafeMutableRawPointer(mutating: api)
          ),
          mpv_render_param(
            type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
            data: procAddress.baseAddress
          ),
          mpv_render_param(),
        ]
        return mpv_render_context_create(&renderContext, handle, &params)
      }
    }

    if created < 0 {
      NSLog("TextureHW: OpenGL ES rendering unavailable: \(String(cString: mpv_error_string(created)))")
      renderContext = nil
      return false
    }

    let target = Unmanaged.passRetained(TextureHWUpdateTarget(self))
    updateTarget = target
    mpv_render_context_set_update_callback(
      renderContext,
      { (ctx) in
        guard let ctx = ctx else {
          return
        }
        let target = Unmanaged<TextureHWUpdateTarget>.fromOpaque(ctx)
          .takeUnretainedValue()
        DispatchQueue.main.async {
          target.texture?.updateCallback()
        }
      },
      target.toOpaque()
    )
    return true
  }

  private func disposeMPV() {
    guard renderContext != nil else {
      return
    }
    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("disposeMPV")
      EAGLContext.setCurrent(nil)
    }

    mpv_render_context_set_update_callback(renderContext, nil, nil)
    mpv_render_context_free(renderContext)
    renderContext = nil
    updateTarget?.release()
    updateTarget = nil
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 {
      return
    }

    NSLog("TextureGL: resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()

    textureContexts.reinit(
      objects: [
        TextureGLESContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
        TextureGLESContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
        TextureGLESContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
      ],
      skipCheckArgs: true
    )
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    if BackgroundState.shared.inBackground {
      return
    }
    let textureContext = textureContexts.nextAvailable()
    if textureContext == nil {
      return
    }

    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("render")
      EAGLContext.setCurrent(nil)
    }

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), textureContext!.frameBuffer)
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    var fbo = mpv_opengl_fbo(
      fbo: Int32(textureContext!.frameBuffer),
      w: Int32(size.width),
      h: Int32(size.height),
      internal_format: 0
    )
    withUnsafeMutablePointer(to: &fbo) { fboPtr -> Void in
      var params: [mpv_render_param] = [
        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
      ]
      mpv_render_context_render(renderContext, &params)
    }

    glFlush()

    textureContexts.pushAsReady(textureContext!)
  }

  static private func getProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<Int8>?
  ) -> UnsafeMutableRawPointer? {
    let symbol: CFString = CFStringCreateWithCString(
      kCFAllocatorDefault,
      name,
      kCFStringEncodingASCII
    )
    let indentifier = CFBundleGetBundleWithIdentifier(
      "com.apple.opengles" as CFString
    )
    let addr = CFBundleGetFunctionPointerForName(indentifier, symbol)

    if addr == nil {
      NSLog("Cannot get OpenGLES function pointer!")
    }
    return addr
  }
}

/// Lumtub: what mpv's update callback is given. It is released only after
/// the callback is removed, and holds the texture weakly, so a callback in
/// flight while the texture goes away finds nil instead of a freed object.
private final class TextureHWUpdateTarget {
  weak var texture: TextureHW?

  init(_ texture: TextureHW) {
    self.texture = texture
  }
}
