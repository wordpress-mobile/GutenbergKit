import Testing
import GutenbergKit

struct `XCFramework integration test` {

    @Test func `EditorConfigurationBuilder can be used`() {
      #expect(
        EditorConfigurationBuilder()
          .setShouldHideTitle(true)
          .build()
          .shouldHideTitle
        ==
        true
      )
    }
}
