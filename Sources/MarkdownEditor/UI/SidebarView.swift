import SwiftUI

/// The project sidebar: one collapsible group per opened folder, flat list of
/// its .md files. Replaces the tab bar — rows show open state (dot) and the
/// active file.
struct SidebarView: View {
    @ObservedObject var session: SessionModel

    var body: some View {
        List {
            if !untitledDocs.isEmpty {
                Section("Kladder") {
                    ForEach(untitledDocs) { doc in
                        SidebarRow(
                            name: doc.displayName,
                            document: doc,
                            isActive: doc === session.activeDoc
                        ) {
                            session.activeDoc?.flush()
                            session.activate(doc)
                        }
                    }
                }
            }
            ForEach(session.projects) { project in
                Section {
                    ForEach(project.files) { file in
                        SidebarRow(
                            name: file.name,
                            document: session.document(for: file.url),
                            isActive: session.document(for: file.url) === session.activeDoc
                                && session.activeDoc != nil
                        ) {
                            session.select(file.url)
                        }
                    }
                } header: {
                    HStack {
                        Text(project.name)
                        Spacer()
                        Text("\(project.files.count)")
                            .foregroundStyle(NMColors.mutedForeground)
                            .padding(.trailing, 10)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Fjern fra sidebar") {
                            session.removeProject(project.folderURL)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var untitledDocs: [OpenDocument] {
        session.openDocs.filter { $0.url == nil }
    }
}

private struct SidebarRow: View {
    let name: String
    let document: OpenDocument?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 13))
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
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.primary.opacity(0.12) : .clear)
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
    }
}

/// Dot = file is open; NM primary while it has unsaved changes (autosave pending).
private struct OpenDot: View {
    @ObservedObject var document: OpenDocument

    var body: some View {
        Circle()
            .fill(document.isDirty ? NMColors.primary : NMColors.mutedForeground)
            .frame(width: 6, height: 6)
    }
}
