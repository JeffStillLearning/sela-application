package com.sela.app.presentation.ui

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.Window
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.sela.app.R
import com.sela.app.service.MonitoringService

class WarningActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_WARNING_LEVEL = "warning_level"
        const val WARNING_LEVEL_2 = 2
        const val WARNING_LEVEL_3 = 3
    }

    private lateinit var txtTitle: TextView
    private lateinit var txtMessage: TextView
    private lateinit var editText: EditText
    private lateinit var btnSadar: Button

    private var warningLevel = WARNING_LEVEL_2

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Buat activity tampil di atas semua (seperti overlay)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )

        setContentView(R.layout.activity_warning)

        warningLevel = intent.getIntExtra(EXTRA_WARNING_LEVEL, WARNING_LEVEL_2)

        initViews()
        setupUI()
        setupClickListeners()
    }

    private fun initViews() {
        txtTitle = findViewById(R.id.txtWarningTitle)
        txtMessage = findViewById(R.id.txtWarningMessage)
        editText = findViewById(R.id.editTextConfirmation)
        btnSadar = findViewById(R.id.btnSadar)
    }

    private fun setupUI() {
        when (warningLevel) {
            WARNING_LEVEL_2 -> {
                txtTitle.text = "PERINGATAN 2"
                txtMessage.text = "Kamu sudah terlalu lama di sini!\nSaatnya berhenti dan lanjutkan goal kamu."
                editText.visibility = android.view.View.GONE
            }
            WARNING_LEVEL_3 -> {
                txtTitle.text = "PERINGATAN FINAL"
                txtMessage.text = "INI PERINGATAN TERAKHIR!\nTutup aplikasi ini sekarang juga!"
                editText.visibility = android.view.View.VISIBLE
                editText.hint = "Ketik: Saya memilih untuk terus scroll"
            }
        }
    }

    private fun setupClickListeners() {
        btnSadar.setOnClickListener {
            stopMonitoringService()
            finish()
        }

        // Untuk peringatan 3, tambahkan TextWatcher untuk validasi
        if (warningLevel == WARNING_LEVEL_3) {
            editText.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    val confirmationText = "Saya memilih untuk terus scroll"
                    btnSadar.isEnabled = s.toString() == confirmationText
                }
            })
            // Disable tombol sampai user mengetik
            btnSadar.isEnabled = false
        }
    }

    private fun stopMonitoringService() {
        // Stop service setelah user klik SADAR
        val intent = android.content.Intent(this, MonitoringService::class.java)
        stopService(intent)
    }

    override fun onBackPressed() {
        // Disable back button, user harus klik SADAR
        // Do nothing
    }
}
