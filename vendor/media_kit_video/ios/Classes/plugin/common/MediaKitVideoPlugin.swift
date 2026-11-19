#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class MediaKitVideoPlugin: NSObject, FlutterPlugin {
  private static let CHANNEL_NAME = "com.alexmercerind/media_kit_video"

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if canImport(Flutter)
      let binaryMessenger = registrar.messenger()
      let registry = registrar.textures()
      let utils: UtilsProtocol? = nil
    #elseif canImport(FlutterMacOS)
      let binaryMessenger = registrar.messenger
      let registry = registrar.textures
      let utils: UtilsProtocol? = Utils(registrar)
    #endif

    let channel = FlutterMethodChannel(
      name: CHANNEL_NAME,
      binaryMessenger: binaryMessenger
    )
    let instance = MediaKitVideoPlugin(
      registry: registry,
      channel: channel,
      utils: utils
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    #if canImport(Flutter)
      // Lumtub: the view the avfoundation video output's layer shows in.
      registrar.register(
        PlayerLayerViewFactory(layers: { [weak instance] in instance?.layers[$0] }),
        withId: "com.alexmercerind/media_kit_video/layer"
      )
    #endif
  }

  #if canImport(Flutter)
    /// Lumtub: each player's display layer (vo=avfoundation), by handle.
    /// Kept while the app runs: mpv holds the layer's address.
    fileprivate var layers = [Int64: PlayerLayer]()
  #endif

  private let channel: FlutterMethodChannel
  private let videoOutputManager: VideoOutputManager
  private let utils: UtilsProtocol?

  init(
    registry: FlutterTextureRegistry,
    channel: FlutterMethodChannel,
    utils: UtilsProtocol?
  ) {
    self.channel = channel
    videoOutputManager = VideoOutputManager(
      registry: registry
    )
    self.utils = utils
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "VideoOutputManager.Create":
      handleCreateMethodCall(call.arguments, result)
    case "VideoOutputManager.SetSize":
      handleSetSizeMethodCall(call.arguments, result)
    case "VideoOutputManager.Dispose":
      handleDisposeMethodCall(call.arguments, result)
    #if canImport(Flutter)
    case let method where method.hasPrefix("Layer."):
      handleLayerMethodCall(method, call.arguments, result)
    #endif
    case "Utils.EnterNativeFullscreen":
      handleEnterNativeFullscreenMethodCall(call.arguments, result)
    case "Utils.ExitNativeFullscreen":
      handleExitNativeFullscreenMethodCall(call.arguments, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  #if canImport(Flutter)
    private func handleLayerMethodCall(
      _ method: String,
      _ arguments: Any?,
      _ result: FlutterResult
    ) {
      let args = arguments as? [String: Any] ?? [:]
      guard let handleStr = args["handle"] as? String, let handle = Int64(handleStr) else {
        return result(FlutterError(code: "handle", message: "handle must be an Int64", details: nil))
      }
      if method == "Layer.Create" {
        let layer = layers[handle] ?? PlayerLayer(events: { [weak self] event, seconds in
          var arguments: [String: Any] = ["handle": handle, "event": event]
          if let seconds { arguments["seconds"] = seconds }
          self?.channel.invokeMethod("Layer.Pip", arguments: arguments)
        })
        layers[handle] = layer
        return result(layer.address)
      }
      guard let layer = layers[handle] else { return result(nil) }
      switch method {
      case "Layer.Update":
        layer.update(
          position: (args["position"] as? NSNumber)?.doubleValue ?? 0,
          duration: (args["duration"] as? NSNumber)?.doubleValue ?? 0,
          playing: args["playing"] as? Bool ?? false,
          rate: (args["rate"] as? NSNumber)?.doubleValue ?? 1,
          live: args["live"] as? Bool ?? false
        )
        result(nil)
      case "Layer.Warmth":
        layer.setWarmth(argb: (args["argb"] as? NSNumber)?.uint32Value ?? 0xFFFF_FFFF)
        result(nil)
      case "Layer.Mirror":
        layer.setMirror((args["on"] as? Bool) ?? false)
        result(nil)
      case "Layer.StartPip":
        result(layer.startPip())
      case "Layer.StopPip":
        layer.stopPip()
        result(nil)
      case "Layer.AutoPip":
        layer.setAutoPip(args["on"] as? Bool ?? false)
        result(nil)
      case "Layer.PipSupported":
        result(layer.pipSupported)
      case "Layer.PipActive":
        result(layer.pipActive)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  #endif

  private func handleCreateMethodCall(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let handle: Int64? = Int64(handleStr)
    let configDict = args?["configuration"] as! [String: Any]
    let configuration = VideoOutputConfiguration.fromDict(configDict)

    assert(handle != nil, "handle must be an Int64")

    videoOutputManager.create(
      handle: handle!,
      configuration: configuration,
      textureUpdateCallback: { (_ textureId: Int64, _ size: CGSize) in
        self.channel.invokeMethod(
          "VideoOutput.Resize",
          arguments: [
            "handle": handle!,
            "id": textureId,
            "rect": [
              "top": 0,
              "left": 0,
              "width": size.width,
              "height": size.height,
            ],
          ] as [String: Any]
        )
      }
    )

    result(nil)
  }

  private func handleSetSizeMethodCall(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let widthStr = args?["width"] as! String
    let heightStr = args?["height"] as! String

    let handle: Int64? = Int64(handleStr)
    let width: Int64? = Int64(widthStr)
    let height: Int64? = Int64(heightStr)

    assert(handle != nil, "handle must be an Int64")

    self.videoOutputManager.setSize(
      handle: handle!,
      width: width,
      height: height
    )

    result(nil)
  }

  private func handleDisposeMethodCall(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let handle: Int64? = Int64(handleStr)

    assert(handle != nil, "handle must be an Int64")

    videoOutputManager.destroy(
      handle: handle!
    )

    result(nil)
  }

  private func handleEnterNativeFullscreenMethodCall(
    _: Any?,
    _ result: FlutterResult
  ) {
    if utils == nil {
      return result(FlutterMethodNotImplemented)
    }

    utils?.enterNativeFullscreen()
    result(nil)
  }

  private func handleExitNativeFullscreenMethodCall(
    _: Any?,
    _ result: FlutterResult
  ) {
    if utils == nil {
      return result(FlutterMethodNotImplemented)
    }

    utils?.exitNativeFullscreen()
    result(nil)
  }
}
