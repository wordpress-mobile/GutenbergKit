import Foundation

#if canImport(OSLog)
import OSLog

extension Logger {
    static let gbkit = Logger(subsystem: "org.wordpress.gutenberg", category: "all")
}
#endif
