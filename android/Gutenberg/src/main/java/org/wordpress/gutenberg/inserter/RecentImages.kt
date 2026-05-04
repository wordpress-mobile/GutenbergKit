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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
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
    var partial by remember { mutableStateOf(isPartialPhotoAccess(context)) }
    var promptedBefore by remember { mutableStateOf(hasPromptedForPhotos(context)) }
    var uris by remember { mutableStateOf<List<Uri>>(emptyList()) }
    // `canReprompt` is its own state, recomputed at every permission-relevant
    // signal (launcher result, lifecycle resume). Compose's snapshot system
    // can't see the OS-level `shouldShowRequestPermissionRationale` flip from
    // true → false on the 2nd denial otherwise — `granted` and `promptedBefore`
    // are already in their post-deny values, so neither would notify Compose
    // and the rationale would stay stuck on "Try Again".
    var canReprompt by remember {
        mutableStateOf(activity?.let { shouldShowRationale(it) } ?: true)
    }
    // Bumped after every launcher result. Keys the MediaStore re-query so a
    // partial-access selection update (granted stays true, uris content changes)
    // refreshes the strip — `granted`/`limit` alone wouldn't trigger that.
    var refreshTick by remember { mutableStateOf(0) }
    val refreshAccessState = {
        granted = hasPhotosPermission(context)
        partial = isPartialPhotoAccess(context)
        canReprompt = activity?.let { shouldShowRationale(it) } ?: true
    }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { _ ->
        markPromptedForPhotos(context)
        promptedBefore = true
        refreshAccessState()
        refreshTick++
    }
    // Re-read permission on every RESUME so we notice grants made via system
    // Settings (which happen outside the Compose result-callback path).
    // Important: observe the host Activity's lifecycle, not the Compose-default
    // LocalLifecycleOwner. Inside a BottomSheetDialog the latter resolves to the
    // dialog's own LifecycleRegistry (per ComponentDialog), which only dispatches
    // ON_RESUME from `show()` and never refires when the user leaves to system
    // Settings and returns. The Activity's lifecycle does refire ON_RESUME.
    val activityLifecycle = (activity as? LifecycleOwner)?.lifecycle
    DisposableEffect(activityLifecycle) {
        if (activityLifecycle == null) return@DisposableEffect onDispose { }
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshAccessState()
        }
        activityLifecycle.addObserver(observer)
        onDispose { activityLifecycle.removeObserver(observer) }
    }
    LaunchedEffect(granted, limit, refreshTick) {
        uris = if (granted) {
            withContext(Dispatchers.IO) { queryRecentImages(context, limit) }
        } else {
            emptyList()
        }
    }
    if (granted) {
        return PhotoAccess.Granted(
            uris = uris,
            partialAccess = if (partial) {
                PhotoAccess.PartialAccess(
                    onManageSelection = { launcher.launch(photosPermissions()) },
                )
            } else null,
        )
    }
    val state = resolvePromptState(promptedBefore = promptedBefore, canReprompt = canReprompt)
    return PhotoAccess.NeedsPermission(
        state = state,
        request = {
            if (state == PromptState.PermanentlyDenied) openAppSettings(context)
            else launcher.launch(photosPermissions())
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

/**
 * The permission set to request together. On Android 14+ we ask for both the
 * full and partial-access permissions in one prompt — the system surfaces the
 * "Select photos and videos" affordance, and on subsequent calls reopens the
 * picker so the user can update a partial-access selection without leaving us.
 */
private fun photosPermissions(): Array<String> = when {
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
        Manifest.permission.READ_MEDIA_IMAGES,
        Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
    )
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
        Manifest.permission.READ_MEDIA_IMAGES,
    )
    else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
}

/** True when either full or partial-access reads are permitted. */
private fun hasPhotosPermission(context: Context): Boolean {
    if (ContextCompat.checkSelfPermission(context, photosPermission()) == PackageManager.PERMISSION_GRANTED) {
        return true
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        ) == PackageManager.PERMISSION_GRANTED
    }
    return false
}

/** True only when the user picked "Select photos and videos" (Android 14+). */
private fun isPartialPhotoAccess(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
    val full = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.READ_MEDIA_IMAGES,
    ) == PackageManager.PERMISSION_GRANTED
    if (full) return false
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
    ) == PackageManager.PERMISSION_GRANTED
}

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

/**
 * Clears just the rationale-rejected flag (leaving the prompted-before flag
 * alone). Called when we observe the photo permission becoming granted, so a
 * subsequent revocation surfaces the rationale again instead of stranding the
 * user in CompactTiles with no in-app affordance to re-engage.
 */
internal fun clearRejectedRationale(context: Context) {
    context.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
        .edit().remove(KEY_RATIONALE_REJECTED).apply()
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
