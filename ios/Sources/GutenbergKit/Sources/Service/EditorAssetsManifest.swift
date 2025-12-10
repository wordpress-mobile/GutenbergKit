import Foundation

// MARK: - v2.1 Asset Types

/// Represents a script asset from the v2.1 editor assets endpoint
struct ScriptAsset: Codable {
    let src: StringOrFalse?
    let deps: [String]?
    let version: StringOrBool?
    let inFooter: Bool?

    enum CodingKeys: String, CodingKey {
        case src
        case deps
        case version
        case inFooter = "in_footer"
    }

    init(src: StringOrFalse?, deps: [String]?, version: StringOrBool?, inFooter: Bool?) {
        self.src = src
        self.deps = deps
        self.version = version
        self.inFooter = inFooter
    }
}

/// Represents a style asset from the v2.1 editor assets endpoint
struct StyleAsset: Codable {
    let src: StringOrFalse?
    let deps: [String]?
    let version: StringOrBool?
    let media: String?

    init(src: StringOrFalse?, deps: [String]?, version: StringOrBool?, media: String?) {
        self.src = src
        self.deps = deps
        self.version = version
        self.media = media
    }
}

/// Represents inline script assets (before/after) from the v2.1 editor assets endpoint
/// Values are strings (inline script content)
/// Note: PHP encodes empty arrays as [] instead of {}, so we need custom decoding
struct InlineScriptAssets: Codable {
    let before: [String: String]?
    let after: [String: String]?

    init(before: [String: String]? = nil, after: [String: String]? = nil) {
        self.before = before
        self.after = after
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // PHP encodes empty arrays as [] instead of {}, so we try to decode as dictionary
        // and fall back to nil if it's an empty array
        before = Self.decodeDictionaryOrNil(from: container, forKey: .before)
        after = Self.decodeDictionaryOrNil(from: container, forKey: .after)
    }

    private static func decodeDictionaryOrNil(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [String: String]? {
        // Try to decode as dictionary first
        if let dict = try? container.decodeIfPresent([String: String].self, forKey: key) {
            return dict
        }
        // If that fails (e.g., it's an empty array []), return nil
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case before
        case after
    }
}

/// Represents inline style assets (before/after) from the v2.1 editor assets endpoint
/// Values are arrays of strings (multiple inline style declarations per handle)
/// Note: PHP encodes empty arrays as [] instead of {}, so we need custom decoding
struct InlineStyleAssets: Codable {
    let before: [String: [String]]?
    let after: [String: [String]]?

    init(before: [String: [String]]? = nil, after: [String: [String]]? = nil) {
        self.before = before
        self.after = after
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // PHP encodes empty arrays as [] instead of {}, so we try to decode as dictionary
        // and fall back to nil if it's an empty array
        before = Self.decodeDictionaryOrNil(from: container, forKey: .before)
        after = Self.decodeDictionaryOrNil(from: container, forKey: .after)
    }

    private static func decodeDictionaryOrNil(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [String: [String]]? {
        // Try to decode as dictionary first
        if let dict = try? container.decodeIfPresent([String: [String]].self, forKey: key) {
            return dict
        }
        // If that fails (e.g., it's an empty array []), return nil
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case before
        case after
    }
}

/// Helper type to handle version field which can be string, bool, or null
enum StringOrBool: Codable {
    case string(String)
    case bool(Bool)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            throw DecodingError.typeMismatch(
                StringOrBool.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String, Bool, or Int")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .bool: return nil
        }
    }
}

/// Helper type to handle src field which can be a URL string or false (for alias scripts without external source)
enum StringOrFalse: Codable {
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else {
            throw DecodingError.typeMismatch(
                StringOrFalse.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Bool")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }

    /// Returns the URL string if present, nil if src is false or empty
    var urlString: String? {
        switch self {
        case .string(let value): return value.isEmpty ? nil : value
        case .bool: return nil
        }
    }
}

// MARK: - Main Manifest

/// Represents the v2.1 editor assets manifest response
struct EditorAssetsManifest: Codable {
    var scripts: [String: ScriptAsset]
    var styles: [String: StyleAsset]
    var inlineScripts: InlineScriptAssets
    var inlineStyles: InlineStyleAssets

    enum CodingKeys: String, CodingKey {
        case scripts
        case styles
        case inlineScripts = "inline_scripts"
        case inlineStyles = "inline_styles"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scripts = try container.decode([String: ScriptAsset].self, forKey: .scripts)
        styles = try container.decode([String: StyleAsset].self, forKey: .styles)
        inlineScripts = try container.decodeIfPresent(InlineScriptAssets.self, forKey: .inlineScripts) ?? InlineScriptAssets()
        inlineStyles = try container.decodeIfPresent(InlineStyleAssets.self, forKey: .inlineStyles) ?? InlineStyleAssets()
    }

    /// Handles for scripts that are bundled in GutenbergKit and should be excluded
    private static let bundledScriptHandles: Set<String> = [
        "react", "react-dom", "react-jsx-runtime",
        "lodash", "jquery", "jquery-core", "jquery-migrate",
        "moment", "regenerator-runtime"
    ]

    /// Checks if an asset URL points to WordPress core (wp-includes directory)
    private static func isWordPressCoreAsset(_ src: String?) -> Bool {
        guard let src = src else { return false }
        return src.contains("/wp-includes/")
    }

    /// Checks if a script should be excluded (bundled in GutenbergKit or WordPress core)
    private static func shouldExcludeScript(_ handle: String, src: String?) -> Bool {
        handle.hasPrefix("wp-") || bundledScriptHandles.contains(handle) || isWordPressCoreAsset(src)
    }

    /// Checks if a style should be excluded (bundled in GutenbergKit or WordPress core)
    private static func shouldExcludeStyle(_ handle: String, src: String?) -> Bool {
        handle.hasPrefix("wp-") || isWordPressCoreAsset(src)
    }

    /// Extracts all asset URLs from scripts and styles for caching
    /// Excludes bundled assets that are already part of GutenbergKit
    /// URLs include version query parameter to match what the editor will request
    func parseAssetLinks(defaultScheme: String? = nil) -> [String] {
        var assetLinks: [String] = []

        // Extract script URLs (only if src is a valid URL string, not false)
        // Exclude bundled scripts (wp-*, bundled handles, and wp-includes assets)
        for (handle, script) in scripts {
            let src = script.src?.urlString
            if Self.shouldExcludeScript(handle, src: src) {
                continue
            }
            if let src {
                let versionedSrc = Self.buildVersionedURL(src, version: script.version)
                assetLinks.append(Self.resolveAssetLink(versionedSrc, defaultScheme: defaultScheme))
            }
        }

        // Extract style URLs (only if src is a valid URL string, not false)
        // Exclude bundled styles (wp-* and wp-includes assets)
        for (handle, style) in styles {
            let src = style.src?.urlString
            if Self.shouldExcludeStyle(handle, src: src) {
                continue
            }
            if let src {
                let versionedSrc = Self.buildVersionedURL(src, version: style.version)
                assetLinks.append(Self.resolveAssetLink(versionedSrc, defaultScheme: defaultScheme))
            }
        }

        return assetLinks
    }

    /// Transforms asset URLs to use the cache scheme handler and returns JSON for the editor
    /// Excludes bundled assets that are already part of GutenbergKit
    /// URLs include version query parameter to enable proper cache lookup
    func renderForEditor(defaultScheme: String?) -> Data {
        var rendered = self

        // Transform script URLs (only if src is a valid URL string, not false)
        // Exclude bundled scripts (wp-*, bundled handles, and wp-includes assets)
        var transformedScripts: [String: ScriptAsset] = [:]
        for (handle, script) in scripts {
            let src = script.src?.urlString
            if Self.shouldExcludeScript(handle, src: src) {
                continue
            }
            var transformedScript = script
            if let src {
                let versionedSrc = Self.buildVersionedURL(src, version: script.version)
                let resolvedLink = Self.resolveAssetLink(versionedSrc, defaultScheme: defaultScheme)
                #if canImport(UIKit)
                let cachedLink = CachedAssetSchemeHandler.cachedURL(forWebLink: resolvedLink) ?? resolvedLink
                #else
                let cachedLink = resolvedLink
                #endif
                transformedScript = ScriptAsset(
                    src: .string(cachedLink),
                    deps: script.deps,
                    version: script.version,
                    inFooter: script.inFooter
                )
            }
            transformedScripts[handle] = transformedScript
        }
        rendered.scripts = transformedScripts

        // Transform style URLs (only if src is a valid URL string, not false)
        // Exclude bundled styles (wp-* and wp-includes assets)
        var transformedStyles: [String: StyleAsset] = [:]
        for (handle, style) in styles {
            let src = style.src?.urlString
            if Self.shouldExcludeStyle(handle, src: src) {
                continue
            }
            var transformedStyle = style
            if let src {
                let versionedSrc = Self.buildVersionedURL(src, version: style.version)
                let resolvedLink = Self.resolveAssetLink(versionedSrc, defaultScheme: defaultScheme)
                #if canImport(UIKit)
                let cachedLink = CachedAssetSchemeHandler.cachedURL(forWebLink: resolvedLink) ?? resolvedLink
                #else
                let cachedLink = resolvedLink
                #endif
                transformedStyle = StyleAsset(
                    src: .string(cachedLink),
                    deps: style.deps,
                    version: style.version,
                    media: style.media
                )
            }
            transformedStyles[handle] = transformedStyle
        }
        rendered.styles = transformedStyles

        // Encode and return
        do {
            return try JSONEncoder().encode(rendered)
        } catch {
            // Return empty object if encoding fails
            return "{}".data(using: .utf8) ?? Data()
        }
    }

    /// Resolves protocol-relative URLs to absolute URLs
    private static func resolveAssetLink(_ link: String, defaultScheme: String?) -> String {
        if link.starts(with: "//") {
            return "\(defaultScheme ?? "https"):\(link)"
        }
        return link
    }

    /// Builds a URL with version query parameter appended
    /// Matches the behavior of buildVersionedURL in editor-loader.js
    private static func buildVersionedURL(_ src: String, version: StringOrBool?) -> String {
        guard let versionString = version?.stringValue else { return src }
        let separator = src.contains("?") ? "&" : "?"
        return "\(src)\(separator)ver=\(versionString)"
    }
}
