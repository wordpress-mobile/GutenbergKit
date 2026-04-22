package org.wordpress.gutenberg.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize
import kotlinx.serialization.Serializable

/**
 * Host-declared user capabilities passed into the editor.
 *
 * These are serialized into `window.GBKit.userCapabilities` and used by
 * the JavaScript editor to preseed `@wordpress/core-data`'s `canUser`
 * results, bypassing the cross-origin OPTIONS inference path that cannot
 * read the REST `Allow` header.
 */
@Parcelize
@Serializable
data class UserCapabilities(
    /** Whether the user has the `upload_files` WordPress capability. */
    val uploadFiles: Boolean = false
) : Parcelable
