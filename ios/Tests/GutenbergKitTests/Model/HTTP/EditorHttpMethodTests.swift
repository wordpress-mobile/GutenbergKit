import Testing

@testable import GutenbergKit

// MARK: - EditorHttpMethod Tests

@Suite
struct EditorHttpMethodTests {

  @Test("Raw values are correct")
  func rawValuesAreCorrect() {
    #expect(EditorHttpMethod.GET.rawValue == "GET")
    #expect(EditorHttpMethod.POST.rawValue == "POST")
    #expect(EditorHttpMethod.PUT.rawValue == "PUT")
    #expect(EditorHttpMethod.DELETE.rawValue == "DELETE")
    #expect(EditorHttpMethod.OPTIONS.rawValue == "OPTIONS")
  }

  @Test("All HTTP methods are defined")
  func allHttpMethodsAreDefined() {
    #expect(EditorHttpMethod.allCases == [.GET, .POST, .PUT, .DELETE, .OPTIONS])
  }
}
