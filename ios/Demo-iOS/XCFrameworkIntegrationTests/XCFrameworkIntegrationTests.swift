import GutenbergKit
import Testing

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

  @MainActor
  @Test func `implicit test for CSS loading from XCFramework bundle`() async {
    // Would like to use the following:
    //
    //    #expect(processExitsWith: .success) {
    //      _ = HTMLPreviewManager()
    //    }
    //
    // But it's not possible because these tests and the library target iOS, on which the API is unavailalable.
    //
    // See:
    //
    // - https://github.com/swiftlang/swift-evolution/blob/d2111b0f8e725ffa68d124e9570cccb20bde194c/proposals/testing/0008-exit-tests.md#:~:text=If%20a%20platform%20does%20not%20support%20exit%20tests%20(generally%20because%20it%20does%20not%20support%20spawning%20or%20awaiting%20child%20processes)%2C%20then%20we%20define%20SWT_NO_EXIT_TESTS%20when%20we%20build%20it.
    // - https://github.com/swiftlang/swift-testing/pull/324/files#diff-d8ec9e3f3ab018bd21f22d4e11152b4d3cc981bc509652525df761a4e4295d2eR25-R27
    //
    // So, we just init the object and trust that if the assertion below runs, there was no crash
    _ = HTMLPreviewManager()
    #expect(true, "Placeholder expectation after code that would crash if bundle read failed.")
  }
}
