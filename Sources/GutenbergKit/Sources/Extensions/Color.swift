import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

extension Color {
    static var separator: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #elseif canImport(AppKit)
        Color(nsColor: .separatorColor)
        #endif
    }

    #if canImport(UIKit)
    func from(color: UIColor) -> Color {
        Color(uiColor: color)
    }
    #endif

    #if canImport(AppKit)
    func from(color: NSColor) -> Color {
        Color(nsColor: color)
    }
    #endif
}
