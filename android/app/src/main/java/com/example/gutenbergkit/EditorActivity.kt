package com.example.gutenbergkit

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.wordpress.gutenberg.EditorConfiguration
import org.wordpress.gutenberg.GutenbergView

class EditorActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_editor)

        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.editor)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        WebView.setWebContentsDebuggingEnabled(true)

        // Get the configuration from the intent
        val configuration =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra("configuration", EditorConfiguration::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<EditorConfiguration>("configuration")
            } ?: EditorConfiguration.builder().build()

        val gbView = findViewById<GutenbergView>(R.id.gutenbergView)
        gbView.start(configuration)
    }
}