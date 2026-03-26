package com.example.gutenbergkit

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.example.gutenbergkit.ui.theme.AppTheme
import org.wordpress.gutenberg.HttpResponse
import org.wordpress.gutenberg.HttpServer
import org.wordpress.gutenberg.RequestLogEntry
import android.text.format.Formatter
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.runtime.rememberCoroutineScope
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SpeedTestResult(
    val size: Int,
    val durationMs: Long
) {
    val throughputBytesPerSec: Double get() = size.toDouble() / (durationMs.toDouble() / 1000.0)
}

class MediaProxyServerActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            AppTheme {
                MediaProxyServerScreen(onBack = { finish() })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediaProxyServerScreen(onBack: () -> Unit) {
    val server = remember { mutableStateOf<HttpServer?>(null) }
    val logs = remember { mutableStateListOf<RequestLogEntry>() }
    val localAddress = remember { mutableStateOf("") }
    val externallyAccessible = remember { mutableStateOf(true) }
    val isRunning = server.value != null
    val timeFormat = remember { SimpleDateFormat("HH:mm:ss", Locale.getDefault()) }
    val speedTestResults = remember { mutableStateListOf<SpeedTestResult>() }
    val isRunningSpeedTest = remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()

    fun startServer() {
        // Authentication is disabled for this demo app — it is never shipped to
        // end users. Production code should always set requiresAuthentication = true.
        val s = HttpServer(
            name = "media-proxy-demo",
            requestedPort = 8080,
            externallyAccessible = externallyAccessible.value,
            requiresAuthentication = false,
            handler = { request ->
                // Note: logs grows without bound. This is acceptable for a demo app;
                // a production UI should cap the list or use a ring buffer.
                withContext(Dispatchers.Main) {
                    logs.add(0, RequestLogEntry(
                        timestamp = java.util.Date(),
                        method = request.method,
                        target = request.target,
                        requestBodySize = request.body?.size?.toInt() ?: 0,
                        parseDurationMs = request.parseDurationMs
                    ))
                }
                HttpResponse(body = "OK\n".toByteArray())
            }
        )
        s.start()
        localAddress.value = if (externallyAccessible.value) {
            HttpServer.getLocalIpAddress() ?: "unknown"
        } else {
            "127.0.0.1"
        }
        server.value = s
    }

    fun stopServer() {
        server.value?.stop()
        server.value = null
    }

    LaunchedEffect(Unit) {
        startServer()
    }

    DisposableEffect(Unit) {
        onDispose { stopServer() }
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text("Media Proxy Server") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                }
            )
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            item {
                ListItem(
                    headlineContent = { Text("Address") },
                    trailingContent = {
                        AnimatedContent(
                            targetState = isRunning,
                            label = "address"
                        ) { running ->
                            if (running) {
                                Text(
                                    text = "${localAddress.value}:${server.value?.port}",
                                    fontFamily = FontFamily.Monospace
                                )
                            } else {
                                Text(
                                    text = "Loading...",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                )
            }

            item {
                ListItem(
                    headlineContent = { Text("Externally Accessible") },
                    trailingContent = {
                        Switch(
                            checked = externallyAccessible.value,
                            enabled = isRunning,
                            onCheckedChange = {
                                externallyAccessible.value = it
                                stopServer()
                                startServer()
                            }
                        )
                    }
                )
            }

            item {
                if (isRunning) {
                    Button(
                        onClick = { stopServer() },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Text("Stop Server")
                    }
                } else {
                    Button(
                        onClick = { startServer() },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Text("Start Server")
                    }
                }
            }

            item {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    Text(
                        text = "SPEED TEST",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            item {
                if (isRunning) {
                    Button(
                        onClick = {
                            coroutineScope.launch {
                                isRunningSpeedTest.value = true
                                speedTestResults.clear()
                                val sizes = listOf(128 * 1024, 512 * 1024, 1024 * 1024, 5 * 1024 * 1024, 10 * 1024 * 1024)
                                val port = server.value?.port ?: return@launch
                                for (size in sizes) {
                                    val result = withContext(Dispatchers.IO) {
                                        val payload = ByteArray(size) { 0x42 }
                                        // 127.0.0.1 is intentional — the speed test is a local
                                        // self-benchmark, not a device-to-device test. The server's
                                        // externallyAccessible toggle controls whether remote clients
                                        // can connect.
                                        val conn = URL("http://127.0.0.1:$port/speed-test").openConnection() as HttpURLConnection
                                        conn.requestMethod = "POST"
                                        conn.doOutput = true
                                        conn.setFixedLengthStreamingMode(size)
                                        val start = System.nanoTime()
                                        conn.outputStream.use { it.write(payload) }
                                        conn.inputStream.use { it.readBytes() }
                                        conn.disconnect()
                                        val elapsed = System.nanoTime() - start
                                        SpeedTestResult(size, elapsed / 1_000_000)
                                    }
                                    speedTestResults.add(result)
                                }
                                isRunningSpeedTest.value = false
                            }
                        },
                        enabled = !isRunningSpeedTest.value,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp)
                    ) {
                        Text(if (isRunningSpeedTest.value) "Running..." else "Run Speed Test")
                    }
                }
            }

            if (speedTestResults.isNotEmpty()) {
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Size", fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                        Text("Time", fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                        Text("Throughput", fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                    }
                }
            }

            items(speedTestResults) { result ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = Formatter.formatShortFileSize(androidx.compose.ui.platform.LocalContext.current, result.size.toLong()),
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        text = "${result.durationMs} ms",
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        text = "${Formatter.formatShortFileSize(androidx.compose.ui.platform.LocalContext.current, result.throughputBytesPerSec.toLong())}/s",
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            item {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    Text(
                        text = "REQUEST LOG",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            if (logs.isEmpty()) {
                item {
                    Text(
                        text = "No requests yet",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
            } else {
                items(logs) { entry ->
                    ListItem(
                        headlineContent = {
                            Text(
                                text = "${entry.method} ${entry.target}",
                                fontFamily = FontFamily.Monospace,
                                style = MaterialTheme.typography.bodySmall
                            )
                        },
                        supportingContent = {
                            Text(
                                text = "${timeFormat.format(entry.timestamp)} · ${Formatter.formatShortFileSize(androidx.compose.ui.platform.LocalContext.current, entry.requestBodySize.toLong())} · ${"%.2f".format(entry.parseDurationMs)}ms",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    )
                }
            }
        }
    }
}
