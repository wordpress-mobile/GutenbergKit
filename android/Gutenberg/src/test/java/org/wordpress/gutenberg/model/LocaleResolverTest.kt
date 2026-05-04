package org.wordpress.gutenberg.model

import org.junit.Assert.assertEquals
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
    fun `resolves Locale values via toLanguageTag`() {
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
}
