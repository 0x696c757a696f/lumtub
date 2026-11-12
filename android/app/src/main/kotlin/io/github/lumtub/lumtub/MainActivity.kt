package io.github.lumtub.lumtub

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.Display
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android side of the shell channel the desktop runners answer
 * (lib/windows_shell.dart, lib/app_window.dart, lib/keep_awake.dart):
 * the media notification and lock screen controls (PlaybackService),
 * keeping the screen on, and the system's picture in picture.
 */
private const val LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"
private const val WEB_SIGN_IN = 7341

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Whether leaving the app now should go to picture in picture. */
    private var autoPip = false
    private var pipAspect = Rational(16, 9)

    /** Waiting for WebSignInActivity: answered with its file, or null. */
    private var signingIn: MethodChannel.Result? = null

    /** Gives the core's certificate check (rustls-platform-verifier) this app's context. */
    private external fun initTls(context: android.content.Context)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Before Dart's first request; should it fail, the core reads
        // Android's certificate files instead.
        runCatching {
            System.loadLibrary("lumtub_core")
            initTls(applicationContext)
        }
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lumtub/windows_shell")
        this.channel = channel
        PlaybackService.listener = { method, argument -> runOnUiThread { channel.invokeMethod(method, argument) } }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "askLocalNetwork") return@setMethodCallHandler askLocalNetwork(result)
            if (call.method == "webSignIn") {
                signingIn?.success(null)
                signingIn = result
                @Suppress("DEPRECATION")
                startActivityForResult(Intent(this, WebSignInActivity::class.java), WEB_SIGN_IN)
                return@setMethodCallHandler
            }
            if (call.method == "hwDecoders") {
                // Listing the codecs loads every codec plugin; kept off the UI thread.
                Thread {
                    val answer = runCatching { hardwareDecoders() }
                    runOnUiThread { answer.fold({ result.success(it) }, { result.error("hwDecoders", it.message ?: it.toString(), null) }) }
                }.start()
                return@setMethodCallHandler
            }
            if (call.method == "installApk") {
                // Copying the APK into the installer takes a moment.
                Thread {
                    val done = runCatching { ApkInstaller.install(applicationContext, call.arguments as String) }
                    runOnUiThread { done.fold({ result.success(null) }, { result.error("install", it.message ?: it.toString(), null) }) }
                }.start()
                return@setMethodCallHandler
            }
            result.success(handle(call))
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lumtub/python").setMethodCallHandler { call, result ->
            if (call.method != "prepare") return@setMethodCallHandler result.notImplemented()
            // Unpacking the first time takes a few seconds: not on the UI thread.
            Thread {
                val answer = runCatching { PythonSetup.prepare(applicationContext) }
                runOnUiThread {
                    answer.fold({ result.success(it) }, { result.error("python", it.toString(), null) })
                }
            }.start()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PlaybackService.createChannel(this)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != WEB_SIGN_IN) return
        val path = if (resultCode == RESULT_OK) data?.getStringExtra(WebSignInActivity.PATH) else null
        signingIn?.success(path)
        signingIn = null
    }

    /**
     * Shows the sunlight or the classic icon on the home screen by turning
     * on one launcher alias and off the other; the launcher may take a
     * moment to redraw it.
     */
    private fun setAppIcon(sunlight: Boolean) {
        val want = if (sunlight) "SunlightIcon" else "ClassicIcon"
        for (name in listOf("ClassicIcon", "SunlightIcon")) {
            val component = ComponentName(this, "${MainActivity::class.java.name.substringBeforeLast('.')}.$name")
            val state = if (name == want) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            val current = packageManager.getComponentEnabledSetting(component)
            val on = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && name == "ClassicIcon")
            if (on == (name == want)) continue
            try {
                packageManager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            } catch (e: Exception) {
                // An older build without the alias: keep the icon it has.
            }
        }
    }

    /**
     * The tallest 16:9 picture a hardware decoder takes for H.264, VP9 and
     * AV1 (0 for none), as the desktop builds ask their GPU: the automatic
     * codecs follow the answer.
     */
    private fun hardwareDecoders(): Map<String, Any> {
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder && isHardware(it) }
        fun tallest(mime: String): Int {
            var best = 0
            for (info in codecs) {
                if (mime !in info.supportedTypes) continue
                val video = runCatching { info.getCapabilitiesForType(mime).videoCapabilities }.getOrNull() ?: continue
                for (height in intArrayOf(720, 1080, 1440, 2160, 4320)) {
                    val width = height * 16 / 9
                    if (height > best && (video.isSizeSupported(width, height) || video.isSizeSupported(height, width))) best = height
                }
            }
            return best
        }
        val chip = if (Build.VERSION.SDK_INT >= 31) " ${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}" else ""
        return mapOf(
            "adapter" to "${Build.MANUFACTURER} ${Build.MODEL}$chip MediaCodec",
            "h264" to tallest(MediaFormat.MIMETYPE_VIDEO_AVC),
            "vp9" to tallest(MediaFormat.MIMETYPE_VIDEO_VP9),
            "av1" to tallest(MediaFormat.MIMETYPE_VIDEO_AV1),
        )
    }

    private fun isHardware(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= 29) return info.isHardwareAccelerated
        val name = info.name.lowercase()
        return !name.startsWith("omx.google.") && !name.startsWith("c2.android.") && !name.contains(".sw.")
    }

    private fun handle(call: MethodCall): Any? {
        when (call.method) {
            "setMetadata" -> {
                val title = call.argument<String>("title") ?: ""
                val artist = call.argument<String>("artist") ?: ""
                val thumbnail = call.argument<String>("thumbnail") ?: ""
                PlaybackService.update(this) { it.copy(title = title, artist = artist, thumbnail = thumbnail) }
            }
            "setStatus" -> {
                val status = call.arguments as? String ?: "stopped"
                if (status == "playing") askForNotifications()
                PlaybackService.update(this) { it.copy(status = status) }
            }
            "setButtons" -> {
                val next = call.argument<Boolean>("next") ?: false
                val previous = call.argument<Boolean>("previous") ?: false
                PlaybackService.update(this) { it.copy(next = next, previous = previous) }
            }
            "setTimeline" -> {
                val position = (call.argument<Number>("position") ?: 0).toLong()
                val duration = (call.argument<Number>("duration") ?: 0).toLong()
                PlaybackService.update(this) { it.copy(position = position, duration = duration) }
            }
            "setKeepAwake" -> {
                if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            "setAutoPip" -> {
                autoPip = call.arguments == true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setPictureInPictureParams(pipParams())
            }
            "enterPip" -> {
                pipAspect = rationalOf((call.argument<Number>("aspect") ?: 16.0 / 9).toDouble())
                return enterPip()
            }
            "setPipAspect" -> {
                pipAspect = rationalOf((call.arguments as? Number ?: 16.0 / 9).toDouble())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) setPictureInPictureParams(pipParams())
            }
            "exitPip" -> {
                // Bringing the task forward again ends the system's window.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
                    startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                }
            }
            "isTv" -> return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                !packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
            "openUrl" -> {
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (e: Exception) {
                    // No browser installed: nothing to open it with.
                }
            }
            "shareText" -> {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, call.arguments as String)
                startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            "moveToBack" -> moveTaskToBack(true)
            "setAppIcon" -> setAppIcon(call.arguments == "sunlight")
            "setFrameRate" -> fitFrameRate((call.arguments as? Number)?.toDouble() ?: 0.0)
            "isMetered" -> return (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).isActiveNetworkMetered
        }
        return null
    }

    /** The screen's mode before Lumtub asked for another. */
    private var ownMode: Display.Mode? = null

    /**
     * Asks for a display mode of the same size whose refresh rate the
     * video's [fps] divides (24 Hz for a film), the fewest repeats first;
     * none when the screen's own mode already fits or nothing does.
     */
    private fun fitFrameRate(fps: Double) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        @Suppress("DEPRECATION")
        val display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay) ?: return
        if (window.attributes.preferredDisplayModeId == 0) ownMode = display.mode
        val own = ownMode ?: display.mode
        fun repeats(mode: Display.Mode): Int? {
            val ratio = mode.refreshRate / fps
            val whole = Math.round(ratio).toInt()
            return if (whole >= 1 && Math.abs(ratio - whole) < 0.01 * whole) whole else null
        }
        val id = when {
            fps < 1 -> 0
            repeats(own) != null -> 0
            else -> display.supportedModes
                .filter { it.physicalWidth == own.physicalWidth && it.physicalHeight == own.physicalHeight }
                .mapNotNull { mode -> repeats(mode)?.let { mode to it } }
                .minByOrNull { it.second }?.first?.modeId ?: 0
        }
        if (window.attributes.preferredDisplayModeId == id) return
        window.attributes = window.attributes.also { it.preferredDisplayModeId = id }
    }

    /** Android allows ratios from 1:2.39 to 2.39:1. */
    private fun rationalOf(aspect: Double): Rational {
        val clamped = aspect.coerceIn(1 / 2.39 + 0.01, 2.39 - 0.01)
        return Rational((clamped * 10000).toInt(), 10000)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPip).setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        return try {
            enterPictureInPictureMode(pipParams())
        } catch (e: IllegalStateException) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // From Android 12 the system enters it itself (setAutoEnterEnabled).
        if (autoPip && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pip", isInPictureInPictureMode)
    }

    private var localNetworkAnswer: MethodChannel.Result? = null

    /**
     * From Android 17 an app reaches devices on the local network (TVs to
     * cast to) only once the user allows it; answers whether it may.
     */
    private fun askLocalNetwork(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 37 || checkSelfPermission(LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED) {
            return result.success(true)
        }
        if (localNetworkAnswer != null) return result.success(false)
        localNetworkAnswer = result
        requestPermissions(arrayOf(LOCAL_NETWORK), 2)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 2) {
            localNetworkAnswer?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            localNetworkAnswer = null
        }
    }

    private var askedForNotifications = false

    /** Android 13 shows the playback notification only once allowed. */
    private fun askForNotifications() {
        if (askedForNotifications || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        askedForNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onDestroy() {
        if (isFinishing) PlaybackService.stop(this)
        PlaybackService.listener = null
        super.onDestroy()
    }
}
