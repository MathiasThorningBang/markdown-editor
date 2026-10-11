import AppKit
import SwiftUI

/// NM design tokens mirrored from editor.html's :root (light) and its
/// prefers-color-scheme: dark block — keep the two in sync.
enum NMColors {
    static let background = Color(light: 0xFFFFFF, dark: 0x0A0A0A)
    static let foreground = Color(light: 0x171717, dark: 0xFAFAFA)
    static let mutedForeground = Color(light: 0xA3A3A3, dark: 0x737373)
    static let secondaryForeground = Color(light: 0x525252, dark: 0xA3A3A3)
    static let border = Color(light: 0xE5E5E5, dark: 0x262626)
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Lyst"
        case .dark: "Mørkt"
        }
    }
}

/// Curated accent colors; each reads on both the light and dark background.
struct AccentPreset: Identifiable {
    let name: String
    let hex: UInt32
    var id: UInt32 { hex }

    static let nmRed: UInt32 = 0xDF475C

    static let all = [
        AccentPreset(name: "Rød", hex: nmRed),
        AccentPreset(name: "Orange", hex: 0xE07A2E),
        AccentPreset(name: "Grøn", hex: 0x2F9E6B),
        AccentPreset(name: "Petrol", hex: 0x1F8A8A),
        AccentPreset(name: "Blå", hex: 0x2E7AB5),
        AccentPreset(name: "Lilla", hex: 0x7C5CD6),
    ]
}

/// User-chosen appearance and accent, persisted in UserDefaults. The accent
/// replaces NM primary everywhere: sidebar, editor web views, system controls.
@MainActor
final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()

    @Published var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    @Published var accentHex: UInt32 {
        didSet { UserDefaults.standard.set(Int(accentHex), forKey: "accentHex") }
    }

    var accent: Color { Color(hex: accentHex) }

    /// CSS form for the editor web views, e.g. "#df475c".
    var accentCSS: String { String(format: "#%06x", accentHex) }

    private init() {
        let defaults = UserDefaults.standard
        appearance = defaults.string(forKey: "appearance").flatMap(AppearanceMode.init) ?? .system
        accentHex = (defaults.object(forKey: "accentHex") as? Int).map(UInt32.init) ?? AccentPreset.nmRed
    }

    func applyAppearance() {
        NSApplication.shared.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Binding for SwiftUI's ColorPicker (free choice beyond the presets).
    var accentColorBinding: Binding<Color> {
        Binding(
            get: { self.accent },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let r = UInt32((rgb.redComponent * 255).rounded())
                let g = UInt32((rgb.greenComponent * 255).rounded())
                let b = UInt32((rgb.blueComponent * 255).rounded())
                self.accentHex = (r << 16) | (g << 8) | b
            }
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Resolves per appearance, so explicit light/dark overrides apply too.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}
