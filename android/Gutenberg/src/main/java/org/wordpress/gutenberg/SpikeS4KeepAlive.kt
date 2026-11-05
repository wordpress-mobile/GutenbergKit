package org.wordpress.gutenberg

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import org.json.JSONObject
import java.time.Instant

/**
 * Spike CMM-2752 (throwaway): runs a foreground service while the page reports
 * a save in flight, so the cached-app freezer can't freeze the app mid-save.
 */
class SpikeS4KeepAlive(private val context: Context, private val webView: WebView) {
    private val main = Handler(Looper.getMainLooper())
    private val open = mutableSetOf<String>()

    @JavascriptInterface
    fun begin(attemptId: String) {
        synchronized(open) { open.add(attemptId) }
        val intent = Intent(context, SpikeS4KeepAliveService::class.java)
        try {
            context.startForegroundService(intent)
            report("begin", attemptId)
        } catch (e: Exception) {
            report("begin failed: ${e.javaClass.simpleName} ${e.message}", attemptId)
        }
    }

    @JavascriptInterface
    fun end(attemptId: String) {
        val empty = synchronized(open) { open.remove(attemptId); open.isEmpty() }
        if (empty) {
            context.stopService(Intent(context, SpikeS4KeepAliveService::class.java))
        }
        report("end", attemptId)
    }

    private fun report(message: String, attemptId: String) {
        val data = JSONObject().put("attemptId", attemptId).put("at", Instant.now().toString())
        Log.i(TAG, "$message $data")
        main.post {
            webView.evaluateJavascript(
                "window.__s4?.nativeLog?.(${JSONObject.quote(message)}, $data)",
                null
            )
        }
    }

    companion object {
        const val TAG = "S4"
    }
}

class SpikeS4KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Saving", NotificationManager.IMPORTANCE_LOW)
        )
        val notification = Notification.Builder(this, CHANNEL)
            .setContentTitle("Saving post…")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        Log.i(SpikeS4KeepAlive.TAG, "service started ${Instant.now()}")
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.i(SpikeS4KeepAlive.TAG, "service timeout ${Instant.now()}")
        stopSelf()
    }

    override fun onDestroy() {
        Log.i(SpikeS4KeepAlive.TAG, "service destroyed ${Instant.now()}")
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "s4-save"
        const val ID = 2752
    }
}
