import Foundation
import GutenbergKitResources

/// Resolves an arbitrary locale tag to one of the bundles GutenbergKit
/// actually ships translations for.
///
/// Consumers (WP-iOS) historically hand `EditorConfiguration` an opaque
/// locale string and the editor silently falls back to English whenever the
/// tag doesn't match a shipped `translations/<tag>.json` file exactly. The
/// resolver moves that decision into the library, so a device configured
/// for `pt_BR` ends up with the Brazilian Portuguese bundle — and a tag
/// like `nl-BE`, for which we don't ship a regional bundle, falls back to
/// `nl` instead of all the way to English.
///
/// Resolution chain for an input locale:
///   1. `language-region`
///   2. `language-<script-implied region>` (e.g. `zh-Hant-HK` → `zh-tw`)
///   3. `language`
///   4. `en`
///
/// String inputs are normalised (`_` → `-`) and then parsed via
/// `Locale(identifier:)`, so script-tagged inputs like `zh-Hans-CN`
/// collapse to `zh-cn` rather than falling through to English. Legacy
/// ISO 639-1 codes that platforms still emit (`iw` for Hebrew, `in` for
/// Indonesian, `no` for Norwegian Bokmål) are mapped to their canonical
/// equivalents before lookup. Variant and Unicode-extension subtags
/// (e.g. `de-DE-u-ca-gregory`) are ignored — the editor doesn't vary
/// translations by calendar or numbering system.
///
/// The supported set is read from a manifest emitted by the JS build, so
/// it stays in sync with what the bundle actually ships.
struct LocaleResolver {
    static let `default` = LocaleResolver()

    private let supportedLocales: Set<String>

    init(supportedLocales: [String]? = nil) {
        let source = supportedLocales ?? GutenbergKitResources.loadSupportedLocales()
        self.supportedLocales = Set(source.map { Self.normalize($0) })
    }

    /// Resolves a string locale tag against the shipped translation bundles.
    ///
    /// Accepts BCP-47 tags (`pt-BR`, `zh-Hant-HK`) and the underscore-separated
    /// variant platform APIs sometimes emit (`pt_BR`). Empty or `nil` input
    /// falls back to `en`.
    func resolve(_ tag: String?) -> String {
        guard let tag, !tag.isEmpty else { return Self.defaultLocale }
        // Foundation's identifier parser accepts both ICU-ish (`pt_BR`) and
        // BCP-47 (`pt-BR`) input, but pre-normalising to dashes keeps
        // script-tagged inputs like `zh_Hans_CN` parsing cleanly.
        return resolve(Locale(identifier: tag.replacingOccurrences(of: "_", with: "-")))
    }

    /// Resolves a `Locale` value against the shipped translation bundles.
    func resolve(_ locale: Locale) -> String {
        let rawLanguage = (locale.language.languageCode?.identifier ?? "").lowercased()
        if rawLanguage.isEmpty { return Self.defaultLocale }
        let language = Self.languageAliases[rawLanguage] ?? rawLanguage

        let region = (locale.region?.identifier ?? "").lowercased()
        if !region.isEmpty {
            let full = "\(language)-\(region)"
            if supportedLocales.contains(full) { return full }
        }

        // For macrolanguages where we ship disjoint regional bundles only
        // (e.g. `zh-cn`/`zh-tw` with no language-only `zh`), fall back to a
        // script-implied region before the language-only step. Without this,
        // `zh-Hant-HK` and bare `zh-Hans` end up at English even though the
        // script subtag clearly indicates Traditional/Simplified intent.
        let script = (locale.language.script?.identifier ?? "").lowercased()
        if !script.isEmpty,
           let implied = Self.scriptImpliedTag(language: language, script: script),
           supportedLocales.contains(implied) {
            return implied
        }

        if supportedLocales.contains(language) { return language }

        return Self.defaultLocale
    }

    private static let defaultLocale = "en"

    // Some platform `Locale` implementations still emit the legacy ISO 639-1
    // codes for Hebrew (`iw`) and Indonesian (`in`) for backward compat, and
    // the deprecated `no` macrolanguage tag survives in some configurations
    // for the Bokmål bundle we ship as `nb`. Translate before lookup so users
    // on those devices don't silently land on English.
    private static let languageAliases: [String: String] = [
        "iw": "he",
        "in": "id",
        "no": "nb",
    ]

    private static func normalize(_ tag: String) -> String {
        tag.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    private static func scriptImpliedTag(language: String, script: String) -> String? {
        switch (language, script) {
        case ("zh", "hans"): return "zh-cn"
        case ("zh", "hant"): return "zh-tw"
        default: return nil
        }
    }
}
