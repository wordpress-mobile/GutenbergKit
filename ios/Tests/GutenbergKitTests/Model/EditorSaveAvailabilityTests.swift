import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct EditorSaveAvailabilityTests {

    @Test("Decodes the onEditorSaveAvailabilityChanged message body")
    func decodesMessageBody() throws {
        let json = #"{"isSaveable":true,"isSavingLocked":true}"#

        let availability = try JSONDecoder().decode(EditorSaveAvailability.self, from: Data(json.utf8))

        #expect(availability == EditorSaveAvailability(isSaveable: true, isSavingLocked: true))
    }
}
