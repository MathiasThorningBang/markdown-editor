import SwiftUI

/// NM design tokens mirrored from editor.html's :root — keep the two in sync.
enum NMColors {
    static let primary = Color(hex: 0xDF475C)
    static let mutedForeground = Color(hex: 0xA3A3A3)
    static let secondaryForeground = Color(hex: 0x525252)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
