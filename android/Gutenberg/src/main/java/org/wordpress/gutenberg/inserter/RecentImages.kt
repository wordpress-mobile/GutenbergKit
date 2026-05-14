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
import android.util.Log
import android.util.LruCache
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Process-wide thumbnail cache keyed by content URI. Sized for ~half the
// strip (RECENT_PHOTO_LIMIT / 2) — enough that the user can scroll back
// and forth without re-fetching the leading items, and bounded so the
// memory footprint stays predictable (32 entries * ~200KB ARGB_8888 at
// 64dp/3.5x density ≈ 6MB worst case). Bitmaps are immutable, so cache
// hits are safe to share across composables.
//
// Without this cache, `LazyRow`'s offscreen disposal forced every
// scroll-back into view to re-run `RealThumbnail`'s `LaunchedEffect`,
// re-hitting `ContentResolver.loadThumbnail` via binder for a thumbnail
// the user just saw — and every dialog reopen re-decoded the same 64
// URIs from scratch.
private const val THUMBNAIL_CACHE_SIZE = 32
// Key includes `sizePx` so a density or `MEDIA_THUMB_SIZE_DP` change doesn't
// serve a bitmap decoded for a different render size.
private val thumbnailCache = LruCache<Pair<Uri, Int>, ImageBitmap>(THUMBNAIL_CACHE_SIZE)

private const val TAG = "RecentImages"

private const val PHOTO_PREFS = "gbk_inserter"
private const val KEY_PHOTOS_PROMPTED = "photos_prompted"
private const val KEY_RATIONALE_REJECTED = "rationale_rejected"

/**
 * Immutable snapshot of the inserter's photo prefs. Two booleans:
 *  - `promptedBefore`: have we shown the system permission prompt at least once.
 *  - `rejected`: has the user dismissed the rationale card.
 */
internal data class PhotoPrefs(
    val promptedBefore: Boolean = false,
    val rejected: Boolean = false,
)

// Process-wide cache populated on first async load. SharedPreferences reads
// and writes are dispatched off the main thread — composables read from the
// cache (synchronous, no IO) and writers update the cache atomically before
// queuing a disk `.apply()` on `photoPrefsScope`.
@Volatile
private var cachedPhotoPrefs: PhotoPrefs? = null
private val photoPrefsScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

internal suspend fun ensurePhotoPrefsLoaded(context: Context): PhotoPrefs {
    cachedPhotoPrefs?.let { return it }
    return withContext(Dispatchers.IO) {
        cachedPhotoPrefs ?: run {
            val sp = context.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
            PhotoPrefs(
                promptedBefore = sp.getBoolean(KEY_PHOTOS_PROMPTED, false),
                rejected = sp.getBoolean(KEY_RATIONALE_REJECTED, false),
            ).also { cachedPhotoPrefs = it }
        }
    }
}

/**
 * Returns the cached prefs synchronously if already loaded; otherwise kicks
 * off an async load and returns `null` until the load completes. In practice
 * the cache is warmed by `warmupPhotoPrefs` during `GutenbergView` construction,
 * so by the time the inserter is openable the prefs are loaded and this
 * returns synchronously. The async path is a defensive fallback that should
 * never render visibly under normal use.
 */
@Composable
internal fun rememberPhotoPrefs(context: Context): PhotoPrefs? {
    var prefs by remember { mutableStateOf(cachedPhotoPrefs) }
    LaunchedEffect(Unit) {
        if (prefs == null) prefs = ensurePhotoPrefsLoaded(context)
    }
    return prefs
}

/**
 * Fire-and-forget warmup that loads the photo prefs into the process-wide
 * cache. Called from `GutenbergView`'s constructor so that by the time the
 * user can navigate to and open the inserter, the cache is hot and the
 * inserter's prefs read is synchronous — no async-load placeholder flashes.
 */
internal fun warmupPhotoPrefs(context: Context) {
    if (cachedPhotoPrefs != null) return
    val appContext = context.applicationContext
    photoPrefsScope.launch { ensurePhotoPrefsLoaded(appContext) }
}

@Composable
internal fun rememberPhotoAccess(limit: Int, initialPromptedBefore: Boolean): PhotoAccess {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    var granted by remember { mutableStateOf(hasPhotosPermission(context)) }
    var promptedBefore by remember { mutableStateOf(initialPromptedBefore) }
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
    val refreshAccessState = {
        granted = hasPhotosPermission(context)
        canReprompt = activity?.let { shouldShowRationale(it) } ?: true
    }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ ->
        markPromptedForPhotos(context)
        promptedBefore = true
        refreshAccessState()
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
    LaunchedEffect(granted, limit) {
        uris = if (granted) {
            withContext(Dispatchers.IO) { queryRecentImages(context, limit) }
        } else {
            emptyList()
        }
    }
    if (granted) return PhotoAccess.Granted(uris)
    val state = resolvePromptState(promptedBefore = promptedBefore, canReprompt = canReprompt)
    return PhotoAccess.NeedsPermission(
        state = state,
        request = {
            if (state == PromptState.PermanentlyDenied) openAppSettings(context)
            else launcher.launch(photosPermission())
        },
    )
}

internal fun cachedThumbnail(uri: Uri, sizePx: Int): ImageBitmap? =
    thumbnailCache.get(uri to sizePx)

internal fun loadThumbnail(context: Context, uri: Uri, sizePx: Int): ImageBitmap? {
    val key = uri to sizePx
    thumbnailCache.get(key)?.let { return it }
    // MediaStore failures here are expected (deleted-mid-scroll URIs,
    // partial-grant SecurityExceptions on Android 14+, OEM-specific
    // FileNotFoundException). Log at warn so the failure isn't silent
    // for engineers watching logcat, but don't crash — the strip
    // gracefully falls back to the neutral placeholder for this tile.
    val decoded = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.loadThumbnail(uri, AndroidSize(sizePx, sizePx), null)
                .asImageBitmap()
        } else {
            null
        }
    }.onFailure { Log.w(TAG, "Failed to load thumbnail: $uri", it) }.getOrNull()
    decoded?.let { thumbnailCache.put(key, it) }
    return decoded
}

private fun photosPermission(): String =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Manifest.permission.READ_MEDIA_IMAGES
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

private fun hasPhotosPermission(context: Context): Boolean {
    if (ContextCompat.checkSelfPermission(context, photosPermission()) ==
        PackageManager.PERMISSION_GRANTED
    ) {
        return true
    }
    // Android 14+ shows a three-option dialog ("Allow all" / "Select photos" /
    // "Don't allow") whenever an app at targetSdk >= 34 requests
    // `READ_MEDIA_IMAGES` — regardless of whether the manifest opts in to
    // `READ_MEDIA_VISUAL_USER_SELECTED`. If the user picks "Select photos",
    // `READ_MEDIA_IMAGES` stays denied but `READ_MEDIA_VISUAL_USER_SELECTED`
    // is granted, and MediaStore automatically scopes our query to the
    // user-selected items. Treat that as granted so we don't tell the user
    // they have no access when they actually granted partial access.
    //
    // Declaring `READ_MEDIA_VISUAL_USER_SELECTED` in the library manifest
    // (which would unlock the "Select more photos" re-prompt affordance)
    // is the follow-up PR.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        ) == PackageManager.PERMISSION_GRANTED
    }
    return false
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

// Cache update is synchronous so subsequent composition reads see the new
// value immediately; the disk `.apply()` runs on `photoPrefsScope` so the
// caller never blocks on IO (including `SharedPreferences.edit()` itself,
// which can block waiting for the file's background load to complete).
private fun markPromptedForPhotos(context: Context) {
    cachedPhotoPrefs = (cachedPhotoPrefs ?: PhotoPrefs()).copy(promptedBefore = true)
    val appContext = context.applicationContext
    photoPrefsScope.launch {
        appContext.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_PHOTOS_PROMPTED, true).apply()
    }
}

internal fun markRationaleRejected(context: Context) {
    cachedPhotoPrefs = (cachedPhotoPrefs ?: PhotoPrefs()).copy(rejected = true)
    val appContext = context.applicationContext
    photoPrefsScope.launch {
        appContext.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_RATIONALE_REJECTED, true).apply()
    }
}

/**
 * Clears just the rationale-rejected flag (leaving the prompted-before flag
 * alone). Called when we observe the photo permission becoming granted, so a
 * subsequent revocation surfaces the rationale again instead of stranding the
 * user in CompactTiles with no in-app affordance to re-engage.
 */
internal fun clearRejectedRationale(context: Context) {
    cachedPhotoPrefs = (cachedPhotoPrefs ?: PhotoPrefs()).copy(rejected = false)
    val appContext = context.applicationContext
    photoPrefsScope.launch {
        appContext.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY_RATIONALE_REJECTED).apply()
    }
}

internal fun clearPhotoPreferences(context: Context) {
    cachedPhotoPrefs = PhotoPrefs()
    val appContext = context.applicationContext
    photoPrefsScope.launch {
        appContext.getSharedPreferences(PHOTO_PREFS, Context.MODE_PRIVATE)
            .edit().clear().apply()
    }
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
    // Query failures here strand the user with an empty strip rather
    // than a crash — surface to logcat so engineers see when a real
    // permission/cursor problem (vs. genuinely no photos) is the cause.
    runCatching {
        context.contentResolver.query(collection, projection, null, null, sortOrder)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            while (cursor.moveToNext() && result.size < limit) {
                val id = cursor.getLong(idColumn)
                result.add(ContentUris.withAppendedId(collection, id))
            }
        }
    }.onFailure { Log.w(TAG, "Failed to query recent images from MediaStore", it) }
    return result
}
