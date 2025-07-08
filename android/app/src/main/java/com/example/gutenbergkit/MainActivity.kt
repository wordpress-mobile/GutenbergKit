package com.example.gutenbergkit

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.wordpress.gutenberg.GutenbergView
import org.wordpress.gutenberg.EditorConfiguration

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

        val gbView = findViewById<GutenbergView>(R.id.gutenbergView)

        val config = EditorConfiguration.builder()
            .setTitle("")
            .setContent("")
            .setPostType("post")
            .setThemeStyles(false)
            .setPlugins(false)
            .setHideTitle(false)
            .setSiteURL("")
            .setSiteApiRoot("")
            .setSiteApiNamespace(arrayOf())
            .setNamespaceExcludedPaths(arrayOf())
            .setAuthHeader("")
            .setWebViewGlobals(emptyList())
            .setCookies(emptyMap())
            .build()

        gbView.start(config)
    }
}
