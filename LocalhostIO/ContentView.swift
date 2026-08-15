import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case running   = "Running"
    case favorites = "Favorites"
    case recent    = "Recent"
    case newServer = "New Server"

    var id: String { rawValue }

    /// The items shown as plain navigation rows (New Server is a button instead).
    static var navigationRows: [SidebarItem] { [.running, .favorites, .recent] }

    var icon: String {
        switch self {
        case .running:   return "bolt.horizontal.circle"
        case .favorites: return "star"
        case .recent:    return "clock"
        case .newServer: return "plus.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SidebarItem? = .running

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.navigationRows, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .badge(badge(for: item))
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
            .safeAreaInset(edge: .top) {
                NewServerButton(isActive: selection == .newServer) {
                    selection = .newServer
                }
            }
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            Group {
                switch selection ?? .running {
                case .running:   RunningServersView()
                case .favorites: SavedServersView(mode: .favorites)
                case .recent:    SavedServersView(mode: .recent)
                case .newServer: NewServerView()
                }
            }
            .navigationSplitViewColumnWidth(min: 540, ideal: 640)
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .running:   return appState.runningServers.count
        case .favorites: return appState.favorites.count
        case .recent:    return appState.recents.count
        case .newServer: return 0
        }
    }
}

// MARK: - Prominent "New Server" call-to-action

private struct NewServerButton: View {
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("New Server")
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .opacity(isActive ? 1.0 : (hovering ? 0.92 : 0.85))
            )
            .foregroundStyle(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(isActive ? 0.35 : 0), lineWidth: 1)
            )
            .shadow(color: Color.accentColor.opacity(0.35), radius: hovering ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - Decorative background used behind detail panes

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.11, green: 0.11, blue: 0.17), Color(red: 0.06, green: 0.06, blue: 0.10)]
                    : [Color(red: 0.97, green: 0.97, blue: 1.00), Color(red: 0.92, green: 0.94, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "network")
                .font(.system(size: 440, weight: .ultraLight))
                .foregroundStyle(.tint.opacity(scheme == .dark ? 0.06 : 0.05))
                .rotationEffect(.degrees(-12))
                .offset(x: 180, y: 150)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Small illustrated footer in the sidebar

private struct SidebarFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.accentColor.gradient)
            Text("IO: localhost")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Local server manager")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
