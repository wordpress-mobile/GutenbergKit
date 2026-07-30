import Foundation

/// Resolves the language the app was launched in to a locale the editor ships
/// translations for.
///
/// Xcode's *App Language* scheme option launches the app with
/// `-AppleLanguages (<tag>)`, which surfaces in `Locale.preferredLanguages`.
/// Forwarding that to `EditorConfiguration` lets the demo app exercise the
/// editor's localization by changing a dropdown rather than editing code.
///
/// - Note: `Bundle.main.preferredLocalizations` is deliberately *not* used. It
///   filters against the localizations the app bundle itself ships, and the
///   demo app ships only English, so every selection would collapse to `en`.
///
/// - Note: Xcode's *Right-to-Left Pseudolanguage* options are not supported.
///   They are not languages: Xcode launches the app with `-AppleTextDirection
///   YES -NSForceRightToLeftWritingDirection YES` and no `-AppleLanguages`, so
///   `Locale.preferredLanguages` still reports the device language and the
///   editor loads the corresponding translations. UIKit mirrors its own layout
///   from those flags, so the app around the editor will flip while the editor
///   itself does not. To exercise right-to-left rendering in the editor, select
///   a real right-to-left language such as Arabic or Hebrew.
///
/// - Important: This duplicates the resolution chain that
///   [PR #492](https://github.com/wordpress-mobile/GutenbergKit/pull/492) adds
///   to the library as `LocaleResolver`, matching the Android implementation
///   already merged in #493. It exists only because the iOS half is frozen.
///   When that lands, delete this type and pass `Locale.current` to
///   `setLocale(_:)` directly — the library will do the resolving.
enum DemoAppLocale {

    /// The editor locale matching the language the app is running in.
    static var current: String {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }

    /// Resolves the first supported locale among `preferredLanguages`.
    ///
    /// Falls back to English when nothing matches, mirroring the editor's own
    /// behavior for unshipped locales.
    static func resolve(
        preferredLanguages: [String],
        supportedLocales: Set<String> = Self.supportedLocales
    ) -> String {
        for language in preferredLanguages {
            if let match = resolve(language: language, supportedLocales: supportedLocales) {
                return match
            }

            // English is the editor's source language, so no `en` bundle ships
            // and the lookup above cannot match it. Stop rather than falling
            // through to the next preferred language: the user asked for
            // English, and English is what the editor renders without a bundle.
            // Regional variants that do ship — `en-gb`, `en-au` — match above.
            if isEnglish(language) {
                return defaultLocale
            }
        }
        return defaultLocale
    }

    /// Whether a tag's language subtag is English, regardless of region.
    static func isEnglish(_ language: String) -> Bool {
        let normalized = language.replacingOccurrences(of: "_", with: "-")
        return Locale.Components(identifier: normalized)
            .languageComponents.languageCode?.identifier.lowercased() == defaultLocale
    }

    /// Resolution chain for a single tag, mirroring the Android `LocaleResolver`:
    /// `language-region`, then a script-implied region, then the bare language.
    ///
    /// Tags carrying a private-use region need no special handling: `XA`/`XB`
    /// match no bundle, so the chain falls through to the base language.
    private static func resolve(language: String, supportedLocales: Set<String>) -> String? {
        let normalized = language.replacingOccurrences(of: "_", with: "-")
        let components = Locale.Components(identifier: normalized)

        guard let code = components.languageComponents.languageCode?.identifier.lowercased(),
              !code.isEmpty
        else {
            return nil
        }

        // Android's `Locale` still emits legacy ISO 639-1 codes for these
        // languages. Aliased here too so both platforms resolve alike.
        let language = languageAliases[code] ?? code

        if let region = components.languageComponents.region?.identifier.lowercased() {
            let tag = "\(language)-\(region)"
            if supportedLocales.contains(tag) {
                return tag
            }
        }

        // For macrolanguages shipped only as regional bundles (`zh-cn`,
        // `zh-tw`), a script subtag indicates which one is intended.
        if let script = components.languageComponents.script?.identifier.lowercased(),
           let implied = scriptImpliedTag(language: language, script: script),
           supportedLocales.contains(implied) {
            return implied
        }

        return supportedLocales.contains(language) ? language : nil
    }

    private static func scriptImpliedTag(language: String, script: String) -> String? {
        switch (language, script) {
        case ("zh", "hans"): return "zh-cn"
        case ("zh", "hant"): return "zh-tw"
        default: return nil
        }
    }

    private static let languageAliases = [
        "iw": "he",
        "in": "id",
        "no": "nb",
    ]

    static let defaultLocale = "en"

    /// The locales the editor ships translations for.
    ///
    /// Mirrors `supported-locales.json`, which the JS build emits from
    /// `src/translations/`. Hardcoded rather than read from the resource bundle
    /// because this whole type is temporary scaffolding — see the type-level
    /// note. Duplicating the list here keeps the eventual deletion to a single
    /// file, with no library API added and then removed.
    static let supportedLocales: Set<String> = [
        "ar", "bg", "bo", "ca", "cs", "cy", "da", "de", "el",
        "en-au", "en-ca", "en-gb", "en-nz", "en-za",
        "es", "es-ar", "es-cl", "es-cr", "fa", "fr", "gl", "he", "hr", "hu",
        "id", "is", "it", "ja", "ka", "ko", "nb", "nl", "nl-be", "pl",
        "pt", "pt-br", "ro", "ru", "sk", "sq", "sr", "sv", "th", "tr",
        "uk", "ur", "vi", "zh-cn", "zh-tw",
    ]
}
