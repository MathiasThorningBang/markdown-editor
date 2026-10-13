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
                    SidebarHeader(title: "Drafts", count: untitledDocs.count)
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
                    SidebarHeader(title: project.name, count: project.files.count, folder: project.folderURL)
                    .contextMenu {
                        Button("Copy Path") {
                            AppModel.shared.copyPath(project.folderURL)
                        }
                        Button("Remove from Sidebar") {
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
/// Projects show where their folder lives on a second, gray line.
private struct SidebarHeader: View {
    let title: String
    let count: Int
    var folder: URL? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NMColors.secondaryForeground)
                if let folder {
                    Text(Self.parentLabel(folder))
                        .font(.system(size: 12))
                        .foregroundStyle(NMColors.mutedForeground)
                }
            }
            .lineLimit(1)
            .help(folder?.path ?? "")
            Spacer()
            Text("\(count)")
                .font(.system(size: 12))
                .foregroundStyle(NMColors.secondaryForeground)
                .padding(.trailing, 10)
        }
        .contentShape(Rectangle())
    }

    /// The folder's parent with ~ for home, cut at whole folders:
    /// "~/Desktop/work" in full, deeper ones as their two nearest folders ("…/Intern/Prod").
    static func parentLabel(_ folder: URL) -> String {
        var parts = folder.deletingLastPathComponent().pathComponents
        let home = FileManager.default.homeDirectoryForCurrentUser.pathComponents
        if parts.starts(with: home) {
            parts = ["~"] + parts.dropFirst(home.count)
        } else {
            parts[0] = ""  // the leading "/" component; joining puts the slash back
        }
        let label = parts.count > 3
            ? "…/" + parts.suffix(2).joined(separator: "/")
            : parts.joined(separator: "/")
        return label.isEmpty ? "/" : label
    }
}

/// File name without its extension, after a tag in the file type's color.
private struct SidebarRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    let url: URL?
    let document: OpenDocument?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                FileTypeTag(ext: ext)
                Text(baseName)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(NMColors.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let document {
                    OpenDot(document: document, color: NMColors.fileType(ext))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let url {
                Button("Copy Path") { AppModel.shared.copyPath(url) }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                // Neutral gray, not the accent: the colored tags need the contrast.
                .fill(isActive ? NMColors.foreground.opacity(colorScheme == .dark ? 0.11 : 0.09) : .clear)
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
    }

    /// Drafts have no URL and are markdown.
    private var ext: String { url?.pathExtension.lowercased() ?? "md" }

    private var baseName: String {
        url.map { $0.deletingPathExtension().lastPathComponent } ?? name
    }
}

private struct FileTypeTag: View {
    let ext: String

    var body: some View {
        let color = NMColors.fileType(ext)
        Text(ext.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 58, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
    }
}

/// Dot = file is open, in the file type's color. Unsaved changes only last until
/// autosave (700 ms), so they get no color of their own.
private struct OpenDot: View {
    @ObservedObject var document: OpenDocument
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .accessibilityLabel(document.isDirty ? "Unsaved" : "Open")
    }
}
