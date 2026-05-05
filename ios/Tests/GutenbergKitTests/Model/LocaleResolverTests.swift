import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct LocaleResolverTests {
  // Stand-in for the manifest emitted at build time. Mirrors the real
  // supported set closely enough to exercise both fallback steps.
  static let supported = [
    "de", "en-gb", "es", "es-ar", "fr", "nl", "nl-be", "pt", "pt-br", "zh-cn", "zh-tw",
  ]

  static let resolver = LocaleResolver(supportedLocales: supported)

  @Test("nil and empty input fall back to English")
  func emptyFallsBack() {
    #expect(Self.resolver.resolve(nil) == "en")
    #expect(Self.resolver.resolve("") == "en")
  }

  @Test("Full normalized tag is returned when shipped")
  func fullTagMatch() {
    #expect(Self.resolver.resolve("pt-br") == "pt-br")
    #expect(Self.resolver.resolve("pt-BR") == "pt-br")
    #expect(Self.resolver.resolve("pt_BR") == "pt-br")
    #expect(Self.resolver.resolve("EN_GB") == "en-gb")
    #expect(Self.resolver.resolve("zh-CN") == "zh-cn")
  }

  @Test("Falls back to language-only tag when the regional bundle is absent")
  func languageFallback() {
    // `fr-CA` not shipped, but `fr` is.
    #expect(Self.resolver.resolve("fr-CA") == "fr")
    // `de-AT` not shipped, but `de` is.
    #expect(Self.resolver.resolve("de-AT") == "de")
  }

  @Test("Falls back to English when neither full nor language match")
  func englishFallback() {
    // `xx-yy` parses to language=xx, region=yy with no script: nothing
    // matches and we land on English.
    #expect(Self.resolver.resolve("xx-yy") == "en")
  }

  @Test("Resolves Locale values via language and region")
  func resolveLocaleValue() {
    #expect(Self.resolver.resolve(Locale(identifier: "pt_BR")) == "pt-br")
    #expect(Self.resolver.resolve(Locale(identifier: "fr_CA")) == "fr")
    // Foundation supplies an implicit script for bare-language tags
    // (`zh` → `Hans`, `ja` → `Jpan`, etc.), so the script-implied step
    // resolves a bare `zh` to `zh-cn` instead of English. This is a
    // deliberate iOS-side win over Android's `Locale.forLanguageTag`,
    // which leaves the script unset and falls through to language-only.
    #expect(Self.resolver.resolve(Locale(identifier: "zh")) == "zh-cn")
    #expect(Self.resolver.resolve("zh") == "zh-cn")
  }

  @Test("Script-tagged inputs collapse to the regional bundle")
  func scriptStripping() {
    // Without script-aware handling these end up as `zh-hans-cn`, miss the
    // supported set, and fall through to English despite a `zh-cn` bundle
    // being available.
    #expect(Self.resolver.resolve("zh-Hans-CN") == "zh-cn")
    #expect(Self.resolver.resolve("zh-Hant-TW") == "zh-tw")
    #expect(Self.resolver.resolve(Locale(identifier: "zh-Hans-CN")) == "zh-cn")
    #expect(Self.resolver.resolve(Locale(identifier: "zh-Hant-TW")) == "zh-tw")
  }

  @Test("Script subtag implies region when language-region and language are absent")
  func scriptImpliedRegion() {
    // We ship `zh-cn` and `zh-tw` but no language-only `zh`. Without a
    // script-aware fallback, Hong Kong and Macau Traditional Chinese users
    // (`zh-Hant-HK` / `zh-Hant-MO`) silently land on English even though
    // `Hant` clearly indicates Traditional Chinese.
    #expect(Self.resolver.resolve("zh-Hant-HK") == "zh-tw")
    #expect(Self.resolver.resolve("zh-Hant-MO") == "zh-tw")
    #expect(Self.resolver.resolve(Locale(identifier: "zh-Hant-HK")) == "zh-tw")
    #expect(Self.resolver.resolve(Locale(identifier: "zh-Hant-MO")) == "zh-tw")

    // Bare `zh-Hans` / `zh-Hant` with no region still implies a bundle.
    #expect(Self.resolver.resolve("zh-Hans") == "zh-cn")
    #expect(Self.resolver.resolve("zh-Hant") == "zh-tw")
    #expect(Self.resolver.resolve(Locale(identifier: "zh-Hans")) == "zh-cn")
    #expect(Self.resolver.resolve(Locale(identifier: "zh-Hant")) == "zh-tw")
  }

  @Test("Legacy ISO 639-1 codes are aliased to canonical bundles")
  func legacyAliases() {
    // Foundation already canonicalises `iw` → `he`, `in` → `id`, and
    // `no` → `nb` when parsing identifiers, so these inputs land on the
    // canonical bundles even before the resolver's defensive alias map
    // runs. Tests assert the user-facing behaviour either way: a Hebrew
    // or Indonesian device shouldn't fall through to English.
    let aliasResolver = LocaleResolver(supportedLocales: ["he", "id", "nb"])

    #expect(aliasResolver.resolve("iw") == "he")
    #expect(aliasResolver.resolve("iw-IL") == "he")
    #expect(aliasResolver.resolve(Locale(identifier: "iw_IL")) == "he")

    #expect(aliasResolver.resolve("in") == "id")
    #expect(aliasResolver.resolve("in-ID") == "id")
    #expect(aliasResolver.resolve(Locale(identifier: "in_ID")) == "id")

    // Norwegian macrolanguage `no` falls through to the Bokmål bundle.
    #expect(aliasResolver.resolve("no") == "nb")
    #expect(aliasResolver.resolve(Locale(identifier: "no")) == "nb")
  }

  @Test("Variant and extension subtags are ignored")
  func variantsAndExtensions() {
    // Calendar and other Unicode extensions shouldn't influence which
    // bundle ships — the editor doesn't vary translations by calendar.
    #expect(Self.resolver.resolve("de-DE-u-ca-gregory") == "de")
    #expect(Self.resolver.resolve("pt-BR-u-nu-latn") == "pt-br")
  }

  // MARK: - Exhaustive coverage of the shipped manifest

  // `SupportedLocales.all` is generated at build time by
  // `SupportedLocalesPlugin` from the JS-emitted manifest, so the set
  // reflects what the bundle actually ships. Each parameterised case
  // asserts the round-trip contract: a shipped tag must resolve to
  // itself — no normalisation tricks, no accidental fallbacks.

  static let shippedLocales = Array(SupportedLocales.all).sorted()

  @Test("SupportedLocales.all is non-empty (plugin should fail the build otherwise)")
  func manifestPresent() {
    #expect(!Self.shippedLocales.isEmpty)
  }

  @Test("Every shipped locale resolves to itself", arguments: shippedLocales)
  func shippedLocaleRoundTrip(locale: String) {
    #expect(LocaleResolver.default.resolve(locale) == locale)
  }
}
