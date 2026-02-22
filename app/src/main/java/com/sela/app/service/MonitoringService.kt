package com.sela.app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.sela.app.presentation.ui.MainActivity
import com.sela.app.presentation.ui.WarningActivity
import kotlinx.coroutines.launch
import android.util.Log

class MonitoringService : LifecycleService() {

    companion object {
        private const val TAG = "SelaService"
        private const val NOTIFICATION_ID = 1001
        
        // Notification Channels
        const val CHANNEL_GENTLE_REMINDER = "gentle_reminder"
        const val CHANNEL_URGENT_WARNING = "urgent_warning"
        const val CHANNEL_PERSISTENT = "persistent_notification"
        
        // Warning thresholds (dalam detik)
        private const val WARNING_1_THRESHOLD = 15 * 60  // 15 menit
        private const val WARNING_2_THRESHOLD = 30 * 60  // 30 menit
        private const val WARNING_3_THRESHOLD = 45 * 60  // 45 menit

        // Daftar aplikasi yang dipantau (zombie scrolling apps)
        private val MONITORED_APPS = setOf(
            "com.instagram.android",
            "com.google.android.youtube",
            "com.zhiliaoapp.musically", // TikTok
            "com.facebook.katana",
            "com.facebook.orca" // Messenger
        )
    }

    private lateinit var usageStatsManager: UsageStatsManager
    private lateinit var notificationManager: NotificationManager

    // Tracking waktu dan warning
    private var currentAppStartTime: Long = 0
    private var currentMonitoredApp: String? = null
    private var warning1Shown = false
    private var warning2Shown = false
    private var warning3Shown = false

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "✓ Service onCreate() dipanggil")
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        createNotificationChannels()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service onDestroy() dipanggil")
    }

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "✓ Service onStartCommand() dipanggil")
        super.onStartCommand(intent, flags, startId)

        val notification = createPersistentNotification()

        val foregroundServiceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }

        Log.d(TAG, "📢 Memanggil startForeground()...")
        startForeground(NOTIFICATION_ID, notification, foregroundServiceType)
        Log.d(TAG, "✓ Service berjalan di foreground")

        lifecycleScope.launch {
            Log.d(TAG, "✓ Monitoring loop dimulai")

            while (true) {
                kotlinx.coroutines.delay(1000)

                val foregroundApp = getForegroundApp()

                if (foregroundApp != null) {
                    if (foregroundApp in MONITORED_APPS) {
                        if (currentMonitoredApp == foregroundApp) {
                            val durationInSeconds = (System.currentTimeMillis() - currentAppStartTime) / 1000

                            // Log durasi setiap 5 detik
                            if (durationInSeconds % 5 == 0L) {
                                Log.d(TAG, "⏱ Durasi di $foregroundApp: ${durationInSeconds / 60}m ${durationInSeconds % 60}s")
                            }

                            // Cek threshold peringatan
                            checkWarningThresholds(durationInSeconds, foregroundApp)
                        } else {
                            // Aplikasi baru, reset timer dan warning flags
                            Log.d(TAG, "🔄 Reset timer untuk: $foregroundApp")
                            currentMonitoredApp = foregroundApp
                            currentAppStartTime = System.currentTimeMillis()
                            warning1Shown = false
                            warning2Shown = false
                            warning3Shown = false

                            Log.d(TAG, "=== Mulai monitoring: $foregroundApp ===")
                        }
                    } else {
                        // User pindah ke aplikasi aman
                        if (currentMonitoredApp != null) {
                            Log.d(TAG, "✅ User pindah ke aplikasi aman: $foregroundApp")
                        }
                        currentMonitoredApp = null
                        currentAppStartTime = 0
                        warning1Shown = false
                        warning2Shown = false
                        warning3Shown = false
                    }
                }
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: android.content.Intent): IBinder? {
        super.onBind(intent)
        return null
    }

    /**
     * Membuat notification channels untuk berbagai tingkat peringatan.
     */
    private fun createNotificationChannels() {
        // Channel 1: Gentle Reminder (Importance High - Heads-Up)
        val gentleChannel = NotificationChannel(
            CHANNEL_GENTLE_REMINDER,
            "Gentle Reminder",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Peringatan halus untuk mengingatkan goal kamu"
            enableVibration(true)
            setShowBadge(true)
        }

        // Channel 2: Urgent Warning (Importance Max - Full Screen)
        val urgentChannel = NotificationChannel(
            CHANNEL_URGENT_WARNING,
            "Urgent Warning",
            NotificationManager.IMPORTANCE_MAX
        ).apply {
            description = "Peringatan mendesak yang akan menampilkan layar penuh"
            enableVibration(true)
            enableLights(true)
            lightColor = android.graphics.Color.RED
            setShowBadge(true)
        }

        // Channel 3: Persistent Notification (Importance Low)
        val persistentChannel = NotificationChannel(
            CHANNEL_PERSISTENT,
            "Monitoring Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Notifikasi untuk menjaga service tetap berjalan"
            setShowBadge(false)
        }

        notificationManager.createNotificationChannels(listOf(gentleChannel, urgentChannel, persistentChannel))
        Log.d(TAG, "✓ Notification channels dibuat")
    }

    /**
     * Mengecek threshold peringatan dan menampilkan notifikasi yang sesuai.
     */
    private fun checkWarningThresholds(durationInSeconds: Long, appPackage: String) {
        val appName = getAppName(appPackage)

        // Warning 1: 15 menit - Heads-Up Notification
        if (durationInSeconds >= WARNING_1_THRESHOLD && !warning1Shown) {
            Log.d(TAG, "🚨 WARNING 1: ${durationInSeconds / 60} menit di $appName")
            sendGentleReminder(appName)
            warning1Shown = true
        }

        // Warning 2: 30 menit - Full-Screen Intent
        if (durationInSeconds >= WARNING_2_THRESHOLD && !warning2Shown) {
            Log.d(TAG, "🚨 WARNING 2: ${durationInSeconds / 60} menit di $appName")
            sendUrgentWarning(appName, WarningActivity.WARNING_LEVEL_2)
            warning2Shown = true
        }

        // Warning 3: 45 menit - Full-Screen Intent dengan konfirmasi
        if (durationInSeconds >= WARNING_3_THRESHOLD && !warning3Shown) {
            Log.d(TAG, "🚨 WARNING 3 (FINAL): ${durationInSeconds / 60} menit di $appName")
            sendUrgentWarning(appName, WarningActivity.WARNING_LEVEL_3)
            warning3Shown = true
        }
    }

    /**
     * Mengirim Heads-Up Notification (Peringatan 1).
     */
    private fun sendGentleReminder(appName: String) {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_GENTLE_REMINDER)
            .setContentTitle("⏰ Ingat Goal Kamu!")
            .setContentText("Kamu sudah ${WARNING_1_THRESHOLD / 60} menit di $appName. Saatnya berhenti!")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(2001, notification)
        Log.d(TAG, "✓ Gentle reminder dikirim")
    }

    /**
     * Mengirim Full-Screen Intent (Peringatan 2 & 3).
     */
    private fun sendUrgentWarning(appName: String, level: Int) {
        val intent = Intent(this, WarningActivity::class.java).apply {
            putExtra(WarningActivity.EXTRA_WARNING_LEVEL, level)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = if (level == WarningActivity.WARNING_LEVEL_2) {
            "PERINGATAN 2"
        } else {
            "PERINGATAN FINAL"
        }

        val message = if (level == WarningActivity.WARNING_LEVEL_2) {
            "Kamu sudah ${WARNING_2_THRESHOLD / 60} menit di $appName!"
        } else {
            "Kamu sudah ${WARNING_3_THRESHOLD / 60} menit di $appName! Ini peringatan terakhir!"
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_URGENT_WARNING)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(false)
            .build()

        notificationManager.notify(3000 + level, notification)
        Log.d(TAG, "✓ Urgent warning level $level dikirim dengan Full-Screen Intent")
    }

    /**
     * Membuat notifikasi persistent untuk foreground service.
     */
    private fun createPersistentNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_PERSISTENT)
            .setContentTitle("Sela Monitoring")
            .setContentText("Sela aktif memantau penggunaan aplikasimu")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    /**
     * Mendapatkan nama aplikasi dari package name.
     */
    private fun getAppName(packageName: String): String {
        return when (packageName) {
            "com.instagram.android" -> "Instagram"
            "com.google.android.youtube" -> "YouTube"
            "com.zhiliaoapp.musically" -> "TikTok"
            "com.facebook.katana" -> "Facebook"
            "com.facebook.orca" -> "Messenger"
            else -> "Aplikasi ini"
        }
    }

    /**
     * Mendapatkan package name dari aplikasi foreground.
     */
    private fun getForegroundApp(): String? {
        val currentTime = System.currentTimeMillis()
        val startTime = currentTime - 10000
        val endTime = currentTime

        val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
        var lastApp: String? = null
        var lastTime: Long = 0

        val event = UsageEvents.Event()
        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)

            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                if (event.timeStamp > lastTime) {
                    lastTime = event.timeStamp
                    lastApp = event.packageName
                }
            }
        }

        return lastApp
    }
}
