import Foundation
import os

/// Which uploads the upload server has begun passing on to WordPress, and which the page
/// has given up on.
///
/// This is what lets the page retry an upload it lost without risking a duplicate
/// attachment. When a request to the server fails at the transport layer, the page can't
/// tell a connection that was refused (nothing received the upload) from one cut off after
/// the server had handed the file on (the attachment may already exist). The server can,
/// if every upload carries an ID: an upload the server never *began* can't have reached
/// WordPress.
///
/// ``begin(_:)`` and ``abandon(_:)`` settle each ID once, under one lock, so exactly one of
/// them wins. If the page gives up on an upload the server hasn't begun, the server will
/// refuse to begin it later, and the page's retry is the only copy that reaches WordPress.
///
/// The editor owns the ledger and hands the same one to every server it starts. The
/// question is usually about an upload the *previous* server may have received, so the
/// answer has to outlive the restart.
final class UploadLedger: Sendable {
    private enum Outcome {
        case begun
        case abandoned
    }

    private let outcomes = OSAllocatedUnfairLock<[String: Outcome]>(initialState: [:])

    /// Records that the server is about to pass upload `id` on toward WordPress.
    ///
    /// - Returns: `false` if the page has already given up on the upload, in which case it
    ///   must not be sent. An upload without an ID, from a page that doesn't send them, is
    ///   always allowed.
    func begin(_ id: String?) -> Bool {
        guard let id else { return true }
        return outcomes.withLock { outcomes in
            if outcomes[id] == .abandoned { return false }
            outcomes[id] = .begun
            return true
        }
    }

    /// Records that the page has given up on upload `id`.
    ///
    /// - Returns: `true` if the server never began the upload, so WordPress can't have
    ///   received it and the page may send the file again.
    func abandon(_ id: String) -> Bool {
        outcomes.withLock { outcomes in
            if outcomes[id] == .begun { return false }
            outcomes[id] = .abandoned
            return true
        }
    }
}
