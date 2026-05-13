package org.wordpress.gutenberg.inserter

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SecondaryScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.rememberNestedScrollInteropConnection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import java.io.File
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.wordpress.gutenberg.R
import androidx.compose.ui.graphics.Color as ComposeColor
import org.wordpress.gutenberg.model.BlockInserterPayload
import org.wordpress.gutenberg.model.BlockType

private const val SEARCH_ONLY_CATEGORY = "gbk-search-only"
private const val MOST_USED_CATEGORY = "gbk-most-used"
private const val SEARCH_DEBOUNCE_MS = 150L

/** WordPress brand navy — seed for the fallback scheme on pre-API-31 devices. */
private const val BRAND_SEED_ARGB = 0xFF001E57.toInt()

/** Medium sheet height (dp) per the design spec; drives BottomSheetBehavior's peek. */
private const val SHEET_PEEK_HEIGHT_DP = 620

private const val SHEET_CORNER_DP = 28
private const val HANDLE_WIDTH_DP = 32
private const val HANDLE_HEIGHT_DP = 4
private const val HANDLE_TOP_PAD_DP = 10
private const val HANDLE_BOTTOM_PAD_DP = 4
private const val HANDLE_ALPHA = 0.4f

private const val HEADER_HEIGHT_DP = 48
private const val HEADER_START_PAD_DP = 24
private const val HEADER_END_PAD_DP = 8
private const val HEADER_VERTICAL_PAD_DP = 6
private const val HEADER_BUTTON_GAP_DP = 6
private const val HEADER_TITLE_SP = 22
private const val HEADER_TITLE_LETTER_SPACING_SP = -0.1

private const val ICON_BUTTON_SIZE_DP = 40
private const val ICON_SIZE_DP = 20

private const val MEDIA_STRIP_TOP_PAD_DP = 4
private const val MEDIA_STRIP_BOTTOM_PAD_DP = 10
private const val MEDIA_STRIP_CONTENT_HORIZONTAL_PAD_DP = 20
private const val MEDIA_STRIP_CONTENT_TOP_PAD_DP = 2
private const val MEDIA_STRIP_CONTENT_BOTTOM_PAD_DP = 6
private const val MEDIA_STRIP_ITEM_GAP_DP = 8
private const val MEDIA_STACK_WIDTH_DP = 72
private const val MEDIA_STACK_HEIGHT_DP = 136
private const val MEDIA_STACK_COMPACT_HEIGHT_DP = 88
private const val MEDIA_STACK_GAP_DP = 4
private const val MEDIA_STACK_CORNER_DP = 18
private const val MEDIA_STACK_ICON_SIZE_DP = 28
private const val MEDIA_STACK_LABEL_SP = 13
private const val MEDIA_THUMB_SIZE_DP = 64
private const val MEDIA_THUMB_CORNER_DP = 16
private const val RECENT_PHOTO_LIMIT = 64

private const val MEDIA_RATIONALE_PAD_DP = 14
private const val MEDIA_RATIONALE_FONT_SP = 13
private const val MEDIA_RATIONALE_LINE_HEIGHT_SP = 18
private const val MEDIA_RATIONALE_BUTTON_GAP_DP = 6
private const val MEDIA_RATIONALE_BUTTON_HEIGHT_DP = 32
private const val MEDIA_RATIONALE_BUTTON_CORNER_DP = 16
private const val MEDIA_RATIONALE_BUTTON_FONT_SP = 12

// Matches M3's internal `Tab.HorizontalTextPadding` — the horizontal padding
// applied by `Tab` between its layout bounds and the text label inside.
// Hardcoded because the upstream constant is `internal`.
private const val TAB_INTERNAL_TEXT_PAD_DP = 16

private const val SEARCH_TOP_PAD_DP = 12
private const val SEARCH_HORIZONTAL_PAD_DP = 20
private const val SEARCH_BOTTOM_PAD_DP = 10
private const val SEARCH_HEIGHT_DP = 40
private const val SEARCH_CORNER_DP = 20
private const val SEARCH_INNER_HORIZONTAL_PAD_DP = 14
private const val SEARCH_ICON_GAP_DP = 10
private const val SEARCH_ICON_SIZE_DP = 22
private const val SEARCH_FONT_SP = 14

private const val GRID_HORIZONTAL_PAD_DP = 14
private const val GRID_BOTTOM_PAD_DP = 8
private const val GRID_GAP_DP = 8
private const val BLOCK_TILE_BUTTON_CORNER_DP = 18
private const val BLOCK_TILE_ICON_SIZE_DP = 56
private const val BLOCK_TILE_ICON_CORNER_DP = 18
private const val BLOCK_TILE_ICON_GLYPH_SIZE_DP = 32
private const val BLOCK_TILE_VERTICAL_PAD_TOP_DP = 10
private const val BLOCK_TILE_VERTICAL_PAD_BOTTOM_DP = 12
private const val BLOCK_TILE_HORIZONTAL_PAD_DP = 4
private const val BLOCK_TILE_ICON_LABEL_GAP_DP = 8
private const val BLOCK_TILE_LABEL_SP = 12
private const val BLOCK_TILE_LABEL_MIN_SP = 9
private const val BLOCK_TILE_LABEL_LETTER_SPACING_SP = 0.1
private const val BLOCK_TILE_LABEL_LINE_HEIGHT_RATIO = 1.2f

private const val EMPTY_STATE_HORIZONTAL_PAD_DP = 12
private const val EMPTY_STATE_VERTICAL_PAD_DP = 32
private const val EMPTY_STATE_FONT_SP = 14

private const val DISABLED_ALPHA = 0.5f

/**
 * Material 3 minimum touch-target. The rationale buttons sit below this for
 * design reasons; we wrap them in an outer clickable that meets the minimum
 * without changing the visual size.
 */
private const val TOUCH_TARGET_MIN_DP = 48

/**
 * Bottom-sheet block inserter. The outer shell stays a `BottomSheetDialog` so
 * `GutenbergView`'s integration surface is unchanged; everything visible is
 * Compose content matching the Variation B design handoff — header row, recent
 * media strip, scrollable secondary tabs, rounded search, 5-column tonal tile grid.
 *
 * The sheet background and 28dp top corners are drawn by Compose directly; the
 * dialog's default white pill background is cleared so it doesn't fight the
 * Material 3 surface tokens.
 */
internal class BlockPickerDialog(
    context: Context,
    private val payload: BlockInserterPayload,
    private val onBlockSelected: (BlockType) -> Unit,
) : BottomSheetDialog(context) {

    init {
        // Render at full size regardless of the IME — without this the dialog
        // opens compressed above an in-flight soft keyboard, then visibly
        // resizes once the IME dismisses, looking like a "double launch".
        window?.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        )
        val composeView = ComposeView(context).apply {
            setContent {
                BlockPickerSheet(
                    payload = payload,
                    onBlockSelected = { block ->
                        onBlockSelected(block)
                        dismiss()
                    },
                    onClose = { dismiss() },
                )
            }
        }
        setContentView(composeView)
    }

    override fun onStart() {
        super.onStart()
        val parent = findViewById<ViewGroup>(com.google.android.material.R.id.design_bottom_sheet)
        parent?.setBackgroundColor(Color.TRANSPARENT)
        parent?.let { sheet ->
            BottomSheetBehavior.from(sheet).apply {
                val density = context.resources.displayMetrics.density
                peekHeight = (SHEET_PEEK_HEIGHT_DP * density).toInt()
                skipCollapsed = false
                state = BottomSheetBehavior.STATE_COLLAPSED
            }
        }
    }
}

@Composable
private fun BlockPickerSheet(
    payload: BlockInserterPayload,
    onBlockSelected: (BlockType) -> Unit,
    onClose: () -> Unit,
) {
    val colorScheme = rememberColorScheme()
    MaterialTheme(colorScheme = colorScheme) {
        val allBlocks = remember(payload) { flattenBlocks(payload) }
        val recentBlocks = remember(payload, allBlocks) { recentBlocks(payload, allBlocks) }

        var selectedTab by remember { mutableStateOf(BlockPickerTab.Recent) }
        var query by remember { mutableStateOf("") }
        var debounced by remember { mutableStateOf("") }
        LaunchedEffect(query) {
            delay(SEARCH_DEBOUNCE_MS)
            debounced = query.trim()
        }

        val filtered = remember(selectedTab, debounced, allBlocks, recentBlocks) {
            val tabBlocks = filterByTab(selectedTab, allBlocks, recentBlocks)
            if (debounced.isEmpty()) tabBlocks else searchBlocks(debounced, tabBlocks)
        }

        SheetContent(
            selectedTab = selectedTab,
            onSelectTab = { selectedTab = it },
            query = query,
            onQueryChange = { query = it },
            debouncedQuery = debounced,
            blocks = filtered,
            onBlockSelected = onBlockSelected,
            onClose = onClose,
            surface = colorScheme.surfaceContainerLow,
        )
    }
}

@Composable
@Suppress("LongParameterList")
private fun SheetContent(
    selectedTab: BlockPickerTab,
    onSelectTab: (BlockPickerTab) -> Unit,
    query: String,
    onQueryChange: (String) -> Unit,
    debouncedQuery: String,
    blocks: List<BlockType>,
    onBlockSelected: (BlockType) -> Unit,
    onClose: () -> Unit,
    surface: ComposeColor,
) {
    // Bridge Compose scroll deltas (grid, tabs) into the View-hierarchy
    // nested-scroll system so `BottomSheetBehavior` only drags the sheet when
    // an inner scroller is at its own edge. Without this the sheet and inner
    // scrollers compete for each touch.
    val nestedScroll = rememberNestedScrollInteropConnection()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .nestedScroll(nestedScroll)
            .clip(RoundedCornerShape(topStart = SHEET_CORNER_DP.dp, topEnd = SHEET_CORNER_DP.dp))
            .background(surface)
    ) {
        DragHandle()
        Header(onClose = onClose)
        MediaStrip()
        CategoryTabs(selected = selectedTab, onSelect = onSelectTab)
        SearchField(query = query, onQueryChange = onQueryChange)
        BlockGridContent(
            blocks = blocks,
            query = debouncedQuery,
            onBlockClicked = onBlockSelected,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f, fill = true),
        )
    }
}

private fun flattenBlocks(payload: BlockInserterPayload): List<BlockType> =
    dedupeById(
        payload.sections
            .filter { it.category != SEARCH_ONLY_CATEGORY }
            .flatMap { it.blocks }
    )

private fun recentBlocks(
    payload: BlockInserterPayload,
    allBlocks: List<BlockType>,
): List<BlockType> {
    val mostUsed = payload.sections
        .firstOrNull { it.category == MOST_USED_CATEGORY }
        ?.blocks
        .orEmpty()
    return if (mostUsed.isNotEmpty()) dedupeById(mostUsed) else allBlocks
}

@Composable
private fun rememberColorScheme(): ColorScheme {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    return remember(dark) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        } else {
            brandFallback(dark, if (dark) darkColorScheme() else lightColorScheme())
        }
    }
}

private fun brandFallback(dark: Boolean, base: ColorScheme): ColorScheme {
    fun ComposeColor.lighten(f: Float): ComposeColor = copy(
        red = red + (1f - red) * f,
        green = green + (1f - green) * f,
        blue = blue + (1f - blue) * f,
    )
    fun ComposeColor.darken(f: Float): ComposeColor = copy(
        red = red * (1f - f),
        green = green * (1f - f),
        blue = blue * (1f - f),
    )
    val seed = ComposeColor(BRAND_SEED_ARGB)
    return if (dark) {
        base.copy(
            primary = seed.lighten(0.4f),
            onPrimary = ComposeColor.White,
            primaryContainer = seed.darken(0.2f),
            onPrimaryContainer = seed.lighten(0.6f),
        )
    } else {
        base.copy(
            primary = seed,
            onPrimary = ComposeColor.White,
            primaryContainer = seed.lighten(0.75f),
            onPrimaryContainer = seed,
        )
    }
}

@Composable
private fun DragHandle() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = HANDLE_TOP_PAD_DP.dp, bottom = HANDLE_BOTTOM_PAD_DP.dp),
        contentAlignment = Alignment.TopCenter,
    ) {
        Box(
            modifier = Modifier
                .width(HANDLE_WIDTH_DP.dp)
                .height(HANDLE_HEIGHT_DP.dp)
                .clip(RoundedCornerShape(HANDLE_HEIGHT_DP.dp / 2))
                .background(
                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = HANDLE_ALPHA)
                ),
        )
    }
}

@Composable
private fun Header(onClose: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(HEADER_BUTTON_GAP_DP.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = HEADER_HEIGHT_DP.dp)
            .padding(
                start = HEADER_START_PAD_DP.dp,
                end = HEADER_END_PAD_DP.dp,
                top = HEADER_VERTICAL_PAD_DP.dp,
                bottom = HEADER_VERTICAL_PAD_DP.dp,
            ),
    ) {
        Text(
            text = stringResource(R.string.gbk_block_inserter_title),
            color = MaterialTheme.colorScheme.onSurface,
            fontSize = HEADER_TITLE_SP.sp,
            fontWeight = FontWeight.Medium,
            letterSpacing = HEADER_TITLE_LETTER_SPACING_SP.sp,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() },
        )
        CloseButton(onClose = onClose)
    }
}

@Composable
private fun CloseButton(onClose: () -> Unit) {
    IconButton(onClick = onClose, modifier = Modifier.size(ICON_BUTTON_SIZE_DP.dp)) {
        Icon(
            imageVector = Icons.Filled.Close,
            contentDescription = stringResource(R.string.gbk_block_inserter_close),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(ICON_SIZE_DP.dp),
        )
    }
}

@Composable
@Suppress("LongMethod")
private fun MediaStrip() {
    val contentPadding = PaddingValues(
        start = MEDIA_STRIP_CONTENT_HORIZONTAL_PAD_DP.dp,
        end = MEDIA_STRIP_CONTENT_HORIZONTAL_PAD_DP.dp,
        top = MEDIA_STRIP_CONTENT_TOP_PAD_DP.dp,
        bottom = MEDIA_STRIP_CONTENT_BOTTOM_PAD_DP.dp,
    )
    val stripFraming = Modifier
        .fillMaxWidth()
        .padding(top = MEDIA_STRIP_TOP_PAD_DP.dp, bottom = MEDIA_STRIP_BOTTOM_PAD_DP.dp)
    // Pre-Q (Android 7-9, API 24-28): `ContentResolver.loadThumbnail` is
    // API 29+ and we don't ship a `BitmapFactory.decodeStream` fallback —
    // full-resolution decodes on the slowest hardware in our minSdk range
    // would be worse UX than not showing the strip. Skip the permission
    // prompt entirely and render only the permissionless Photos/Camera
    // tiles. The user gets a working media-insert path (system picker +
    // camera) and we don't burn their trust asking for a permission we
    // can't deliver on.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        Box(modifier = stripFraming) {
            PhotosCameraTile(
                horizontal = true,
                modifier = Modifier.fillMaxWidth().padding(contentPadding),
            )
        }
        return
    }
    val access = rememberPhotoAccess(limit = RECENT_PHOTO_LIMIT)
    val context = LocalContext.current
    var rejected by remember { mutableStateOf(hasRejectedRationale(context)) }
    // Clear a prior rejection once the user actually grants the permission.
    // Without this, a later revocation would leave the user in CompactTiles
    // with no in-app path back to the rationale.
    LaunchedEffect(access) {
        if (access is PhotoAccess.Granted && rejected) {
            clearRejectedRationale(context)
            rejected = false
        }
    }
    Box(modifier = stripFraming) {
        when (resolveMediaStripView(access, rejected)) {
            MediaStripView.Rationale -> {
                val needs = access as PhotoAccess.NeedsPermission
                // Rationale fills the remaining width next to the Photos/Camera
                // column — no horizontal scroll needed since nothing extends past
                // the viewport.
                Row(
                    horizontalArrangement = Arrangement.spacedBy(MEDIA_STRIP_ITEM_GAP_DP.dp),
                    modifier = Modifier.fillMaxWidth().padding(contentPadding),
                ) {
                    PhotosCameraTile(horizontal = false)
                    PhotoAccessRationale(
                        state = needs.state,
                        onAllow = needs.request,
                        onReject = {
                            markRationaleRejected(context)
                            rejected = true
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            MediaStripView.CompactTiles -> {
                // Rationale dismissed — keep the Photos/Camera buttons accessible
                // but flatten them into a single full-width row. Picker and camera
                // don't need the photo permission; only the recent-photo strip does.
                PhotosCameraTile(
                    horizontal = true,
                    modifier = Modifier.fillMaxWidth().padding(contentPadding),
                )
            }
            MediaStripView.FullStrip -> FullMediaStrip(
                granted = access as? PhotoAccess.Granted,
                contentPadding = contentPadding,
            )
        }
    }
}

@Composable
private fun FullMediaStrip(granted: PhotoAccess.Granted?, contentPadding: PaddingValues) {
    // Granted — thumbnail strip extends past the viewport. LazyRow composes
    // only the visible columns (plus prefetch), so the 64 thumbnails aren't
    // all decoded into memory upfront. Vertical drags pass through the lazy
    // list's nested-scroll dispatch up to BottomSheetBehavior; no manual
    // relay needed.
    val uris = granted?.uris.orEmpty()
    val columns = (uris.size + 1) / 2
    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(MEDIA_STRIP_ITEM_GAP_DP.dp),
        contentPadding = contentPadding,
        modifier = Modifier.fillMaxWidth(),
    ) {
        item(key = "actions") { PhotosCameraTile(horizontal = false) }
        items(columns, key = { uris[it * 2].toString() }) { col ->
            Column(verticalArrangement = Arrangement.spacedBy(MEDIA_STRIP_ITEM_GAP_DP.dp)) {
                RealThumbnail(uri = uris[col * 2])
                val secondIndex = col * 2 + 1
                if (secondIndex < uris.size) {
                    RealThumbnail(uri = uris[secondIndex])
                }
            }
        }
    }
}

// Photos uses the permissionless system photo picker; Camera uses
// ACTION_IMAGE_CAPTURE against a cache-scoped FileProvider URI — no CAMERA
// permission required since we delegate to the system camera app. The
// recent-photos strip (READ_MEDIA_IMAGES-gated) sits alongside this row when
// granted; otherwise this tile pair is the only media affordance.
@Composable
@Suppress("LongMethod")
private fun PhotosCameraTile(
    horizontal: Boolean,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    // Hide the Camera tile on devices without any camera hardware (tablets,
    // emulators, e-readers). FEATURE_CAMERA_ANY doesn't require a `<queries>`
    // manifest entry, unlike resolving ACTION_IMAGE_CAPTURE directly.
    val hasCamera = remember(context) {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    }
    // The result callbacks below are intentionally inert: the picked URI / camera
    // capture needs to round-trip through `WebViewAssetLoader` so the JS editor
    // can `fetch()` it, which is a follow-up. Until that lands, this whole sheet
    // is gated behind the demo app's "Enable Native Inserter" toggle, so users
    // outside that opt-in won't see the no-op buttons.
    val photoPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { /* picked uri — hand-off to editor insertion is a follow-up */ }
    // Saveable so the URI survives process death while the camera app is in
    // the foreground; `Uri` is `Parcelable`, which the default saver handles.
    // Written on each Camera tap so the follow-up `TakePicture` callback can
    // read back the capture target — unused by the inert callback today.
    var pendingCameraUri by rememberSaveable { mutableStateOf<Uri?>(null) }
    val cameraLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { /* success:Boolean + pendingCameraUri — hand-off is a follow-up */ }
    val imageOnly = remember { PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly) }
    val onPhotosClick = { photoPicker.launch(imageOnly) }
    val cameraUnavailableMessage = stringResource(R.string.gbk_block_inserter_camera_unavailable)
    val onCameraClick = {
        val uri = createCameraOutputUri(context)
        pendingCameraUri = uri
        try {
            cameraLauncher.launch(uri)
        } catch (e: ActivityNotFoundException) {
            // Defense-in-depth: hasCamera gates the tile, but corp-locked
            // devices can have camera hardware without any handler for
            // ACTION_IMAGE_CAPTURE installed.
            pendingCameraUri = null
            Log.w("BlockPickerDialog", "No activity to handle ACTION_IMAGE_CAPTURE", e)
            Toast.makeText(context, cameraUnavailableMessage, Toast.LENGTH_SHORT).show()
        }
    }
    val photosLabel = stringResource(R.string.gbk_block_inserter_photos)
    val cameraLabel = stringResource(R.string.gbk_block_inserter_camera)
    if (horizontal) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(MEDIA_STACK_GAP_DP.dp),
            modifier = modifier.height(MEDIA_STACK_COMPACT_HEIGHT_DP.dp),
        ) {
            MediaActionTile(
                icon = Icons.Filled.PhotoLibrary,
                label = photosLabel,
                background = MaterialTheme.colorScheme.primaryContainer,
                foreground = MaterialTheme.colorScheme.onPrimaryContainer,
                onClick = onPhotosClick,
                modifier = Modifier.fillMaxHeight().weight(1f),
            )
            if (hasCamera) {
                MediaActionTile(
                    icon = Icons.Filled.PhotoCamera,
                    label = cameraLabel,
                    background = MaterialTheme.colorScheme.tertiary,
                    foreground = MaterialTheme.colorScheme.onTertiary,
                    onClick = onCameraClick,
                    modifier = Modifier.fillMaxHeight().weight(1f),
                )
            }
        }
    } else {
        Column(
            verticalArrangement = Arrangement.spacedBy(MEDIA_STACK_GAP_DP.dp),
            modifier = modifier
                .width(MEDIA_STACK_WIDTH_DP.dp)
                .height(MEDIA_STACK_HEIGHT_DP.dp),
        ) {
            MediaActionTile(
                icon = Icons.Filled.PhotoLibrary,
                label = photosLabel,
                background = MaterialTheme.colorScheme.primaryContainer,
                foreground = MaterialTheme.colorScheme.onPrimaryContainer,
                onClick = onPhotosClick,
                modifier = Modifier.fillMaxWidth().weight(1f),
            )
            if (hasCamera) {
                MediaActionTile(
                    icon = Icons.Filled.PhotoCamera,
                    label = cameraLabel,
                    background = MaterialTheme.colorScheme.tertiary,
                    foreground = MaterialTheme.colorScheme.onTertiary,
                    onClick = onCameraClick,
                    modifier = Modifier.fillMaxWidth().weight(1f),
                )
            }
        }
    }
}

private fun createCameraOutputUri(context: Context): Uri {
    val dir = File(context.cacheDir, "camera").apply { mkdirs() }
    val file = File(dir, "capture_${System.currentTimeMillis()}.jpg")
    // TODO: clean up captured files once the editor hand-off lands. Each Camera
    // tap creates a fresh file here; with the result callback inert today, every
    // capture is orphaned in the cache. When we wire up the URI hand-off, delete
    // on success/cancel and sweep stale files on next entry.
    return FileProvider.getUriForFile(
        context,
        "${context.packageName}.gutenberg.fileprovider",
        file,
    )
}

@Composable
private fun MediaActionTile(
    icon: ImageVector,
    label: String,
    background: ComposeColor,
    foreground: ComposeColor,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = modifier
            .clip(RoundedCornerShape(MEDIA_STACK_CORNER_DP.dp))
            .background(background)
            .clickable(onClick = onClick)
            // Announce as a single button rather than two stops (clickable
            // Column + inner Text). The Icon is decorative (contentDescription
            // = null) so the merged label is just the visible Text.
            .semantics(mergeDescendants = true) { role = Role.Button },
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = foreground,
            modifier = Modifier.size(MEDIA_STACK_ICON_SIZE_DP.dp),
        )
        Text(
            text = label,
            color = foreground,
            fontSize = MEDIA_STACK_LABEL_SP.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhotoAccessRationale(
    state: PromptState,
    onAllow: () -> Unit,
    onReject: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val bodyRes = when (state) {
        PromptState.Unasked -> R.string.gbk_block_inserter_photos_rationale
        PromptState.Denied -> R.string.gbk_block_inserter_photos_rationale_denied
        PromptState.PermanentlyDenied -> R.string.gbk_block_inserter_photos_rationale_permanent
    }
    val primaryLabelRes = when (state) {
        PromptState.Unasked -> R.string.gbk_block_inserter_photos_allow
        PromptState.Denied -> R.string.gbk_block_inserter_photos_try_again
        PromptState.PermanentlyDenied -> R.string.gbk_block_inserter_photos_open_settings
    }
    @Composable
    fun RationaleButton(label: String, filled: Boolean, onClick: () -> Unit, modifier: Modifier) {
        val bg = if (filled) MaterialTheme.colorScheme.primary else ComposeColor.Transparent
        val fg = if (filled) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.primary
        // Outer wrapper inflates the touch zone to the 48dp minimum; the inner
        // Box paints the design's 32dp pill. The shared interaction source lets
        // the outer absorb taps with no indication while the inner draws the
        // ripple — otherwise a default ripple on the outer would render as a
        // square halo around the rounded pill.
        val interactionSource = remember { MutableInteractionSource() }
        Box(
            contentAlignment = Alignment.Center,
            modifier = modifier
                .heightIn(min = TOUCH_TARGET_MIN_DP.dp)
                .clickable(
                    interactionSource = interactionSource,
                    indication = null,
                    role = Role.Button,
                    onClick = onClick,
                ),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(MEDIA_RATIONALE_BUTTON_HEIGHT_DP.dp)
                    .clip(RoundedCornerShape(MEDIA_RATIONALE_BUTTON_CORNER_DP.dp))
                    .background(bg)
                    .indication(interactionSource, ripple()),
            ) {
                Text(
                    text = label,
                    color = fg,
                    fontSize = MEDIA_RATIONALE_BUTTON_FONT_SP.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
    Column(
        verticalArrangement = Arrangement.SpaceBetween,
        modifier = modifier
            .height(MEDIA_STACK_HEIGHT_DP.dp)
            .clip(RoundedCornerShape(MEDIA_STACK_CORNER_DP.dp))
            .background(MaterialTheme.colorScheme.secondaryContainer)
            .padding(MEDIA_RATIONALE_PAD_DP.dp),
    ) {
        Text(
            text = stringResource(bodyRes),
            color = MaterialTheme.colorScheme.onSecondaryContainer,
            fontSize = MEDIA_RATIONALE_FONT_SP.sp,
            lineHeight = MEDIA_RATIONALE_LINE_HEIGHT_SP.sp,
            fontWeight = FontWeight.Medium,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(MEDIA_RATIONALE_BUTTON_GAP_DP.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            RationaleButton(
                label = stringResource(primaryLabelRes),
                filled = true,
                onClick = onAllow,
                modifier = Modifier.weight(1f),
            )
            RationaleButton(
                label = stringResource(R.string.gbk_block_inserter_photos_reject),
                filled = false,
                onClick = onReject,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun RealThumbnail(uri: Uri) {
    val context = LocalContext.current
    val sizePx = with(LocalDensity.current) { MEDIA_THUMB_SIZE_DP.dp.roundToPx() }
    var bitmap by remember(uri) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(uri, sizePx) {
        bitmap = withContext(Dispatchers.IO) { loadThumbnail(context, uri, sizePx) }
    }
    val bmp = bitmap
    if (bmp != null) {
        Image(
            bitmap = bmp,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(MEDIA_THUMB_SIZE_DP.dp)
                .clip(RoundedCornerShape(MEDIA_THUMB_CORNER_DP.dp)),
        )
    } else {
        // Neutral loading box — avoids flashing colorful mock-photo gradients
        // between the URI being known and the bitmap finishing async load.
        Box(
            modifier = Modifier
                .size(MEDIA_THUMB_SIZE_DP.dp)
                .clip(RoundedCornerShape(MEDIA_THUMB_CORNER_DP.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CategoryTabs(
    selected: BlockPickerTab,
    onSelect: (BlockPickerTab) -> Unit,
) {
    val tabs = BlockPickerTab.entries
    val selectedIndex = tabs.indexOf(selected).coerceAtLeast(0)
    // Tab labels sit 16dp inside the Tab layout (M3's internal
    // `HorizontalTextPadding`), so set `edgePadding` to `SEARCH_HORIZONTAL_PAD_DP
    // - 16` to align the first label's leading edge with the search bar's
    // outer edge instead of the default 52dp.
    SecondaryScrollableTabRow(
        selectedTabIndex = selectedIndex,
        containerColor = ComposeColor.Transparent,
        edgePadding = (SEARCH_HORIZONTAL_PAD_DP - TAB_INTERNAL_TEXT_PAD_DP).dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        tabs.forEach { tab ->
            Tab(
                selected = tab == selected,
                onClick = { onSelect(tab) },
                text = { Text(stringResource(tab.labelRes)) },
            )
        }
    }
}

@Composable
private fun SearchField(
    query: String,
    onQueryChange: (String) -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SEARCH_ICON_GAP_DP.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                top = SEARCH_TOP_PAD_DP.dp,
                bottom = SEARCH_BOTTOM_PAD_DP.dp,
                start = SEARCH_HORIZONTAL_PAD_DP.dp,
                end = SEARCH_HORIZONTAL_PAD_DP.dp,
            )
            .height(SEARCH_HEIGHT_DP.dp)
            .clip(RoundedCornerShape(SEARCH_CORNER_DP.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(horizontal = SEARCH_INNER_HORIZONTAL_PAD_DP.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.Search,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(SEARCH_ICON_SIZE_DP.dp),
        )
        SearchInput(
            query = query,
            onQueryChange = onQueryChange,
            modifier = Modifier.weight(1f),
        )
        if (query.isNotEmpty()) {
            IconButton(
                onClick = { onQueryChange("") },
                modifier = Modifier.size(SEARCH_ICON_SIZE_DP.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = stringResource(R.string.gbk_block_inserter_clear_search),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(ICON_SIZE_DP.dp),
                )
            }
        }
    }
}

@Composable
private fun SearchInput(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // The placeholder Text inside `decorationBox` is a visual hint, not an
    // accessible name — without `contentDescription` on the field, focusing
    // the empty field would announce as "edit box" with no context.
    // `clearAndSetSemantics {}` on the placeholder hides its own `text`
    // semantic so TalkBack reads the field's `contentDescription` once
    // ("Search blocks, edit box") instead of duplicating from the placeholder.
    val label = stringResource(R.string.gbk_block_inserter_search)
    BasicTextField(
        value = query,
        onValueChange = onQueryChange,
        singleLine = true,
        textStyle = TextStyle(
            fontSize = SEARCH_FONT_SP.sp,
            color = MaterialTheme.colorScheme.onSurface,
        ),
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        modifier = modifier.semantics { contentDescription = label },
        decorationBox = { inner ->
            if (query.isEmpty()) {
                Text(
                    text = label,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = SEARCH_FONT_SP.sp,
                    modifier = Modifier.clearAndSetSemantics {},
                )
            }
            inner()
        },
    )
}

@Composable
private fun BlockGridContent(
    blocks: List<BlockType>,
    query: String,
    onBlockClicked: (BlockType) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (blocks.isEmpty()) {
        EmptyState(query = query, modifier = modifier)
        return
    }
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    // Snap-dismiss the keyboard on the first user drag — reliable fallback for
    // per-pixel interactive dismiss, which doesn't work cleanly inside a
    // BottomSheetDialog window. Clear focus too so the search field doesn't
    // silently re-summon the keyboard on the next tap elsewhere.
    val hideKeyboardOnDrag = remember(keyboard, focusManager) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && available.y != 0f) {
                    keyboard?.hide()
                    focusManager.clearFocus()
                }
                return Offset.Zero
            }
        }
    }
    val iconCache = rememberSvgIconCache(chipColor = MaterialTheme.colorScheme.primaryContainer)
    LazyVerticalGrid(
        columns = GridCells.Fixed(5),
        contentPadding = PaddingValues(
            start = GRID_HORIZONTAL_PAD_DP.dp,
            end = GRID_HORIZONTAL_PAD_DP.dp,
            bottom = GRID_BOTTOM_PAD_DP.dp,
        ),
        horizontalArrangement = Arrangement.spacedBy(GRID_GAP_DP.dp),
        verticalArrangement = Arrangement.spacedBy(GRID_GAP_DP.dp),
        modifier = modifier.nestedScroll(hideKeyboardOnDrag),
    ) {
        items(
            count = blocks.size,
            key = { blocks[it].id },
        ) { index ->
            BlockTile(
                block = blocks[index],
                iconCache = iconCache,
                onClick = { onBlockClicked(blocks[index]) },
            )
        }
    }
}

/**
 * One cache per grid composition. Keyed on render size and chip colour so a
 * configuration change (font scale, theme switch) recomputes both the bitmap
 * pixel size and the contrast surrogate the tinting decision is measured
 * against — see `SvgIconCache.contrastSurface`.
 */
@Composable
private fun rememberSvgIconCache(chipColor: ComposeColor): SvgIconCache {
    val density = LocalDensity.current
    val sizePx = with(density) { BLOCK_TILE_ICON_GLYPH_SIZE_DP.dp.toPx() }.roundToInt()
    val surfaceArgb = chipColor.toArgb()
    return remember(sizePx, surfaceArgb) {
        SvgIconCache(renderSizePx = sizePx, contrastSurface = surfaceArgb)
    }
}

@Composable
private fun BlockTile(
    block: BlockType,
    iconCache: SvgIconCache,
    onClick: () -> Unit,
) {
    val bg = MaterialTheme.colorScheme.primaryContainer
    val tint = MaterialTheme.colorScheme.onSurface
    val contentAlpha = if (block.isDisabled) DISABLED_ALPHA else 1f
    val rendered = remember(block.id, iconCache) { iconCache.renderIcon(block) }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(BLOCK_TILE_ICON_LABEL_GAP_DP.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(BLOCK_TILE_BUTTON_CORNER_DP.dp))
            .clickable(
                enabled = !block.isDisabled,
                role = Role.Button,
                onClick = onClick,
            )
            .padding(
                horizontal = BLOCK_TILE_HORIZONTAL_PAD_DP.dp,
            )
            .padding(
                top = BLOCK_TILE_VERTICAL_PAD_TOP_DP.dp,
                bottom = BLOCK_TILE_VERTICAL_PAD_BOTTOM_DP.dp,
            ),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(BLOCK_TILE_ICON_SIZE_DP.dp)
                .clip(RoundedCornerShape(BLOCK_TILE_ICON_CORNER_DP.dp))
                .background(bg),
        ) {
            rendered?.let { icon ->
                Image(
                    bitmap = icon.bitmap.asImageBitmap(),
                    contentDescription = null,
                    alpha = contentAlpha,
                    colorFilter = if (icon.tintable) ColorFilter.tint(tint) else null,
                    modifier = Modifier.size(BLOCK_TILE_ICON_GLYPH_SIZE_DP.dp),
                )
            }
        }
        AutoShrinkTileLabel(
            text = block.title ?: block.name,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * Label that wraps multi-word text at whitespace (up to two lines) and shrinks
 * single-word text to fit on one line, down to [BLOCK_TILE_LABEL_MIN_SP].
 * Single-word labels never break mid-word: Compose's default soft-wrap will
 * character-break an overlong single word to satisfy the maxLines budget
 * (e.g. "Preformatted" → "Preform-" / "atted"), so we measure with
 * `maxLines = 1` and disable `softWrap` for single-word labels to force the
 * shrink path instead. The container reserves two lines worth of vertical
 * space at the resolved size so tile heights stay consistent across the grid.
 * Compose has no built-in autosize Text, so we pre-measure via
 * [rememberTextMeasurer].
 */
@Composable
private fun AutoShrinkTileLabel(
    text: String,
    color: ComposeColor,
    modifier: Modifier = Modifier,
) {
    val measurer = rememberTextMeasurer()
    BoxWithConstraints(modifier = modifier) {
        val maxWidthPx = constraints.maxWidth
        // Centre line height around the glyphs and trim the half-leading
        // above the first / below the last line. Without `Trim.Both` the
        // default leading shows up as a top gap on a single-line label and
        // an outsized gap between the two lines on a wrapped one — Material
        // 3 typography sets this for its presets, but custom sp + lineHeight
        // doesn't pick it up automatically.
        val lineHeightStyle = LineHeightStyle(
            alignment = LineHeightStyle.Alignment.Center,
            trim = LineHeightStyle.Trim.Both,
        )
        val style = TextStyle(
            fontWeight = FontWeight.Medium,
            letterSpacing = BLOCK_TILE_LABEL_LETTER_SPACING_SP.sp,
            textAlign = TextAlign.Center,
            lineHeightStyle = lineHeightStyle,
        )
        val canWrap = text.any { it.isWhitespace() }
        val measureMaxLines = if (canWrap) 2 else 1
        val resolvedSize = remember(text, maxWidthPx, canWrap) {
            var size = BLOCK_TILE_LABEL_SP
            while (size > BLOCK_TILE_LABEL_MIN_SP) {
                val result = measurer.measure(
                    text = text,
                    style = style.copy(
                        fontSize = size.sp,
                        lineHeight = (size * BLOCK_TILE_LABEL_LINE_HEIGHT_RATIO).sp,
                    ),
                    constraints = Constraints(maxWidth = maxWidthPx),
                    maxLines = measureMaxLines,
                )
                if (!result.didOverflowWidth && !result.didOverflowHeight) break
                size -= 1
            }
            size
        }
        Text(
            text = text,
            color = color,
            fontSize = resolvedSize.sp,
            lineHeight = (resolvedSize * BLOCK_TILE_LABEL_LINE_HEIGHT_RATIO).sp,
            fontWeight = FontWeight.Medium,
            letterSpacing = BLOCK_TILE_LABEL_LETTER_SPACING_SP.sp,
            textAlign = TextAlign.Center,
            style = TextStyle(lineHeightStyle = lineHeightStyle),
            softWrap = canWrap,
            minLines = 2,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun EmptyState(query: String, modifier: Modifier = Modifier) {
    val visibleText = if (query.isNotBlank()) {
        stringResource(R.string.gbk_block_inserter_no_results_for, query)
    } else {
        stringResource(R.string.gbk_block_inserter_no_results)
    }
    val announcedText = stringResource(R.string.gbk_block_inserter_no_results)
    // `liveRegion` so TalkBack announces the change when search filters the
    // grid down to no results — otherwise the composition swap is silent.
    // The visible Text would change on every keystroke that produces no
    // results, which would queue a fresh announcement each time. Keeping the
    // box's `contentDescription` constant — and clearing the inner Text's
    // own semantics — means TalkBack announces "No results" once on the
    // empty -> empty-results transition. The visible string still shows the
    // queried term to sighted users; blind users can re-focus the field to
    // hear the query back via `editableText`.
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .fillMaxWidth()
            .padding(
                horizontal = EMPTY_STATE_HORIZONTAL_PAD_DP.dp,
                vertical = EMPTY_STATE_VERTICAL_PAD_DP.dp,
            )
            .semantics {
                liveRegion = LiveRegionMode.Polite
                contentDescription = announcedText
            },
    ) {
        Text(
            text = visibleText,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = EMPTY_STATE_FONT_SP.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.clearAndSetSemantics {},
        )
    }
}

private fun dedupeById(blocks: List<BlockType>): List<BlockType> {
    val seen = HashSet<String>()
    return blocks.filter { seen.add(it.id) }
}

private fun filterByTab(
    tab: BlockPickerTab,
    allBlocks: List<BlockType>,
    recentBlocks: List<BlockType>,
): List<BlockType> {
    if (tab == BlockPickerTab.Recent) return recentBlocks
    val ids = tab.blockIds ?: return allBlocks
    return allBlocks.filter { it.name.substringAfterLast('/') in ids }
}

/**
 * Hardcoded block-id groupings from the design handoff. Production will likely
 * derive these from the payload, but the design freezes the taxonomy shown in
 * the tabs so we pin it here to match Variation B exactly.
 */
private enum class BlockPickerTab(
    val labelRes: Int,
    val blockIds: Set<String>?,
) {
    Recent(R.string.gbk_block_inserter_tab_recent, null),
    Text(
        R.string.gbk_block_inserter_tab_text,
        setOf("paragraph", "heading", "list", "quote", "preformatted"),
    ),
    Media(
        R.string.gbk_block_inserter_tab_media,
        setOf("image", "gallery", "video", "audio", "cover", "file"),
    ),
    Design(
        R.string.gbk_block_inserter_tab_design,
        setOf("table", "separator", "code", "columns", "button", "buttons"),
    ),
    Widgets(
        R.string.gbk_block_inserter_tab_widgets,
        setOf("button", "buttons", "separator"),
    ),
    Theme(
        R.string.gbk_block_inserter_tab_theme,
        setOf("cover", "columns", "gallery"),
    ),
    Embeds(
        R.string.gbk_block_inserter_tab_embeds,
        setOf("video", "audio", "embed"),
    );
}
