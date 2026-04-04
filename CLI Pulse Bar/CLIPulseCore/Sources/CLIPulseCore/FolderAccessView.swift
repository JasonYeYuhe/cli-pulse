#if os(macOS)
import SwiftUI
import AppKit

/// Settings section for managing folder access permissions.
/// Users grant access to CLI tool credential directories via NSOpenPanel.
public struct FolderAccessView: View {
    @State private var statuses: [(directory: BookmarkManager.KnownDirectory, hasAccess: Bool, isInstalled: Bool)] = []

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.secondary)
                Text("CLI Tool Access")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text("Grant read access to CLI tool credential directories so CLI Pulse can track your usage.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(statuses.filter({ $0.isInstalled }), id: \.directory.id) { item in
                HStack {
                    Image(systemName: item.hasAccess ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(item.hasAccess ? .green : .orange)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.directory.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Text(item.directory.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if item.hasAccess {
                        Text("Granted")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant") {
                            let success = BookmarkManager.shared.requestAccessViaPanel(
                                directory: item.directory
                            )
                            if success { refreshStatuses() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }

            if statuses.filter({ $0.isInstalled && !$0.hasAccess }).count > 1 {
                Divider()
                Button {
                    grantAll()
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Grant All at Once")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .onAppear { refreshStatuses() }
    }

    private func refreshStatuses() {
        statuses = BookmarkManager.shared.accessStatus()
    }

    private func grantAll() {
        // Open panel at home directory — grants access to all subdirectories
        let panel = NSOpenPanel()
        panel.message = "Select your home folder to grant CLI Pulse access to all CLI tool credentials"
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: realUserHome())

        if panel.runModal() == .OK, let url = panel.url {
            BookmarkManager.shared.storeBookmark(for: url)
            // Also store bookmarks for each known subdirectory
            for status in statuses where status.isInstalled {
                let subURL = URL(fileURLWithPath: status.directory.expandedPath)
                if FileManager.default.fileExists(atPath: subURL.path) {
                    BookmarkManager.shared.storeBookmark(for: subURL)
                }
            }
            refreshStatuses()
        }
    }
}
#endif
