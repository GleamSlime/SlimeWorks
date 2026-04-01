package com.gleamslime.slime_works

import android.graphics.BitmapFactory
import android.os.Bundle
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var mediaSession: MediaSessionCompat? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 初始化 MediaSession，供锁屏控件使用
        mediaSession = MediaSessionCompat(this, "SlimeWorksMediaSession").also { session ->
            session.setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            session.setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                            PlaybackStateCompat.ACTION_PAUSE or
                            PlaybackStateCompat.ACTION_PLAY_PAUSE,
                    )
                    .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1f)
                    .build(),
            )
            session.isActive = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "slime_works/media_session",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setNowPlaying" -> {
                    val args = call.arguments as? Map<*, *>
                    val title = args?.get("title") as? String ?: ""
                    val artist = args?.get("artist") as? String ?: ""
                    val artworkBytes = args?.get("artwork") as? ByteArray

                    val metaBuilder =
                        MediaMetadataCompat.Builder()
                            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)

                    if (artworkBytes != null) {
                        val bmp = BitmapFactory.decodeByteArray(artworkBytes, 0, artworkBytes.size)
                        if (bmp != null) {
                            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bmp)
                        }
                    }
                    mediaSession?.setMetadata(metaBuilder.build())
                    result.success(null)
                }

                "isPipSupported" -> {
                    // Android 8.0+ (API 26+) 支持 PiP
                    result.success(android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
                }

                "enterPip" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        val params = android.app.PictureInPictureParams.Builder().build()
                        enterPictureInPictureMode(params)
                        result.success(null)
                    } else {
                        result.error("UNSUPPORTED", "该设备不支持画中画", null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        mediaSession?.release()
        super.onDestroy()
    }
}
