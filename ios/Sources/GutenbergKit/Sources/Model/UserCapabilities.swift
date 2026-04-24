import Foundation

/// Host-declared user capabilities passed into the editor.
///
/// These are serialized into `window.GBKit.userCapabilities` and used by
/// the JavaScript editor to preseed `@wordpress/core-data`'s `canUser`
/// results, bypassing the cross-origin OPTIONS inference path that cannot
/// read the REST `Allow` header.
public struct UserCapabilities: Sendable, Codable, Hashable {
    /// Whether the user has the `upload_files` WordPress capability.
    public let uploadFiles: Bool

    public init(uploadFiles: Bool) {
        self.uploadFiles = uploadFiles
    }
}
