import SwiftUI

struct SavedServersView: View {
    enum Mode { case favorites, recent }

    @EnvironmentObject var appState: AppState
    let mode: Mode

    private var servers: [SavedServer] {
        mode == .favorites ? appState.favorites : appState.recents
    }
    private var title: String { mode == .favorites ? "Favorites" : "Recent" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
            }
            .padding()

            Divider()

            if servers.isEmpty {
                ContentUnavailableView(
                    mode == .favorites ? "No favorites yet" : "No recent servers",
                    systemImage: mode == .favorites ? "star" : "clock",
                    description: Text(mode == .favorites
                        ? "Tap the ☆ next to any running server, or on a server you create, to pin it here."
                        : "Servers you start from a folder show up here for quick relaunching.")
                )
            } else {
                List(servers) { server in
                    SavedServerRow(server: server)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppBackground())
    }
}
