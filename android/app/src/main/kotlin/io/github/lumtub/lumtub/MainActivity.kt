package io.github.lumtub.lumtub

import android.Manifest
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
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
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Whether leaving the app now should go to picture in picture. */
    private var autoPip = false
    private var pipAspect = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lumtub/windows_shell")
        this.channel = channel
        PlaybackService.listener = { method, argument -> runOnUiThread { channel.invokeMethod(method, argument) } }
        channel.setMethodCallHandler { call, result -> result.success(handle(call)) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PlaybackService.createChannel(this)
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
            "moveToBack" -> moveTaskToBack(true)
        }
        return null
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
