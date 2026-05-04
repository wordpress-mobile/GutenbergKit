package org.wordpress.gutenberg.model

import android.content.Context
import kotlinx.serialization.json.Json
import java.util.Locale

/**
 * Resolves an arbitrary locale tag to one of the bundles GutenbergKit
 * actually ships translations for.
 *
 * Consumers historically hand [EditorConfiguration] an opaque locale string
 * — on Android, often the output of [Locale.getLanguage], which strips the
 * region. The editor then silently falls back to English whenever the tag
 * doesn't match a shipped `translations/<tag>.json` file exactly. The
 * resolver moves that decision into the library, so a device configured for
 * `pt_BR` ends up with the Brazilian Portuguese bundle — and a tag like
 * `nl-BE`, for which we don't ship a regional bundle, falls back to `nl`
 * instead of all the way to English.
 *
 * Resolution chain for an input `xx-yy`:
 *   1. Full normalised tag (`xx-yy`)
 *   2. Language-only tag (`xx`)
 *   3. `en`
 *
 * The supported set is read from a manifest emitted by the JS build, so it
 * stays in sync with what the bundle actually ships.
 */
class LocaleResolver internal constructor(supportedLocales: Collection<String>) {
    private val supportedLocales: Set<String> =
        supportedLocales.map { normalize(it) }.toSet()

    /** Resolves a string locale tag against the shipped translation bundles. */
    fun resolve(tag: String?): String {
        if (tag.isNullOrEmpty()) return DEFAULT_LOCALE

        val normalized = normalize(tag)
        if (supportedLocales.contains(normalized)) return normalized

        val language = normalized.substringBefore('-')
        if (language.isNotEmpty() && supportedLocales.contains(language)) {
            return language
        }

        return DEFAULT_LOCALE
    }

    /** Resolves a [Locale] against the shipped translation bundles. */
    fun resolve(locale: Locale): String = resolve(locale.toLanguageTag())

    companion object {
        private const val DEFAULT_LOCALE = "en"
        private const val MANIFEST_ASSET_PATH = "supported-locales.json"

        /**
         * Builds a resolver backed by the manifest shipped in `assets/`.
         *
         * Returns a resolver with an empty supported set when the manifest
         * is missing or unreadable — callers will get [DEFAULT_LOCALE] for
         * every input rather than crashing.
         */
        @JvmStatic
        fun fromAssets(context: Context): LocaleResolver {
            val locales = try {
                context.assets.open(MANIFEST_ASSET_PATH).use { stream ->
                    Json.decodeFromString<List<String>>(stream.bufferedReader().readText())
                }
            } catch (_: Exception) {
                emptyList()
            }
            return LocaleResolver(locales)
        }

        private fun normalize(tag: String): String =
            tag.lowercase(Locale.ROOT).replace('_', '-')
    }
}
