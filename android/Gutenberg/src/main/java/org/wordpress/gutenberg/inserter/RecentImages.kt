package org.wordpress.gutenberg.inserter

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size as AndroidSize
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val PHOTO_PREFS = "gbk_inserter"
private const val KEY_PHOTOS_PROMPTED = "photos_prompted"
private const val KEY_RATIONALE_REJECTED = "rationale_rejected"

@Composable
internal fun rememberPhotoAccess(limit: Int): PhotoAccess {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    var granted by remember { mutableStateOf(hasPhotosPermission(context)) }
    var promptedBefore by remember { mutableStateOf(hasPromptedForPhotos(context)) }
    var uris by remember { mutableStateOf<List<Uri>>(emptyList()) }
    // Bumped on every permission result so the rationale state re-evaluates
    // even when `granted` and `promptedBefore` don't change — without it the
    // 2nd denial (which transitions Denied → PermanentlyDenied) would be
    // invisible to recomposition since both flags were already in their
    // post-deny state, and the "Try Again" button would silently no-op.
    var permissionTick by remember { mutableStateOf(0) }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        markPromptedForPhotos(context)
        promptedBefore = true
        granted = isGranted
        permissionTick++
    }
    // Re-read permission on every RESUME so we notice grants made via system
    // Settings (which happen outside the Compose result-callback path).
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                granted = hasPhotosPermission(context)
                permissionTick++
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(granted, limit) {
        if (granted) {
            uris = withContext(Dispatchers.IO) { queryRecentImages(context, limit) }
        }
    }
    if (granted) return PhotoAccess.Granted(uris)
    val canReprompt = run {
        permissionTick // observe the tick so we re-read shouldShowRationale on each result
        activity?.let { shouldShowRationale(it) } ?: true
    }
    val state = resolvePromptState(promptedBefore = promptedBefore, canReprompt = canReprompt)
    return PhotoAccess.NeedsPermission(
        state = state,
        request = {
            if (state == PromptState.PermanentlyDenied) openAppSettings(context)
            else launcher.launch(photosPermission())
        },
    )
}

internal fun loadThumbnail(context: Context, uri: Uri, sizePx: Int): ImageBitmap? =
    runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.loadThumbnail(uri, AndroidSize(sizePx, sizePx), null)
                .asImageBitmap()
        } else {
            null
        }
    }.getOrNull()

private fun photosPermission(): String =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Manifest.permission.READ_MEDIA_IMAGES
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

private fun hasPhotosPermission(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, photosPermission()) == PackageManager.PERMISSION_GRANTED

private fun shouldShowRationale(activity: Activity): Boolean =
    ActivityCompat.shouldShowRequestPermissionRationale(activity, photosPermission())

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

private fun openAppSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.fromParts("package", context.packageName, null)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(intent)
}

private fun hasPromptedForPhotos(context: Context): Boolean =
    context.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
        .getBoolean(KEY_PHOTOS_PROMPTED, false)

private fun markPromptedForPhotos(context: Context) {
    context.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
        .edit().putBoolean(KEY_PHOTOS_PROMPTED, true).apply()
}

internal fun hasRejectedRationale(context: Context): Boolean =
    context.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
        .getBoolean(KEY_RATIONALE_REJECTED, false)

internal fun markRationaleRejected(context: Context) {
    context.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
        .edit().putBoolean(KEY_RATIONALE_REJECTED, true).apply()
}

internal fun clearPhotoPreferences(context: Context) {
    context.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
        .edit().clear().apply()
}

private fun queryRecentImages(context: Context, limit: Int): List<Uri> {
    val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
    } else {
        @Suppress("DEPRECATION")
        MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    }
    val projection = arrayOf(MediaStore.Images.Media._ID)
    val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
    val result = mutableListOf<Uri>()
    runCatching {
        context.contentResolver.query(collection, projection, null, null, sortOrder)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            while (cursor.moveToNext() && result.size < limit) {
                val id = cursor.getLong(idColumn)
                result.add(ContentUris.withAppendedId(collection, id))
            }
        }
    }
    return result
}
