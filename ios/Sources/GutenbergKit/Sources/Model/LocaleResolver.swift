import Foundation
import GutenbergKitResources

/// Resolves an arbitrary locale tag to one of the bundles GutenbergKit
/// actually ships translations for.
///
/// Consumers (WP-iOS, WP-Android) historically hand `EditorConfiguration`
/// an opaque locale string and the editor silently falls back to English
/// whenever the tag doesn't match a shipped `translations/<tag>.json` file
/// exactly. The resolver moves that decision into the library, so a device
/// configured for `pt_BR` ends up with the Brazilian Portuguese bundle —
/// and a tag like `nl-BE`, for which we don't ship a regional bundle, falls
/// back to `nl` instead of all the way to English.
///
/// Resolution chain for an input `xx-yy`:
///   1. Full normalised tag (`xx-yy`)
///   2. Language-only tag (`xx`)
///   3. `en`
///
/// The supported set is read from a manifest emitted by the JS build, so it
/// stays in sync with what the bundle actually ships.
struct LocaleResolver {
    static let `default` = LocaleResolver()

    private let supportedLocales: Set<String>

    init(supportedLocales: [String]? = nil) {
        let source = supportedLocales ?? GutenbergKitResources.loadSupportedLocales()
        self.supportedLocales = Set(source.map { Self.normalize($0) })
    }

    /// Resolves a string locale tag against the shipped translation bundles.
    func resolve(_ tag: String) -> String {
        let normalized = Self.normalize(tag)
        if supportedLocales.contains(normalized) {
            return normalized
        }
        if let language = normalized.split(separator: "-").first.map(String.init),
           !language.isEmpty,
           supportedLocales.contains(language) {
            return language
        }
        return "en"
    }

    /// Resolves a `Locale` value against the shipped translation bundles.
    func resolve(_ locale: Locale) -> String {
        resolve(locale.identifier(.bcp47))
    }

    private static func normalize(_ tag: String) -> String {
        tag.lowercased().replacingOccurrences(of: "_", with: "-")
    }
}
