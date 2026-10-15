import AVFoundation
import SwiftUI

/// Settings as a page in the editor canvas (⌘, or the gear in the
/// toolbar). Selecting a file in the sidebar closes it again.
struct SettingsView: View {
    @ObservedObject var theme = ThemeSettings.shared
    @ObservedObject var reader = ReadAloud.shared
    #if Kokoro
    @ObservedObject var kokoro = ModelDownload.kokoro
    @ObservedObject var plapre = ModelDownload.plapre
    #endif
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Appearance")
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
                    .help("Close settings (Esc)")
                    .accessibilityLabel("Close settings")
                }
                .padding(.bottom, 40)

                Text("Visual style")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.bottom, 12)

                SettingsCard {
                    SettingsRow("Mode") {
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
                    SettingsRow("Accent color") {
                        HStack(spacing: 8) {
                            ForEach(AccentPreset.all) { preset in
                                Swatch(
                                    color: Color(hex: preset.hex),
                                    isSelected: preset.hex == theme.accentHex
                                ) {
                                    theme.accentHex = preset.hex
                                }
                                .help(preset.name)
                                .accessibilityLabel(preset.name)
                                .accessibilityAddTraits(preset.hex == theme.accentHex ? .isSelected : [])
                            }
                            HexChip(theme: theme)
                                .padding(.leading, 6)
                        }
                    }
                }
                .padding(.bottom, 16)

                SettingsCard {
                    SettingsRow("Headings") {
                        FontPicker(selection: $theme.headingFont, role: .text)
                    }
                    Divider()
                    SettingsRow("Body text") {
                        FontPicker(selection: $theme.bodyFont, role: .text)
                    }
                    Divider()
                    SettingsRow("Code") {
                        FontPicker(selection: $theme.codeFont, role: .code)
                    }
                }

                HStack {
                    Spacer()
                    Button("Reset to defaults") {
                        theme.resetToDefaults()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(NMColors.secondaryForeground)
                }
                .padding(.top, 20)

                Text("Read aloud")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 32)
                    .padding(.bottom, 12)

                SettingsCard {
                    #if Kokoro
                    SettingsRow("English voices") {
                        ModelStatus(download: kokoro, size: "326 MB", help: "Kokoro: George and Daniel, natural British voices that run on this Mac")
                    }
                    Divider()
                    SettingsRow("Danish voices") {
                        ModelStatus(download: plapre, size: "790 MB", help: "Plapre Turbo by syv.ai (MIT): Mic and Nic, Danish voices that run on this Mac")
                    }
                    Divider()
                    #endif
                    SettingsRow("English voice") {
                        VoicePicker(
                            selection: $reader.voiceID, section: "Kokoro", prefix: "kokoro:", voices: kokoroVoices,
                            automatic: kokoroVoices.first?.1 ?? ReadAloud.systemVoice(for: "en")?.name
                        )
                    }
                    Divider()
                    SettingsRow("Danish voice") {
                        VoicePicker(
                            selection: $reader.danishVoiceID, section: "Plapre", prefix: "plapre:", voices: plapreVoices,
                            automatic: plapreVoices.first?.1 ?? ReadAloud.systemVoice(for: "da")?.name
                        )
                    }
                    Divider()
                    SettingsRow("Speed") {
                        HStack(spacing: 10) {
                            Slider(value: $reader.speed, in: 0.6...1.6, step: 0.05)
                                .frame(width: 180)
                                .accessibilityLabel("Speed")
                            Text(String(format: "%.2f×", reader.speed))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(NMColors.secondaryForeground)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    Divider()
                    SettingsRow("Sample") {
                        if reader.state == .idle {
                            HStack(spacing: 8) {
                                Button("English") { playSample("Good evening. Your research is ready whenever you are.") }
                                Button("Danish") { playSample("Godaften. Din research er klar, når du er.") }
                            }
                        } else {
                            Button("Stop") { reader.stop() }
                        }
                    }
                }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(NMColors.foreground)
    }

    private func playSample(_ text: String) {
        reader.onSentence = nil
        reader.start(text)
    }

    /// Kokoro's voices once built in and downloaded.
    private var kokoroVoices: [(String, String)] {
        #if Kokoro
        kokoro.isInstalled ? Kokoro.voices : []
        #else
        []
        #endif
    }

    /// Plapre's voices once built in and downloaded.
    private var plapreVoices: [(String, String)] {
        #if Kokoro
        plapre.isInstalled ? Plapre.voices : []
        #else
        []
        #endif
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
            ColorPicker("Choose color", selection: theme.accentColorBinding, supportsOpacity: false)
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
        .help("Pick your own color")
    }
}

#if Kokoro
/// Download button, progress, or "Installed" for a voice model.
private struct ModelStatus: View {
    @ObservedObject var download: ModelDownload
    let size: String
    let help: String

    var body: some View {
        if download.isInstalled {
            Text("Installed")
                .font(.system(size: 13))
                .foregroundStyle(NMColors.secondaryForeground)
        } else if let progress = download.progress {
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(width: 180)
                Text("\(Int(progress * 100)) %")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(NMColors.secondaryForeground)
                    .frame(width: 44, alignment: .trailing)
            }
        } else {
            HStack(spacing: 10) {
                if let error = download.error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(NMColors.secondaryForeground)
                        .lineLimit(1)
                        .help(error)
                }
                Button("Download (\(size))") { download.start() }
                    .help(help)
            }
        }
    }
}

#endif

/// "Automatic", then a model's voices once downloaded.
private struct VoicePicker: View {
    @Binding var selection: String
    let section: String
    /// Marks the model in the stored selection, like "kokoro:".
    let prefix: String
    /// Voice id and display name; empty until downloaded.
    let voices: [(String, String)]
    /// Name of the voice Automatic reads with.
    let automatic: String?

    var body: some View {
        Picker("Voice", selection: $selection) {
            Text("Automatic (\(automatic ?? "system voice"))").tag("")
            if !voices.isEmpty {
                Section(section) {
                    ForEach(voices, id: \.0) { voice, name in
                        Text(name).tag(prefix + voice)
                    }
                }
            } else if selection.hasPrefix(prefix) {
                Text("\(section) (not downloaded)").tag(selection)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
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
        Picker("Font", selection: $selection) {
            ForEach(curated) { font in
                Text(font.name).font(font.previewFont).tag(font.family)
            }
            // A saved font that has since been uninstalled still shows as selected.
            if !curated.contains(where: { $0.family == selection })
                && !installed.contains(where: { $0.family == selection }) {
                Text(selection).tag(selection)
            }
            Section("Other fonts") {
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
