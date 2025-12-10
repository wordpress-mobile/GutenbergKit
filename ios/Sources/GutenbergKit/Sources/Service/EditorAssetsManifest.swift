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

    /// Checks if a script handle should be excluded (bundled in GutenbergKit)
    private static func shouldExcludeScript(_ handle: String) -> Bool {
        handle.hasPrefix("wp-") || bundledScriptHandles.contains(handle)
    }

    /// Checks if a style handle should be excluded (bundled in GutenbergKit)
    private static func shouldExcludeStyle(_ handle: String) -> Bool {
        handle.hasPrefix("wp-")
    }

    /// Extracts all asset URLs from scripts and styles for caching
    /// Excludes bundled assets that are already part of GutenbergKit
    func parseAssetLinks(defaultScheme: String? = nil) -> [String] {
        var assetLinks: [String] = []

        // Extract script URLs (only if src is a valid URL string, not false)
        // Exclude bundled scripts (wp-* and other bundled handles)
        for (handle, script) in scripts {
            if Self.shouldExcludeScript(handle) {
                continue
            }
            if let src = script.src?.urlString {
                assetLinks.append(Self.resolveAssetLink(src, defaultScheme: defaultScheme))
            }
        }

        // Extract style URLs (only if src is a valid URL string, not false)
        // Exclude bundled styles (wp-*)
        for (handle, style) in styles {
            if Self.shouldExcludeStyle(handle) {
                continue
            }
            if let src = style.src?.urlString {
                assetLinks.append(Self.resolveAssetLink(src, defaultScheme: defaultScheme))
            }
        }

        return assetLinks
    }

    /// Transforms asset URLs to use the cache scheme handler and returns JSON for the editor
    /// Excludes bundled assets that are already part of GutenbergKit
    func renderForEditor(defaultScheme: String?) -> Data {
        var rendered = self

        // Transform script URLs (only if src is a valid URL string, not false)
        // Exclude bundled scripts (wp-* and other bundled handles)
        var transformedScripts: [String: ScriptAsset] = [:]
        for (handle, script) in scripts {
            if Self.shouldExcludeScript(handle) {
                continue
            }
            var transformedScript = script
            if let src = script.src?.urlString {
                let resolvedLink = Self.resolveAssetLink(src, defaultScheme: defaultScheme)
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
        // Exclude bundled styles (wp-*)
        var transformedStyles: [String: StyleAsset] = [:]
        for (handle, style) in styles {
            if Self.shouldExcludeStyle(handle) {
                continue
            }
            var transformedStyle = style
            if let src = style.src?.urlString {
                let resolvedLink = Self.resolveAssetLink(src, defaultScheme: defaultScheme)
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
}
