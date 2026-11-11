package io.github.lumtub.lumtub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Keeps Lumtub playing while it is in the background: a foreground service
 * with the media notification, and a MediaSession for the lock screen,
 * headphone buttons, Bluetooth and Android TV's remote. The buttons go back
 * to Dart as the desktop shells send them ('button', 'seek').
 */
class PlaybackService : Service() {
    data class State(
        val title: String = "",
        val artist: String = "",
        val thumbnail: String = "",
        val status: String = "stopped",
        val next: Boolean = false,
        val previous: Boolean = false,
        val position: Long = 0,
        val duration: Long = 0,
    )

    companion object {
        private const val CHANNEL = "playback"
        private const val NOTIFICATION = 1

        var listener: ((String, Any?) -> Unit)? = null

        private var state = State()
        private var service: PlaybackService? = null
        // The service was asked for (it has not started yet), or Android refused
        // it: the timeline ticks then do not build the notification again.
        private var requested = false
        private var denied = false
        private var session: MediaSession? = null
        private var artwork: Pair<String, Bitmap?>? = null
        private val main = Handler(Looper.getMainLooper())

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(CHANNEL, context.getString(R.string.playback_channel), NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        fun update(context: Context, change: (State) -> State) {
            val before = state
            state = change(state)
            if (state == before) return
            val app = context.applicationContext
            val session = sessionFor(app)
            if (state.status == "stopped") {
                session.isActive = false
                stop(app)
                return
            }
            session.isActive = true
            session.setPlaybackState(playbackState())
            if (before.title != state.title || before.artist != state.artist || before.duration != state.duration ||
                before.thumbnail != state.thumbnail) {
                session.setMetadata(metadata())
                loadArtwork(app)
            }
            // Only a change the notification shows rebuilds it.
            if (before.status != state.status || before.title != state.title || before.artist != state.artist ||
                before.next != state.next || before.previous != state.previous || (service == null && !requested && !denied)) {
                show(app)
            }
        }

        fun stop(context: Context) {
            service?.let {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) it.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                else @Suppress("DEPRECATION") it.stopForeground(true)
                it.stopSelf()
            }
            service = null
            requested = false
            denied = false
            context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION)
        }

        private fun sessionFor(context: Context): MediaSession {
            session?.let { return it }
            val created = MediaSession(context, "Lumtub")
            created.setCallback(object : MediaSession.Callback() {
                override fun onPlay() { listener?.invoke("button", "play") }
                override fun onPause() { listener?.invoke("button", "pause") }
                override fun onStop() { listener?.invoke("button", "stop") }
                override fun onSkipToNext() { listener?.invoke("button", "next") }
                override fun onSkipToPrevious() { listener?.invoke("button", "previous") }
                override fun onSeekTo(position: Long) { listener?.invoke("seek", position.toInt()) }
                override fun onFastForward() { listener?.invoke("seek", (state.position + 10_000).toInt()) }
                override fun onRewind() { listener?.invoke("seek", (state.position - 10_000).coerceAtLeast(0).toInt()) }
            })
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            created.setSessionActivity(PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE))
            session = created
            return created
        }

        private fun playbackState(): PlaybackState {
            var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_STOP or PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_FAST_FORWARD or
                PlaybackState.ACTION_REWIND
            if (state.next) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
            if (state.previous) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
            val playing = state.status == "playing"
            return PlaybackState.Builder()
                .setActions(actions)
                .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, state.position, if (playing) 1f else 0f)
                .build()
        }

        private fun metadata(): MediaMetadata {
            val builder = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, state.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, state.artist)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, state.duration)
            artwork?.takeIf { it.first == state.thumbnail }?.second?.let {
                builder.putBitmap(MediaMetadata.METADATA_KEY_ART, it)
            }
            return builder.build()
        }

        // The thumbnail decoded at a size the notification and lock screen
        // show, not at the full size YouTube sends.
        private fun artworkBitmap(bytes: ByteArray): android.graphics.Bitmap? {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 512 && bounds.outHeight / (sample * 2) >= 288) sample *= 2
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
        }

        private fun loadArtwork(context: Context) {
            val address = state.thumbnail
            if (address.isEmpty() || artwork?.first == address) return
            artwork = address to null
            thread(isDaemon = true) {
                val bitmap = try {
                    val connection = URL(address).openConnection() as HttpURLConnection
                    connection.connectTimeout = 8000
                    connection.readTimeout = 8000
                    artworkBitmap(connection.inputStream.use { it.readBytes() })
                } catch (e: Exception) {
                    null
                }
                main.post {
                    if (artwork?.first != address || bitmap == null) return@post
                    artwork = address to bitmap
                    session?.setMetadata(metadata())
                    if (service != null) show(context)
                }
            }
        }

        private fun show(context: Context) {
            val notification = build(context)
            val running = service
            if (running == null) {
                val intent = Intent(context, PlaybackService::class.java)
                requested = true
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                    else context.startService(intent)
                } catch (e: Exception) {
                    // Not allowed from the background (Android 12): the
                    // notification alone, without keeping the app alive.
                    requested = false
                    denied = true
                    context.getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION, notification)
                }
            } else {
                context.getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION, notification)
            }
        }

        private fun action(context: Context, icon: Int, title: String, button: String, code: Int): Notification.Action {
            val intent = Intent(context, PlaybackService::class.java).setAction(button)
            val pending = PendingIntent.getService(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            return Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(context, icon), title, pending).build()
        }

        fun build(context: Context): Notification {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(context)
            val playing = state.status == "playing"
            val compact = mutableListOf<Int>()
            var index = 0
            if (state.previous) {
                builder.addAction(action(context, android.R.drawable.ic_media_previous, "Previous", "previous", 1)); compact += index++
            }
            builder.addAction(
                if (playing) action(context, android.R.drawable.ic_media_pause, "Pause", "pause", 2)
                else action(context, android.R.drawable.ic_media_play, "Play", "play", 3)
            ); compact += index++
            if (state.next) {
                builder.addAction(action(context, android.R.drawable.ic_media_next, "Next", "next", 4)); compact += index++
            }
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val style = Notification.MediaStyle().setMediaSession(session?.sessionToken).setShowActionsInCompactView(*compact.toIntArray())
            builder.setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(state.title)
                .setContentText(state.artist)
                .setContentIntent(PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE))
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(playing)
                .setShowWhen(false)
                .setStyle(style)
            artwork?.takeIf { it.first == state.thumbnail }?.second?.let { builder.setLargeIcon(it) }
            return builder.build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "play", "pause", "next", "previous" -> {
                listener?.invoke("button", intent.action)
                return START_NOT_STICKY
            }
        }
        service = this
        requested = false
        denied = false
        val notification = build(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION, notification)
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping Lumtub away ends the playback with it.
        listener?.invoke("button", "stop")
        stop(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (service === this) service = null
        super.onDestroy()
    }
}
