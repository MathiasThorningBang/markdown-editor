import AppKit
import SwiftUI

/// NM design tokens mirrored from editor.html's :root (light) and its
/// prefers-color-scheme: dark block — keep the two in sync.
enum NMColors {
    static let background = Color(light: 0xFFFFFF, dark: 0x181818)
    static let foreground = Color(light: 0x171717, dark: 0xFFFFFF)
    static let mutedForeground = Color(light: 0xA3A3A3, dark: 0x8A8A8A)
    static let secondaryForeground = Color(light: 0x525252, dark: 0xB4B4B4)
    static let border = Color(light: 0xE5E5E5, dark: 0x2E2E2E)
    static let card = Color(light: 0xFFFFFF, dark: 0x212121)
    /// Solid dark sidebar (Codex style); light mode keeps the system material.
    static let darkSidebar = Color(hex: 0x212121)
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

/// A font the user can pick. `family` is the CSS family name handed to the
/// editor web views — an installed family, or a generic like `ui-serif`.
struct FontChoice: Identifiable, Hashable {
    let name: String
    let family: String
    var id: String { family }

    enum Role { case text, code }

    static let defaultText = "DM Sans"
    static let defaultCode = "Geist Mono"

    /// Shown first in each picker. DM Sans and Geist Mono are bundled with the editor.
    static func curated(_ role: Role) -> [FontChoice] {
        switch role {
        case .text: [
            FontChoice(name: "DM Sans", family: defaultText),
            FontChoice(name: "SF Pro", family: "system-ui"),
            FontChoice(name: "New York", family: "ui-serif"),
            FontChoice(name: "Georgia", family: "Georgia"),
        ]
        case .code: [
            FontChoice(name: "Geist Mono", family: defaultCode),
            FontChoice(name: "SF Mono", family: "ui-monospace"),
            FontChoice(name: "Menlo", family: "Menlo"),
        ]
        }
    }

    /// Everything installed on this Mac; code only lists fixed-pitch families.
    static func installed(_ role: Role) -> [FontChoice] {
        let curatedFamilies = Set(curated(role).map(\.family))
        return NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !curatedFamilies.contains($0) }
            .filter { family in
                guard role == .code else { return true }
                return NSFont(name: family, size: 13)?.isFixedPitch ?? false
            }
            .map { FontChoice(name: $0, family: $0) }
    }

    /// Preview font for the picker; bundled web fonts fall back to the system font.
    var previewFont: Font {
        switch family {
        case "system-ui": .system(size: 13)
        case "ui-serif": .system(size: 13, design: .serif)
        case "ui-monospace": .system(size: 13, design: .monospaced)
        default: .custom(family, size: 13)
        }
    }
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

    @Published var headingFont: String {
        didSet { UserDefaults.standard.set(headingFont, forKey: "headingFont") }
    }

    @Published var bodyFont: String {
        didSet { UserDefaults.standard.set(bodyFont, forKey: "bodyFont") }
    }

    @Published var codeFont: String {
        didSet { UserDefaults.standard.set(codeFont, forKey: "codeFont") }
    }

    var accent: Color { Color(hex: accentHex) }

    /// CSS form for the editor web views, e.g. "#df475c".
    var accentCSS: String { String(format: "#%06x", accentHex) }

    private init() {
        let defaults = UserDefaults.standard
        appearance = defaults.string(forKey: "appearance").flatMap(AppearanceMode.init) ?? .system
        accentHex = (defaults.object(forKey: "accentHex") as? Int).map(UInt32.init) ?? AccentPreset.nmRed
        headingFont = defaults.string(forKey: "headingFont") ?? FontChoice.defaultText
        bodyFont = defaults.string(forKey: "bodyFont") ?? FontChoice.defaultText
        codeFont = defaults.string(forKey: "codeFont") ?? FontChoice.defaultCode
    }

    func resetToDefaults() {
        appearance = .system
        accentHex = AccentPreset.nmRed
        headingFont = FontChoice.defaultText
        bodyFont = FontChoice.defaultText
        codeFont = FontChoice.defaultCode
    }

    /// CSS custom properties for the editor web views.
    var cssVariables: [String: String] {
        func stack(_ family: String, _ fallback: String) -> String {
            // Generic families must stay unquoted; named families are quoted.
            let generics: Set = ["system-ui", "ui-serif", "ui-monospace"]
            let head = generics.contains(family)
                ? family : "'\(family.replacingOccurrences(of: "'", with: "\\'"))'"
            return "\(head), \(fallback)"
        }
        return [
            "--color-primary": accentCSS,
            "--font-heading": stack(headingFont, "system-ui, sans-serif"),
            "--font-body": stack(bodyFont, "system-ui, sans-serif"),
            "--font-mono": stack(codeFont, "ui-monospace, monospace"),
        ]
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
