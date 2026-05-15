package org.wordpress.gutenberg

import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

/**
 * Property delegate that allows exactly one assignment per instance. A second
 * `set` throws `IllegalStateException`; reading before any assignment throws
 * `UninitializedPropertyAccessException`. Use for `lateinit`-shaped fields
 * whose initialization is centralized in one method and whose accidental
 * reassignment would silently overwrite state — e.g., the asset loader, whose
 * registered path handlers were lost when an earlier refactor introduced a
 * second builder.
 */
internal class WriteOnce<T : Any> : ReadWriteProperty<Any?, T> {
    private var value: T? = null

    override fun getValue(thisRef: Any?, property: KProperty<*>): T =
        value ?: throw UninitializedPropertyAccessException(
            "Property ${property.name} has not been initialized",
        )

    override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) {
        check(this.value == null) {
            "Property ${property.name} can only be assigned once"
        }
        this.value = value
    }
}

internal fun <T : Any> writeOnce(): ReadWriteProperty<Any?, T> = WriteOnce()
