#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class TextureSW: NSObject, FlutterTexture, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  private let handle: OpaquePointer
  private let updateCallback: UpdateCallback
  private var renderContext: OpaquePointer?
  private var updateTarget: Unmanaged<TextureSWUpdateTarget>?
  private var textureContexts = SwappableObjectManager<TextureSWContext>(
    objects: [],
    skipCheckArgs: true
  )

  init(
    handle: OpaquePointer,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.updateCallback = updateCallback

    super.init()

    DispatchQueue.main.async {
      self.initMPV()
    }
  }

  deinit {
    disposePixelBuffer()
    disposeMPV()
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let textureContext = textureContexts.current
    if textureContext == nil {
      return nil
    }

    return Unmanaged.passRetained(textureContext!.pixelBuffer)
  }

  private func initMPV() {
    // Lumtub: the pointer handed to mpv is used only inside the closure
    // that makes it.
    let created: CInt = MPV_RENDER_API_TYPE_SW.withCString { api -> CInt in
      var params: [mpv_render_param] = [
        mpv_render_param(
          type: MPV_RENDER_PARAM_API_TYPE,
          data: UnsafeMutableRawPointer(mutating: api)
        ),
        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
      ]
      return mpv_render_context_create(&renderContext, handle, &params)
    }

    MPVHelpers.checkError(created)

    let target = Unmanaged.passRetained(TextureSWUpdateTarget(self))
    updateTarget = target
    mpv_render_context_set_update_callback(
      renderContext,
      { (ctx) in
        guard let ctx = ctx else {
          return
        }
        let target = Unmanaged<TextureSWUpdateTarget>.fromOpaque(ctx)
          .takeUnretainedValue()
        DispatchQueue.main.async {
          target.texture?.updateCallback()
        }
      },
      target.toOpaque()
    )
  }

  private func disposeMPV() {
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

    NSLog("TextureSW: resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()

    textureContexts.reinit(
      objects: [
        TextureSWContext(size: size),
        TextureSWContext(size: size),
        TextureSWContext(size: size),
      ],
      skipCheckArgs: true
    )
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    let textureContext = textureContexts.nextAvailable()
    if textureContext == nil {
      return
    }

    CVPixelBufferLockBaseAddress(
      textureContext!.pixelBuffer,
      CVPixelBufferLockFlags(rawValue: 0)
    )
    defer {
      CVPixelBufferUnlockBaseAddress(
        textureContext!.pixelBuffer,
        CVPixelBufferLockFlags(rawValue: 0)
      )
    }

    var ssize: [Int32] = [Int32(size.width), Int32(size.height)]
    let format: String = "bgr0"
    var pitch: Int = CVPixelBufferGetBytesPerRow(textureContext!.pixelBuffer)
    let buffer = CVPixelBufferGetBaseAddress(textureContext!.pixelBuffer)

    // Lumtub: the pointers handed to mpv are used only inside the closures
    // that make them.
    ssize.withUnsafeMutableBytes { ssizeBytes in
      format.withCString { formatPtr in
        withUnsafeMutablePointer(to: &pitch) { pitchPtr -> Void in
          var params: [mpv_render_param] = [
            mpv_render_param(
              type: MPV_RENDER_PARAM_SW_SIZE,
              data: ssizeBytes.baseAddress
            ),
            mpv_render_param(
              type: MPV_RENDER_PARAM_SW_FORMAT,
              data: UnsafeMutableRawPointer(mutating: formatPtr)
            ),
            mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: pitchPtr),
            mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: buffer),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
          ]
          mpv_render_context_render(renderContext, &params)
        }
      }
    }

    textureContexts.pushAsReady(textureContext!)
  }
}

/// Lumtub: what mpv's update callback is given. It is released only after
/// the callback is removed, and holds the texture weakly, so a callback in
/// flight while the texture goes away finds nil instead of a freed object.
private final class TextureSWUpdateTarget {
  weak var texture: TextureSW?

  init(_ texture: TextureSW) {
    self.texture = texture
  }
}
