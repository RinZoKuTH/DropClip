package com.dropclip.nativebridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Android Foreground Service managing passive clipboard writes and WebSocket lifecycle (FR-03B)
 *
 * Required AndroidManifest.xml entries (targetSdk 34+ crashes with
 * MissingForegroundServiceTypeException without them):
 *
 *   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
 *   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
 *   <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />  <!-- mDNS; also satisfies the connectedDevice prerequisite -->
 *   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />           <!-- Android 13+: request at runtime -->
 *   <service android:name=".DropClipForegroundService"
 *            android:foregroundServiceType="connectedDevice"
 *            android:exported="false" />
 */
class DropClipForegroundService : Service() {

    private val CHANNEL_ID = "dropclip_persistent_channel"
    private val NOTIFICATION_ID = 53317

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val notification = buildForegroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    /**
     * Writes incoming clipboard data from desktop directly to Android primary clip (Passive Inbound)
     */
    fun setPrimaryClip(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("DropClip", text)
        clipboard.setPrimaryClip(clip)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DropClip Continuity Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps DropClip connected in local network"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("DropClip Connected")
            .setContentText("Monitoring local network clipboard events")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
