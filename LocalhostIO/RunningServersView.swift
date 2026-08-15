import SwiftUI

struct RunningServersView: View {
    @EnvironmentObject var appState: AppState
    @State private var expanded: [String: Bool] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Running Servers").font(.title2.bold())
                Spacer()
                Text("Updated \(appState.lastRefresh.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    appState.refreshRunning()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            if appState.runningServers.isEmpty {
                ContentUnavailableView(
                    "Nothing listening",
                    systemImage: "bolt.slash",
                    description: Text("No process is currently listening on a local TCP port.")
                )
            } else {
                List {
                    ForEach(appState.runningGroups) { group in
                        DisclosureGroup(isExpanded: binding(for: group)) {
                            ForEach(group.servers) { server in
                                RunningServerRow(server: server)
                            }
                        } label: {
                            GroupHeader(group: group)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppBackground())
    }

    private func binding(for group: ServerGroup) -> Binding<Bool> {
        Binding(
            get: { expanded[group.name] ?? (group.category == .dev) },
            set: { expanded[group.name] = $0 }
        )
    }
}

private struct GroupHeader: View {
    let group: ServerGroup

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.category.badgeIcon)
                .foregroundStyle(group.category.color)
            Text(group.name).font(.headline)
            Text("\(group.servers.count)")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            Spacer()
            Text(group.category.title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(group.category.color)
        }
        .padding(.vertical, 2)
    }
}
