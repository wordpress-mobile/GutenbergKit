import Foundation

// MARK: - v2.1 Asset Types

/// Represents a script asset from the v2.1 editor assets endpoint
struct ScriptAsset: Codable {
    let src: String?
    let deps: [String]?
    let version: StringOrBool?
    let inFooter: Bool?

    enum CodingKeys: String, CodingKey {
        case src
        case deps
        case version
        case inFooter = "in_footer"
    }
}

/// Represents a style asset from the v2.1 editor assets endpoint
struct StyleAsset: Codable {
    let src: String?
    let deps: [String]?
    let version: StringOrBool?
    let media: String?
}

/// Represents inline assets (before/after) from the v2.1 editor assets endpoint
struct InlineAssets: Codable {
    let before: [String: String]?
    let after: [String: String]?

    init(before: [String: String]? = nil, after: [String: String]? = nil) {
        self.before = before
        self.after = after
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

// MARK: - Main Manifest

/// Represents the v2.1 editor assets manifest response
struct EditorAssetsManifest: Codable {
    var scripts: [String: ScriptAsset]
    var styles: [String: StyleAsset]
    var inlineScripts: InlineAssets
    var inlineStyles: InlineAssets

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
        inlineScripts = try container.decodeIfPresent(InlineAssets.self, forKey: .inlineScripts) ?? InlineAssets()
        inlineStyles = try container.decodeIfPresent(InlineAssets.self, forKey: .inlineStyles) ?? InlineAssets()
    }

    /// Extracts all asset URLs from scripts and styles for caching
    func parseAssetLinks(defaultScheme: String? = nil) -> [String] {
        var assetLinks: [String] = []

        // Extract script URLs
        for (_, script) in scripts {
            if let src = script.src, !src.isEmpty {
                assetLinks.append(Self.resolveAssetLink(src, defaultScheme: defaultScheme))
            }
        }

        // Extract style URLs
        for (_, style) in styles {
            if let src = style.src, !src.isEmpty {
                assetLinks.append(Self.resolveAssetLink(src, defaultScheme: defaultScheme))
            }
        }

        return assetLinks
    }

    /// Transforms asset URLs to use the cache scheme handler and returns JSON for the editor
    func renderForEditor(defaultScheme: String?) -> Data {
        var rendered = self

        // Transform script URLs
        var transformedScripts: [String: ScriptAsset] = [:]
        for (handle, script) in scripts {
            var transformedScript = script
            if let src = script.src, !src.isEmpty {
                let resolvedLink = Self.resolveAssetLink(src, defaultScheme: defaultScheme)
                #if canImport(UIKit)
                let cachedLink = CachedAssetSchemeHandler.cachedURL(forWebLink: resolvedLink) ?? resolvedLink
                #else
                let cachedLink = resolvedLink
                #endif
                transformedScript = ScriptAsset(
                    src: cachedLink,
                    deps: script.deps,
                    version: script.version,
                    inFooter: script.inFooter
                )
            }
            transformedScripts[handle] = transformedScript
        }
        rendered.scripts = transformedScripts

        // Transform style URLs
        var transformedStyles: [String: StyleAsset] = [:]
        for (handle, style) in styles {
            var transformedStyle = style
            if let src = style.src, !src.isEmpty {
                let resolvedLink = Self.resolveAssetLink(src, defaultScheme: defaultScheme)
                #if canImport(UIKit)
                let cachedLink = CachedAssetSchemeHandler.cachedURL(forWebLink: resolvedLink) ?? resolvedLink
                #else
                let cachedLink = resolvedLink
                #endif
                transformedStyle = StyleAsset(
                    src: cachedLink,
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
