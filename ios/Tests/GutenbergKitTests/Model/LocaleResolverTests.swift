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

  @Test("Empty input falls back to English")
  func emptyFallsBack() {
    #expect(Self.resolver.resolve("") == "en")
  }

  @Test("Full normalized tag is returned when shipped")
  func fullTagMatch() {
    #expect(Self.resolver.resolve("pt-br") == "pt-br")
    #expect(Self.resolver.resolve("pt-BR") == "pt-br")
    #expect(Self.resolver.resolve("pt_BR") == "pt-br")
    #expect(Self.resolver.resolve("EN_GB") == "en-gb")
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
    // We ship `zh-cn`/`zh-tw` but no language-only `zh`.
    #expect(Self.resolver.resolve("zh") == "en")
    #expect(Self.resolver.resolve("xx-yy") == "en")
  }

  @Test("Resolves Locale values via BCP-47 identifier")
  func resolveLocaleValue() {
    #expect(Self.resolver.resolve(Locale(identifier: "pt_BR")) == "pt-br")
    #expect(Self.resolver.resolve(Locale(identifier: "fr_CA")) == "fr")
    #expect(Self.resolver.resolve(Locale(identifier: "zh_Hans")) == "en")
  }
}
