import SwiftUI

/// Indstillinger as a page in the editor canvas (⌘, or the gear in the
/// toolbar). Selecting a file in the sidebar closes it again.
struct SettingsView: View {
    @ObservedObject var theme = ThemeSettings.shared
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Udseende")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.4)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NMColors.secondaryForeground)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Luk indstillinger (Esc)")
                }
                .padding(.bottom, 40)

                Text("Visuel stil")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.bottom, 12)

                SettingsCard {
                    SettingsRow("Tilstand") {
                        HStack(spacing: 12) {
                            ForEach(AppearanceMode.allCases) { mode in
                                ModeThumbnail(
                                    mode: mode,
                                    accent: theme.accent,
                                    isSelected: theme.appearance == mode
                                ) {
                                    theme.appearance = mode
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 16)

                SettingsCard {
                    SettingsRow("Temafarve") {
                        HStack(spacing: 8) {
                            ForEach(AccentPreset.all) { preset in
                                Swatch(
                                    color: Color(hex: preset.hex),
                                    isSelected: preset.hex == theme.accentHex
                                ) {
                                    theme.accentHex = preset.hex
                                }
                                .help(preset.name)
                            }
                            HexChip(theme: theme)
                                .padding(.leading, 6)
                        }
                    }
                }
                .padding(.bottom, 16)

                SettingsCard {
                    SettingsRow("Overskrifter") {
                        FontPicker(selection: $theme.headingFont, role: .text)
                    }
                    Divider()
                    SettingsRow("Brødtekst") {
                        FontPicker(selection: $theme.bodyFont, role: .text)
                    }
                    Divider()
                    SettingsRow("Kode") {
                        FontPicker(selection: $theme.codeFont, role: .code)
                    }
                }

                HStack {
                    Spacer()
                    Button("Nulstil til standard") {
                        theme.resetToDefaults()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(NMColors.mutedForeground)
                }
                .padding(.top, 20)
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(NMColors.foreground)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(NMColors.card)
                    .strokeBorder(NMColors.border, lineWidth: 1)
            )
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 24)
            control
        }
        .padding(.vertical, 14)
    }
}

/// Miniature window in the given mode; System is split light/dark.
private struct ModeThumbnail: View {
    let mode: AppearanceMode
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    switch mode {
                    case .light: MiniWindow(dark: false, accent: accent)
                    case .dark: MiniWindow(dark: true, accent: accent)
                    case .system:
                        MiniWindow(dark: false, accent: accent)
                        MiniWindow(dark: true, accent: accent)
                            .mask(HStack(spacing: 0) { Color.clear; Color.black })
                    }
                }
                .frame(width: 84, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? accent : NMColors.border, lineWidth: isSelected ? 2 : 1)
                )
                Text(mode.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? NMColors.foreground : NMColors.secondaryForeground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MiniWindow: View {
    let dark: Bool
    let accent: Color

    var body: some View {
        let bg = Color(hex: dark ? 0x181818 : 0xFFFFFF)
        let side = Color(hex: dark ? 0x212121 : 0xF5F5F5)
        let line = Color(hex: dark ? 0x3A3A3A : 0xD4D4D4)
        HStack(spacing: 0) {
            side.frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(dark ? Color(hex: 0xFFFFFF) : Color(hex: 0x171717)).frame(width: 30, height: 4)
                Capsule().fill(line).frame(width: 44, height: 3)
                Capsule().fill(line).frame(width: 38, height: 3)
                Capsule().fill(accent).frame(width: 20, height: 3)
            }
            .padding(.leading, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(bg)
        }
    }
}

private struct Swatch: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay(
                    Circle().strokeBorder(isSelected ? color : .clear, lineWidth: 2)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Current accent as "● #DF475C"; clicking opens the system color picker.
private struct HexChip: View {
    @ObservedObject var theme: ThemeSettings

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("Vælg farve", selection: theme.accentColorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 20, height: 20)
            Text(theme.accentCSS.uppercased())
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(NMColors.secondaryForeground)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().strokeBorder(NMColors.border, lineWidth: 1))
        .help("Vælg din egen farve")
    }
}

/// Curated fonts first, then every installed family (fixed-pitch only for code).
private struct FontPicker: View {
    @Binding var selection: String
    let role: FontChoice.Role

    // Scanning installed families is slow-ish; do it once per app run.
    private static let installedText = FontChoice.installed(.text)
    private static let installedCode = FontChoice.installed(.code)

    var body: some View {
        let curated = FontChoice.curated(role)
        let installed = role == .text ? Self.installedText : Self.installedCode
        Picker("Skrifttype", selection: $selection) {
            ForEach(curated) { font in
                Text(font.name).font(font.previewFont).tag(font.family)
            }
            // A saved font that has since been uninstalled still shows as selected.
            if !curated.contains(where: { $0.family == selection })
                && !installed.contains(where: { $0.family == selection }) {
                Text(selection).tag(selection)
            }
            Section("Andre skrifttyper") {
                ForEach(installed) { font in
                    Text(font.name).font(font.previewFont).tag(font.family)
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}
