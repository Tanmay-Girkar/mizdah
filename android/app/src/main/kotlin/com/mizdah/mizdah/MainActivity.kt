package com.mizdah.mizdah

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val screenShareChannel = "com.mizdah/screen_share_fg"
    private val pipChannel = "com.mizdah/pip"
    private var pipMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Notification channel referenced by
        //   <meta-data android:name="com.google.firebase.messaging
        //               .default_notification_channel_id"
        //              android:value="mizdah_general_v1" />
        // in AndroidManifest.xml. The channel MUST exist on Android 8+
        // before the first FCM message arrives — otherwise the OS
        // silently drops the notification (no error, no log). Channels
        // are idempotent: re-creating an existing channel is a no-op.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "mizdah_general_v1",
                "General notifications",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Chats, calls, meetings, and scheduling alerts."
                enableLights(true)
                enableVibration(true)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Existing screen-share foreground service control.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenShareChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, MediaProjectionFgService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, MediaProjectionFgService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Picture-in-Picture control. Dart can ask us to enter PiP
        // and we notify Dart whenever the OS toggles PiP mode (e.g.
        // user swipes home, or expands back to full).
        pipMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, pipChannel
        )
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> result.success(enterPip())
                "supported" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(
                            android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE
                        )
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Called by the OS when the user backgrounds the activity. Auto-
     * enter PiP if a meeting is active; the Dart side decides whether
     * we're allowed to (e.g. only while in a call) by gating the
     * Method.invoke call. Here we just call it unconditionally — if
     * Dart has shown a PiP-eligible screen the OS will accept;
     * otherwise it's a no-op.
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Only attempt if Dart has flagged PiP-eligible (we don't
        // here, but the Dart side can call enter manually too).
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipMethodChannel?.invokeMethod("modeChanged", isInPictureInPictureMode)
    }
}
