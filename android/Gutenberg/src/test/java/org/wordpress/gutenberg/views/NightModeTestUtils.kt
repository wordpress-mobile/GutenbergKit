package org.wordpress.gutenberg.views

import android.content.Context
import android.content.res.Configuration

/** The context's configuration with its night mode flipped. */
internal fun nightModeToggled(context: Context) = Configuration(context.resources.configuration).apply {
    val nightMode = uiMode and Configuration.UI_MODE_NIGHT_MASK
    val toggled = if (nightMode == Configuration.UI_MODE_NIGHT_YES) {
        Configuration.UI_MODE_NIGHT_NO
    } else {
        Configuration.UI_MODE_NIGHT_YES
    }
    uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or toggled
}
