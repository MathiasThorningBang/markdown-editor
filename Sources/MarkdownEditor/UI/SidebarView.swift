import SwiftUI

/// The project sidebar: one collapsible group per opened folder, flat list of
/// its .md files. Replaces the tab bar — rows show open state (dot) and the
/// active file.
struct SidebarView: View {
    @ObservedObject var session: SessionModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            if !untitledDocs.isEmpty {
                Section {
                    ForEach(untitledDocs) { doc in
                        SidebarRow(
                            name: doc.displayName,
                            url: nil,
                            document: doc,
                            isActive: doc === session.activeDoc
                        ) {
                            session.activeDoc?.flush()
                            session.activate(doc)
                        }
                    }
                } header: {
                    SidebarHeader(title: "Kladder", count: untitledDocs.count)
                }
            }
            ForEach(session.projects) { project in
                Section {
                    ForEach(project.files) { file in
                        SidebarRow(
                            name: file.name,
                            url: file.url,
                            document: session.document(for: file.url),
                            isActive: session.document(for: file.url) === session.activeDoc
                                && session.activeDoc != nil
                        ) {
                            session.select(file.url)
                        }
                    }
                } header: {
                    SidebarHeader(title: project.name, count: project.files.count)
                    .contextMenu {
                        Button("Kopiér sti") {
                            AppModel.shared.copyPath(project.folderURL)
                        }
                        Button("Fjern fra sidebar") {
                            session.removeProject(project.folderURL)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
        .background(colorScheme == .dark ? NMColors.darkSidebar : .clear)
    }

    private var untitledDocs: [OpenDocument] {
        session.openDocs.filter { $0.url == nil }
    }
}

/// Section header at 12px (the system sidebar default is 11pt, below the NM minimum).
private struct SidebarHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NMColors.secondaryForeground)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12))
                .foregroundStyle(NMColors.mutedForeground)
                .padding(.trailing, 10)
        }
        .contentShape(Rectangle())
    }
}

private struct SidebarRow: View {
    @ObservedObject private var theme = ThemeSettings.shared
    let name: String
    let url: URL?
    let document: OpenDocument?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(NMColors.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let document {
                    OpenDot(document: document)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let url {
                Button("Kopiér sti") { AppModel.shared.copyPath(url) }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? theme.accent.opacity(0.14) : .clear)
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
    }
}

/// Dot = file is open; accent color while it has unsaved changes (autosave pending).
private struct OpenDot: View {
    @ObservedObject var document: OpenDocument
    @ObservedObject private var theme = ThemeSettings.shared

    var body: some View {
        Circle()
            .fill(document.isDirty ? theme.accent : NMColors.mutedForeground)
            .frame(width: 6, height: 6)
    }
}
