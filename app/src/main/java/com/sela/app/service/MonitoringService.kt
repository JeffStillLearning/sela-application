package com.sela.app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import android.util.Log

class MonitoringService : LifecycleService() {

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "sela_monitoring_channel"
        private const val CHANNEL_NAME = "Sela Monitoring"
        
        // Waktu threshold sebelum menampilkan peringatan (dalam detik)
        private const val WARNING_THRESHOLD_SECONDS = 10

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
    private lateinit var overlayManager: OverlayManager
    
    // Tracking waktu dan warning level
    private var currentAppStartTime: Long = 0
    private var currentMonitoredApp: String? = null
    private var warningLevel: Int = 0
    private var lastWarningTime: Long = 0

    override fun onCreate() {
        super.onCreate()
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        overlayManager = OverlayManager(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        overlayManager.cleanup()
    }

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)

        createNotificationChannel()

        val notification = createNotification()

        val foregroundServiceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }

        startForeground(NOTIFICATION_ID, notification, foregroundServiceType)

        lifecycleScope.launch {
            while (true) {
                kotlinx.coroutines.delay(1000)

                val foregroundApp = getForegroundApp()

                if (foregroundApp != null) {
                    // Cek jika aplikasi yang dibuka adalah aplikasi yang dipantau
                    if (foregroundApp in MONITORED_APPS) {
                        // Jika ini adalah aplikasi terpantau yang sama, hitung durasi
                        if (currentMonitoredApp == foregroundApp) {
                            val durationInSeconds = (System.currentTimeMillis() - currentAppStartTime) / 1000

                            Log.d("SelaService", "Durasi di $foregroundApp: ${durationInSeconds}s")

                            // Tampilkan peringatan jika sudah melewati threshold
                            if (durationInSeconds >= WARNING_THRESHOLD_SECONDS && durationInSeconds % 10 < 2) {
                                showWarningForApp(foregroundApp)
                            }
                        } else {
                            // Aplikasi terpantau baru, reset timer
                            currentMonitoredApp = foregroundApp
                            currentAppStartTime = System.currentTimeMillis()
                            warningLevel = 0

                            Log.d("SelaService", "=== Mulai monitoring: $foregroundApp ===")
                        }
                    } else {
                        // User pindah ke aplikasi yang aman, reset semua
                        if (currentMonitoredApp != null) {
                            Log.d("SelaService", "=== User pindah ke aplikasi aman ===")
                        }
                        currentMonitoredApp = null
                        currentAppStartTime = 0
                        warningLevel = 0

                        // Sembunyikan overlay jika ada
                        if (overlayManager.isOverlayShowing()) {
                            overlayManager.hideOverlay()
                        }
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
     * Menampilkan peringatan berdasarkan level untuk aplikasi yang terdeteksi.
     */
    private fun showWarningForApp(appPackage: String) {
        val currentTime = System.currentTimeMillis()
        
        // Cegah spam warning (minimal 30 detik antara warning)
        if (currentTime - lastWarningTime < 30000) return
        
        // Increment warning level (max 3)
        if (warningLevel >= 3) {
            warningLevel = 0 // Reset setelah warning maksimal
            lastWarningTime = currentTime
            return
        }
        
        warningLevel++
        lastWarningTime = currentTime
        
        val appName = when (appPackage) {
            "com.instagram.android" -> "Instagram"
            "com.google.android.youtube" -> "YouTube"
            "com.zhiliaoapp.musically" -> "TikTok"
            "com.facebook.katana" -> "Facebook"
            "com.facebook.orca" -> "Messenger"
            else -> "Aplikasi ini"
        }
        
        Log.d("SelaService", ">>> Menampilkan PERINGATAN $warningLevel untuk $appName <<<")
        overlayManager.showWarning(warningLevel)
    }

    /**
     * Mendapatkan package name dari aplikasi yang sedang berada di foreground.
     * Memerlukan izin PACKAGE_USAGE_STATS.
     */
    private fun getForegroundApp(): String? {
        val currentTime = System.currentTimeMillis()
        val startTime = currentTime - 10000 // Lihat 10 detik ke belakang
        val endTime = currentTime

        val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
        var lastApp: String? = null
        var lastTime: Long = 0

        val event = UsageEvents.Event()
        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)

            // Hanya ambil event MOVE_TO_FOREGROUND
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                if (event.timeStamp > lastTime) {
                    lastTime = event.timeStamp
                    lastApp = event.packageName
                }
            }
        }

        return lastApp
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Sela app monitoring service"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Sela Monitoring")
            .setContentText("Sela is actively monitoring your app usage")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setOngoing(true)
            .build()
    }
}
