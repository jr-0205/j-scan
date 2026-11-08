package com.jscan.mobile_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Servicio en primer plano que mantiene vivo el proceso mientras se envía un
 * archivo grande. El envío real ocurre en Dart; este servicio solo muestra la
 * notificación persistente y evita que Android suspenda la app.
 */
class FileTransferService : Service() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Transferencias de archivos",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Progreso de los archivos enviados a la PC"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE)
            ?: "Enviando archivos a la PC"
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, 0) ?: 0
        val hasProgress = intent?.getBooleanExtra(EXTRA_HAS_PROGRESS, false)
            ?: false
        startForeground(NOTIFICATION_ID, buildNotification(title, progress, hasProgress))
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(
        title: String,
        progress: Int,
        hasProgress: Boolean,
    ): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(title)
            .setContentText("J-SCAN · transferencia cifrada")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setProgress(100, progress.coerceIn(0, 100), !hasProgress)

        return builder.build()
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_HAS_PROGRESS = "hasProgress"
        private const val CHANNEL_ID = "jscan_transfers"
        private const val NOTIFICATION_ID = 4201
    }
}
