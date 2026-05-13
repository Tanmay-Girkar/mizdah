package com.mizdah.mizdah

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps an active P2P call alive while the
 * app is backgrounded or the screen is locked.
 *
 * On Android 14+ (SDK 34) the OS revokes runtime mic/camera access
 * from any process that isn't in the foreground or holding a
 * foreground service of an appropriate type. Without this, WhatsApp-
 * style "keep the call going indefinitely after pressing power"
 * doesn't work — the mic dies within seconds of the screen locking.
 *
 * Started by Dart via the `com.mizdah/call_fg` method channel the
 * moment a call enters `connecting` (or the user accepts an incoming
 * call), stopped when the call ends or fails. The persistent
 * notification is required by the OS for any foreground service.
 *
 * Service type combines `microphone | camera | phoneCall`:
 *   • microphone — required to keep the mic open in background
 *   • camera — required to keep the camera open in background
 *   • phoneCall — declares the user-facing intent so the system
 *                 dialer-style "ongoing call" affordances apply
 */
class OngoingCallFgService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val peerName = intent?.getStringExtra(EXTRA_PEER_NAME) ?: "On a call"
        val withVideo = intent?.getBooleanExtra(EXTRA_WITH_VIDEO, true) ?: true
        val notification = buildNotification(peerName, withVideo)
        Log.d(TAG, "onStartCommand peer=$peerName withVideo=$withVideo")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // Android 14+ requires the foregroundServiceType bitmask
                // be passed explicitly. Combine mic + camera + phoneCall
                // so the OS keeps all three resources alive even after
                // the app is backgrounded.
                val type = if (withVideo) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                }
                startForeground(NOTIFICATION_ID, notification, type)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Q-13: type required as a single int (Q+ but pre-14).
                val type = if (withVideo) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                startForeground(NOTIFICATION_ID, notification, type)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: SecurityException) {
            // Defensive — same pattern as MediaProjectionFgService. If
            // the OS strict-mode rejects the start (rare; requires the
            // app to already lack the permission), drop the service
            // quietly so the call still works in-foreground.
            Log.w(TAG, "startForeground denied; stopping service.", e)
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "startForeground unexpected error", e)
            stopSelf()
        }
        // START_STICKY so if the OS kills us for memory pressure, it
        // restarts the service automatically — the active call would
        // still have its peer connection alive in the Flutter process.
        return START_STICKY
    }

    private fun buildNotification(peerName: String, withVideo: Boolean): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ongoing call",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Persistent notification shown while a Mizdah call is active"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }

        // Tapping the notification re-launches the app so the user is
        // dropped straight back onto the call screen. We use singleTop
        // so an already-running activity is brought to front instead
        // of being recreated (which would destroy the Flutter engine).
        val launchIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) }
        val contentIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            null
        }

        val kind = if (withVideo) "Video call" else "Voice call"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("$kind in progress")
            .setContentText(peerName)
            .setSmallIcon(android.R.drawable.sym_call_outgoing)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setContentIntent(contentIntent)
            .build()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "mizdah_ongoing_call"
        private const val NOTIFICATION_ID = 2001
        private const val TAG = "MizdahCallFGS"
        const val EXTRA_PEER_NAME = "peerName"
        const val EXTRA_WITH_VIDEO = "withVideo"
    }
}
