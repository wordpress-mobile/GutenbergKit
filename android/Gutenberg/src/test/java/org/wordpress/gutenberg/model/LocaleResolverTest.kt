package org.wordpress.gutenberg.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class LocaleResolverTest {

    // Stand-in for the manifest emitted at build time. Mirrors the real
    // supported set closely enough to exercise both fallback steps.
    private val resolver = LocaleResolver(
        listOf(
            "de", "en-gb", "es", "es-ar", "fr", "nl", "nl-be",
            "pt", "pt-br", "zh-cn", "zh-tw"
        )
    )

    @Test
    fun `null and empty input fall back to English`() {
        assertEquals("en", resolver.resolve(null))
        assertEquals("en", resolver.resolve(""))
    }

    @Test
    fun `full normalized tag is returned when shipped`() {
        assertEquals("pt-br", resolver.resolve("pt-br"))
        assertEquals("pt-br", resolver.resolve("pt-BR"))
        assertEquals("pt-br", resolver.resolve("pt_BR"))
        assertEquals("en-gb", resolver.resolve("EN_GB"))
        assertEquals("zh-cn", resolver.resolve("zh-CN"))
    }

    @Test
    fun `falls back to language-only tag when the regional bundle is absent`() {
        // `fr-CA` not shipped, but `fr` is.
        assertEquals("fr", resolver.resolve("fr-CA"))
        // `de-AT` not shipped, but `de` is.
        assertEquals("de", resolver.resolve("de-AT"))
    }

    @Test
    fun `falls back to English when neither full nor language match`() {
        // We ship `zh-cn`/`zh-tw` but no language-only `zh`. This is the
        // real-world footgun the Brazilian/Chinese examples in issue 490
        // describe — `Locale#getLanguage` returns just `zh`, which has
        // historically dropped users into the English bundle.
        assertEquals("en", resolver.resolve("zh"))
        assertEquals("en", resolver.resolve("xx-yy"))
    }

    @Test
    fun `resolves Locale values via language and region`() {
        assertEquals("pt-br", resolver.resolve(Locale("pt", "BR")))
        assertEquals("fr", resolver.resolve(Locale("fr", "CA")))
        assertEquals("zh-cn", resolver.resolve(Locale.SIMPLIFIED_CHINESE))
        // The footgun this issue fixes: WP-Android historically passed
        // `Locale.getLanguage()` (just `zh`), which dropped Chinese users
        // into English. The resolver still falls back to `en` for that
        // bare tag because we ship no language-only `zh` bundle — but
        // consumers who pass the full `Locale` now get `zh-cn`.
        assertEquals("en", resolver.resolve(Locale("zh")))
    }

    @Test
    fun `script subtags are stripped before matching`() {
        // `LocaleListCompat` and `Locale.forLanguageTag` callers can produce
        // script-tagged inputs. Without explicit handling these lowercase to
        // `zh-hans-cn`, miss the supported set, and fall through to English
        // despite a `zh-cn` bundle being available.
        assertEquals("zh-cn", resolver.resolve("zh-Hans-CN"))
        assertEquals("zh-tw", resolver.resolve("zh-Hant-TW"))
        assertEquals("zh-cn", resolver.resolve(Locale.forLanguageTag("zh-Hans-CN")))
        assertEquals("zh-tw", resolver.resolve(Locale.forLanguageTag("zh-Hant-TW")))
    }

    @Test
    fun `script subtag implies region when language-region and language are absent`() {
        // We ship `zh-cn` and `zh-tw` but no language-only `zh`. Without a
        // script-aware fallback, Hong Kong and Macau Traditional Chinese
        // users (`zh-Hant-HK` / `zh-Hant-MO`) silently land on English even
        // though `Hant` clearly indicates Traditional Chinese.
        assertEquals("zh-tw", resolver.resolve("zh-Hant-HK"))
        assertEquals("zh-tw", resolver.resolve("zh-Hant-MO"))
        assertEquals("zh-tw", resolver.resolve(Locale.forLanguageTag("zh-Hant-HK")))
        assertEquals("zh-tw", resolver.resolve(Locale.forLanguageTag("zh-Hant-MO")))

        // Bare `zh-Hans` / `zh-Hant` with no region still implies a bundle.
        assertEquals("zh-cn", resolver.resolve("zh-Hans"))
        assertEquals("zh-tw", resolver.resolve("zh-Hant"))
        assertEquals("zh-cn", resolver.resolve(Locale.forLanguageTag("zh-Hans")))
        assertEquals("zh-tw", resolver.resolve(Locale.forLanguageTag("zh-Hant")))
    }

    @Test
    fun `legacy ISO 639-1 codes are aliased to canonical bundles`() {
        // Android's `Locale` class emits the legacy codes for Hebrew (`iw`)
        // and Indonesian (`in`) — both for `Locale(String)` and for tags
        // round-tripped through `Locale.forLanguageTag`. Without the alias
        // map, every Hebrew or Indonesian device that hits this resolver
        // via the system Locale falls back to English despite shipping the
        // bundles.
        val aliasResolver = LocaleResolver(listOf("he", "id", "nb"))

        assertEquals("he", aliasResolver.resolve("iw"))
        assertEquals("he", aliasResolver.resolve("iw-IL"))
        assertEquals("he", aliasResolver.resolve(Locale("iw", "IL")))

        assertEquals("id", aliasResolver.resolve("in"))
        assertEquals("id", aliasResolver.resolve("in-ID"))
        assertEquals("id", aliasResolver.resolve(Locale("in", "ID")))

        // Norwegian macrolanguage `no` falls through to the Bokmål bundle.
        assertEquals("nb", aliasResolver.resolve("no"))
        assertEquals("nb", aliasResolver.resolve(Locale("no")))
    }

    @Test
    fun `variant and extension subtags are ignored`() {
        // Calendar and other Unicode extensions shouldn't influence which
        // bundle ships — the editor doesn't vary translations by calendar.
        assertEquals("de", resolver.resolve("de-DE-u-ca-gregory"))
        assertEquals("pt-br", resolver.resolve("pt-BR-u-nu-latn"))
    }

    // Exhaustive coverage of the shipped manifest. Each tag must resolve to
    // itself — no normalisation tricks, no accidental fallbacks. The set is
    // generated from the JS build manifest at compile time, so a missing
    // manifest fails the build long before we get here.
    @Test
    fun `every shipped locale resolves to itself`() {
        assertTrue(
            "SupportedLocales.ALL is empty — generator should have failed the build",
            SupportedLocales.ALL.isNotEmpty()
        )

        SupportedLocales.ALL.forEach { locale ->
            assertEquals(
                "Shipped locale '$locale' should resolve to itself",
                locale,
                LocaleResolver.Default.resolve(locale)
            )
        }
    }
}
