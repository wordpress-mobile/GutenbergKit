import Foundation

extension String {
    /// Converts a string (such as a URL) into a safe directory name by removing illegal filesystem characters
    ///
    /// This method filters out characters that are not allowed in directory names across different filesystems,
    /// including: `/`, `:`, `\`, `?`, `%`, `*`, `|`, `"`, `<`, `>`, newlines, and control characters.
    ///
    /// Example:
    /// ```swift
    /// let url = "https://example.com/path?query=1"
    /// let safeName = url.safeFilename
    /// // Result: "https---example.com-path-query-1"
    /// ```
    var safeFilename: String {
        // Define illegal characters for directory names
        let illegalChars = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)

        // Remove scheme and other URL components we don't want
        var cleaned = self
        if var urlComponents = URLComponents(string: self) {
            urlComponents.scheme = nil
            urlComponents.query = nil
            urlComponents.fragment = nil
            if let url = urlComponents.url?.absoluteString {
                cleaned = url
            }
        }

        // Trim and replace illegal characters with dashes
        return cleaned
            .trimmingCharacters(in: illegalChars)
            .components(separatedBy: illegalChars)
            .joined(separator: "-")
    }
}
