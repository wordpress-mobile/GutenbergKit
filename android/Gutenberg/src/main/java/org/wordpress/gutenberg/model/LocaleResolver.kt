package org.wordpress.gutenberg.model

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
 * Resolution chain for an input locale:
 *   1. `language-region`
 *   2. `language-<script-implied region>` (e.g. `zh-Hant-HK` → `zh-tw`)
 *   3. `language`
 *   4. `en`
 *
 * Inputs are parsed as BCP-47 via [Locale.forLanguageTag], so script-tagged
 * inputs like `zh-Hans-CN` collapse to `zh-cn` rather than falling through
 * to English. Underscore-separated identifiers (`pt_BR`, `EN_GB`) are
 * pre-normalised to dashes before parsing. Legacy ISO 639-1 codes that
 * Android's `Locale` class still emits (`iw` for Hebrew, `in` for
 * Indonesian, `no` for Norwegian Bokmål) are mapped to their canonical
 * equivalents before lookup. Variant and Unicode-extension subtags (e.g.
 * `de-DE-u-ca-gregory`) are ignored — the editor doesn't vary translations
 * by calendar or numbering system.
 *
 * The supported set is generated at build time from the JS build manifest
 * (see `:Gutenberg:generateSupportedLocales`), so the resolver and the
 * shipped bundles cannot drift.
 */
internal class LocaleResolver(supportedLocales: Collection<String>) {
    private val supportedLocales: Set<String> =
        supportedLocales.map { normalize(it) }.toSet()

    constructor() : this(SupportedLocales.ALL)

    /**
     * Resolves a string locale tag against the shipped translation bundles.
     *
     * Accepts BCP-47 tags (`pt-BR`, `zh-Hant-HK`) and the underscore-separated
     * variant Android's platform APIs emit (`pt_BR`). Inputs that aren't valid
     * BCP-47 — POSIX locales like `pt_BR.UTF-8`, anything `Locale.forLanguageTag`
     * can't parse to a non-empty language — fall back to `en`.
     */
    fun resolve(tag: String?): String {
        if (tag.isNullOrEmpty()) return DEFAULT_LOCALE
        // Java's BCP-47 parser uses '-'; pre-normalise '_' so platform-native
        // identifiers like `pt_BR` parse cleanly.
        return resolve(Locale.forLanguageTag(tag.replace('_', '-')))
    }

    /** Resolves a [Locale] against the shipped translation bundles. */
    fun resolve(locale: Locale): String {
        val rawLanguage = locale.language.lowercase(Locale.ROOT)
        if (rawLanguage.isEmpty()) return DEFAULT_LOCALE
        val language = LANGUAGE_ALIASES[rawLanguage] ?: rawLanguage

        val region = locale.country.lowercase(Locale.ROOT)
        if (region.isNotEmpty()) {
            val full = "$language-$region"
            if (supportedLocales.contains(full)) return full
        }

        // For macrolanguages where we ship disjoint regional bundles only
        // (e.g. `zh-cn`/`zh-tw` with no language-only `zh`), fall back to a
        // script-implied region before the language-only step. Without this,
        // `zh-Hant-HK` and bare `zh-Hans` end up at English even though the
        // script subtag clearly indicates Traditional/Simplified intent.
        val script = locale.script.lowercase(Locale.ROOT)
        if (script.isNotEmpty()) {
            val implied = scriptImpliedTag(language, script)
            if (implied != null && supportedLocales.contains(implied)) return implied
        }

        if (supportedLocales.contains(language)) return language

        return DEFAULT_LOCALE
    }

    companion object {
        // Reused by `EditorConfiguration.Builder.setLocale` so the
        // supported-set HashSet isn't rebuilt on every call.
        val Default: LocaleResolver = LocaleResolver()

        private const val DEFAULT_LOCALE = "en"

        // Android's `Locale` class still emits the legacy ISO 639-1 codes for
        // Hebrew (`iw`) and Indonesian (`in`) for backward compat, and the
        // deprecated `no` macrolanguage tag survives in some configurations
        // for the Bokmål bundle we ship as `nb`. Translate before lookup so
        // users on those devices don't silently land on English.
        private val LANGUAGE_ALIASES = mapOf(
            "iw" to "he",
            "in" to "id",
            "no" to "nb",
        )

        private fun normalize(tag: String): String =
            tag.lowercase(Locale.ROOT).replace('_', '-')

        private fun scriptImpliedTag(language: String, script: String): String? = when {
            language == "zh" && script == "hans" -> "zh-cn"
            language == "zh" && script == "hant" -> "zh-tw"
            else -> null
        }
    }
}
