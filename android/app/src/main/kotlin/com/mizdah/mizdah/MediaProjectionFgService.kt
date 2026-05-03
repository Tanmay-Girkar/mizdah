package com.mizdah.mizdah

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service whose ONLY purpose is to satisfy Android 14+'s
 * MediaProjection foreground-service requirement. flutter_webrtc's
 * getDisplayMedia internally calls MediaProjectionManager.getMediaProjection,
 * which now throws SecurityException unless a foreground service of
 * TYPE_MEDIA_PROJECTION is already running.
 *
 * The service runs only while the user is sharing their screen.
 * Started from Dart via the screen_share_fg method channel right
 * before getDisplayMedia and stopped when sharing ends.
 */
class MediaProjectionFgService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        // On Android 15+ (SDK 35) and especially Android 16 (SDK 36)
        // the OS only allows a `mediaProjection`-typed FGS to start
        // AFTER the user has granted MediaProjection consent. Our
        // current Dart flow starts this service BEFORE calling
        // getDisplayMedia (which is what triggers consent), so on
        // those SDKs startForeground throws SecurityException and
        // the unhandled crash kills the activity.
        //
        // Defending here: catch the SecurityException, log it, and
        // stop the service quietly. The Dart side then proceeds to
        // call getDisplayMedia which may succeed via flutter_webrtc's
        // own internal foreground-service handling. Worst case the
        // user sees screen-share fail with no crash, instead of the
        // app being killed mid-meeting.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "startForeground denied (SDK strict-mode); stopping service.", e)
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "startForeground unexpected error", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen sharing",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Active when you are sharing your screen in a meeting"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Mizdah")
            .setContentText("Sharing your screen")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "mizdah_screen_share"
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "MizdahFGS"
    }
}
