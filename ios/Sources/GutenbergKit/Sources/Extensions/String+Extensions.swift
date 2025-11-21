import Foundation
import CryptoKit

extension String {
    /// Calculates SHA1 from the given string and returns its hex representation.
      ///
      /// ```swift
      /// print("http://test.com".sha1)
      /// // prints "50334ee0b51600df6397ce93ceed4728c37fee4e"
      /// ```
      var sha1: String {
          guard let input = self.data(using: .utf8) else {
              assertionFailure("Failed to generate data for the string")
              return "" // The conversion to .utf8 should never fail
          }
          let digest = Insecure.SHA1.hash(data: input)
          var output = ""
          for byte in digest {
              output.append(String(format: "%02x", byte))
          }
          return output
      }
}
