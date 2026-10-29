package com.example.gutenbergkit

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.example.gutenbergkit.ui.theme.AppTheme
import org.wordpress.gutenberg.GutenbergView

class ManagePermissionsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AppTheme {
                ManagePermissionsScreen(onBack = { finish() })
            }
        }
    }
}

private enum class OsPermissionState {
    Granted,
    DeniedCanReprompt,
    DeniedSuppressed,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ManagePermissionsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    var state by remember { mutableStateOf(readPermissionState(context, activity)) }
    val refresh = { state = readPermissionState(context, activity) }

    // Re-read on RESUME so revokes/grants made via system Settings are reflected
    // when the user returns to this screen. Observes the host Activity directly
    // (it implements LifecycleOwner) — avoids the deprecated compose-ui
    // `LocalLifecycleOwner` without pulling in `lifecycle-runtime-compose`.
    val lifecycle = (activity as? LifecycleOwner)?.lifecycle
    DisposableEffect(lifecycle) {
        if (lifecycle == null) return@DisposableEffect onDispose { }
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refresh()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text("Manage Permissions") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(PaddingValues(16.dp)),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            CurrentStateCard(state)
            ResetFlagsCard(onReset = {
                GutenbergView.resetBlockPickerPhotoPreferences(context)
                refresh()
            })
            OpenSettingsCard(
                state = state,
                onOpen = { openAppSettings(context) },
            )
        }
    }
}

@Composable
private fun CurrentStateCard(state: OsPermissionState) {
    val (label, detail) = when (state) {
        OsPermissionState.Granted ->
            "Granted" to "The library can read MediaStore images; the inserter renders the thumbnail strip."
        OsPermissionState.DeniedCanReprompt ->
            "Denied (system will re-prompt)" to "The next Allow tap in the rationale will show the system prompt."
        OsPermissionState.DeniedSuppressed ->
            "Denied (system prompt suppressed)" to
                "The OS has stopped offering the system prompt for this permission. Re-enable via Settings."
    }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text("READ_MEDIA_IMAGES", style = MaterialTheme.typography.labelMedium)
            Text(label, style = MaterialTheme.typography.titleMedium)
            Text(
                detail,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ResetFlagsCard(onReset: () -> Unit) {
    ActionCard(
        title = "Reset App Rationale Flags",
        body = "Clears the in-app rationale-rejection and first-prompt flags. Does not touch the OS-level permission grant.",
        action = {
            OutlinedButton(onClick = onReset) { Text("Reset flags") }
        },
    )
}

// Settings hand-off rather than `revokeSelfPermissionOnKill` + self-kill:
//   - The API is API 33+ only and the demo's minSdk is 24, so we'd need
//     two code paths regardless.
//   - Settings gives the user an OS-owned confirmation surface — they
//     see exactly which permission flipped and when.
//   - No lifecycle race between an async self-kill and the user landing
//     back in the demo to verify the new state.
@Composable
private fun OpenSettingsCard(state: OsPermissionState, onOpen: () -> Unit) {
    val body = when (state) {
        OsPermissionState.Granted ->
            "Open the system permission settings to revoke photo access. Return to the demo to see the rationale flow restart."
        OsPermissionState.DeniedCanReprompt ->
            "Open the system permission settings if you want to inspect or change the OS-level photo permission."
        OsPermissionState.DeniedSuppressed ->
            "The system has suppressed the permission prompt for this app. " +
                "Toggle photos access from system Settings to test the granted path."
    }
    ActionCard(
        title = "Open Permission Settings",
        body = body,
        action = {
            OutlinedButton(onClick = onOpen) { Text("Open Settings") }
        },
    )
}

@Composable
private fun ActionCard(title: String, body: String, action: @Composable () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(
                body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            action()
        }
    }
}

private fun readPermissionState(context: Context, activity: Activity?): OsPermissionState {
    val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Manifest.permission.READ_MEDIA_IMAGES
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }
    val granted = ContextCompat.checkSelfPermission(context, permission) ==
        PackageManager.PERMISSION_GRANTED
    if (granted) return OsPermissionState.Granted
    val canReprompt = activity?.let {
        ActivityCompat.shouldShowRequestPermissionRationale(it, permission)
    } ?: false
    return if (canReprompt) OsPermissionState.DeniedCanReprompt else OsPermissionState.DeniedSuppressed
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is android.content.ContextWrapper -> baseContext.findActivity()
    else -> null
}

private fun openAppSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.fromParts("package", context.packageName, null)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(intent)
}
