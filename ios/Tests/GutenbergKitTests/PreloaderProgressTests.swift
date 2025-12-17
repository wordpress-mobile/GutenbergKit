import Testing

@testable import GutenbergKit

struct EditorProgressTests {

  @Test func `reports zero when there are no completed items`() {
    #expect(EditorProgress(completed: 0, total: 5).fractionCompleted == 0)
  }

  @Test func `reports zero when there are no total items`() {
    #expect(EditorProgress(completed: 5, total: 0).fractionCompleted == 0)
  }

  @Test func `reports the correct percentage when there are both completed and total items`() {
    #expect(EditorProgress(completed: 5, total: 5).fractionCompleted == 1.0)
  }

  @Test func `reports a maximum of 1.0 when there are more completed items than total items`() {
    #expect(EditorProgress(completed: 10, total: 5).fractionCompleted == 1.0)
  }
}
