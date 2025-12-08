import Foundation

@testable import GutenbergKit

extension Data {
  init(_ string: String) {
    self = Data(string.utf8)
  }

  static var sample: Data {
    Data(UUID().uuidString.utf8)
  }

  static func forResource(named name: String, withExtension ext: String = "json") throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: ext)!
    return try Data(contentsOf: url)
  }
}
