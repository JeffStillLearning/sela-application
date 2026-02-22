package com.sela.app.service

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import com.sela.app.R

class OverlayManager(private val context: Context) {

    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var isShowing = false

    /**
     * Menampilkan overlay peringatan di atas aplikasi lain.
     * level: 1 = Peringatan pertama (soft reminder)
     *        2 = Peringatan kedua (firmer reminder)
     *        3 = Peringatan ketiga (final warning)
     */
    fun showWarning(level: Int = 1) {
        if (isShowing) return

        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // Inflate layout overlay
        val inflater = LayoutInflater.from(context)
        overlayView = inflater.inflate(R.layout.overlay_warning, null)

        // Setup teks berdasarkan level
        val textView = overlayView?.findViewById<TextView>(R.id.overlayText)
        val titleText = overlayView?.findViewById<TextView>(R.id.overlayTitle)

        when (level) {
            1 -> {
                titleText?.text = "PERINGATAN 1"
                textView?.text = "Kamu lagi ngapain sekarang?\nIngat goal kamu!"
            }
            2 -> {
                titleText?.text = "PERINGATAN 2"
                textView?.text = "Kamu sudah terlalu lama di sini!\nSaatnya berhenti dan lanjutkan goal kamu."
            }
            3 -> {
                titleText?.text = "PERINGATAN FINAL"
                textView?.text = "INI PERINGATAN TERAKHIR!\nTutup aplikasi ini sekarang juga!"
            }
        }

        // Setup tombol "Sadar"
        val btnSadar = overlayView?.findViewById<Button>(R.id.btnSadar)
        btnSadar?.setOnClickListener {
            hideOverlay()
        }

        // Setup layout params untuk TYPE_APPLICATION_OVERLAY
        val layoutParams = WindowManager.LayoutParams().apply {
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
            gravity = Gravity.CENTER

            // TYPE_APPLICATION_OVERLAY untuk Android 8.0+ (API 26+)
            type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            // Flag agar overlay tidak menghalangi interaksi sepenuhnya
            flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE

            format = PixelFormat.TRANSLUCENT
        }

        try {
            windowManager?.addView(overlayView, layoutParams)
            isShowing = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Menutup overlay yang sedang ditampilkan.
     */
    fun hideOverlay() {
        try {
            overlayView?.let {
                windowManager?.removeView(it)
            }
            isShowing = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Mengecek apakah overlay sedang ditampilkan.
     */
    fun isOverlayShowing(): Boolean = isShowing

    /**
     * Membersihkan resource saat tidak digunakan lagi.
     */
    fun cleanup() {
        if (isShowing) {
            hideOverlay()
        }
        windowManager = null
        overlayView = null
    }
}
