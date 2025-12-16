import CryptoKit
import Foundation

// MARK: - FileManager Extensions

extension FileManager {
    /// Checks whether a file exists at the given URL.
    ///
    /// - Parameter url: The file URL to check.
    /// - Returns: `true` if a file exists at the URL, `false` otherwise.
    public func fileExists(at url: URL) -> Bool {
        return self.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Checks whether a directory exists at the given URL.
    ///
    /// - Parameter url: The directory URL to check.
    /// - Returns: `true` if a directory exists at the URL, `false` otherwise.
    ///
    ///   Returns `false` if a file (not a directory) exists at the URL.
    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = true
        let exists = self.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

// MARK: - URL Extensions

extension URL {
    /// Returns the path and query components of the URL as a single string.
    ///
    /// If the URL has a query string, returns the path followed by `?` and the query.
    /// Otherwise, returns just the path.
    ///
    /// Example: For `https://example.com/api/posts?page=1`, returns `/api/posts?page=1`.
    var pathAndQuery: String {
        if let query = self.query(percentEncoded: false) {
            return self.path() + "?" + query
        }

        return self.path(percentEncoded: false)
    }

    /// Appends a raw path string to the URL without percent-encoding.
    ///
    /// This method handles slash normalization between the base URL and the path being appended,
    /// ensuring exactly one slash separates them.
    ///
    /// - Parameter rawPath: The path to append. May or may not start with a slash.
    /// - Returns: A new URL with the path appended.
    func appending(rawPath: String) -> URL {
        let urlString = self.absoluteString

        if urlString.hasSuffix("/") && rawPath.hasPrefix("/") {
            return URL(string: urlString + rawPath.trimmingPrefix("/"))!
        }

        if !urlString.hasSuffix("/") && !rawPath.hasPrefix("/") {
            return URL(string: urlString + "/" + rawPath)!
        }

        return URL(string: urlString + rawPath)!
    }

    func replacing(scheme: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components!.scheme = scheme
        return components!.url!
    }
}

// MARK: - URLRequest Extensions

extension URLRequest {
    /// Creates a URL request with the specified URL and HTTP method.
    ///
    /// - Parameters:
    ///   - url: The URL for the request.
    ///   - method: The HTTP method to use.
    init(method: EditorHttpMethod, url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        self = request
    }
}

// MARK: - Data Extensions

extension Data {
    /// Computes a SHA-256 hash of the data and returns it as a hexadecimal string.
    ///
    /// - Returns: A 64-character lowercase hexadecimal string representing the SHA-256 hash.
    func hash() -> String {
        SHA256.hash(data: self).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - String Extensions

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
