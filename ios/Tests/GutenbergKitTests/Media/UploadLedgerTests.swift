import Foundation
import Testing

@testable import GutenbergKit

/// `begin` and `abandon` must settle each upload once. If both could win, the old server
/// would send an upload the page is also sending again, and WordPress would get it twice.
@Suite("UploadLedger")
struct UploadLedgerTests {

    @Test("an upload the server began can't be cleared for a retry")
    func begunCannotBeAbandoned() {
        let ledger = UploadLedger()
        #expect(ledger.begin("upload"))
        #expect(!ledger.abandon("upload"))
    }

    @Test("an upload the page gave up on can't be begun")
    func abandonedCannotBegin() {
        let ledger = UploadLedger()
        #expect(ledger.abandon("upload"))
        #expect(!ledger.begin("upload"))
    }

    @Test("an upload without an ID always begins")
    func uploadWithoutAnIDBegins() {
        let ledger = UploadLedger()
        #expect(ledger.begin(nil))
        #expect(ledger.begin(nil))
    }

    @Test("each upload is settled on its own")
    func uploadsAreIndependent() {
        let ledger = UploadLedger()
        #expect(ledger.begin("sent"))
        #expect(ledger.abandon("unsent"))
        #expect(!ledger.abandon("sent"))
        #expect(!ledger.begin("unsent"))
    }

    /// The race this exists for: the server begins an upload on its connection's task while
    /// the page's check abandons it on the main actor. Whichever runs first, exactly one wins.
    @Test("exactly one of begin and abandon wins, whichever runs first")
    func beginAndAbandonRace() async {
        let ledger = UploadLedger()
        let ids = (0..<500).map { "upload-\($0)" }

        let outcomes = await withTaskGroup(of: (String, Bool, Bool).self) { group in
            for id in ids {
                group.addTask {
                    async let began = Task.detached { ledger.begin(id) }.value
                    async let abandoned = Task.detached { ledger.abandon(id) }.value
                    return await (id, began, abandoned)
                }
            }
            return await group.reduce(into: [(String, Bool, Bool)]()) { $0.append($1) }
        }

        let bothOrNeither = outcomes.filter { $0.1 == $0.2 }.map(\.0)
        #expect(bothOrNeither.isEmpty, "begin and abandon agreed on \(bothOrNeither.prefix(5))")
    }
}
