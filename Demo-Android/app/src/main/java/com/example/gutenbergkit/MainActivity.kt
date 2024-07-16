package com.example.gutenbergkit

import android.os.Bundle
import android.util.Log
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat


class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_main)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            insets
        }

        WebView.setWebContentsDebuggingEnabled(true)

        Log.i("GutenbergView", "onCreate")

        val gbView = findViewById<GutenbergView>(R.id.gutenbergView)
        gbView.editorDidBecomeAvailable = { editor ->
            editor.setContent("<!-- wp:paragraph --><p>This is the new content</p><!-- /wp:paragraph -->")
        }
        gbView.startWithDevServer()
    }
}