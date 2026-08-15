import SwiftUI

// MARK: - Category presentation

extension ServerCategory {
    var color: Color {
        switch self {
        case .dev:         return .green
        case .application: return .blue
        case .system:      return .orange
        case .unknown:     return .secondary
        }
    }

    var badgeIcon: String {
        switch self {
        case .dev:         return "hammer.fill"
        case .application: return "app.badge.fill"
        case .system:      return "gearshape.fill"
        case .unknown:     return "questionmark.circle.fill"
        }
    }
}

// MARK: - Row for a live, discovered server

struct RunningServerRow: View {
    @EnvironmentObject var appState: AppState
    let server: RunningServer

    @State private var showLabelEditor = false
    @State private var editingLabel = ""
    @State private var showStopConfirm = false

    private var category: ServerCategory { appState.category(for: server) }
    private var customLabel: String? { appState.label(forPort: server.port) }
    private var isFavorite: Bool { appState.isFavorite(port: server.port) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(category.color)
                .help(category.title)

            VStack(alignment: .leading, spacing: 2) {
                Text(customLabel ?? "localhost:\(String(server.port))")
                    .font(.headline)
                Text("\(server.processName) · PID \(String(server.pid)) · :\(String(server.port)) · \(server.address)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !server.command.isEmpty {
                    Text(server.command)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(server.command)
                }
            }

            Spacer()

            Button {
                appState.toggleFavorite(for: server)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")

            Button {
                editingLabel = customLabel ?? ""
                showLabelEditor = true
            } label: {
                Image(systemName: "tag")
            }
            .buttonStyle(.borderless)
            .help("Set a custom label")
            .accessibilityLabel("Set a custom label")

            if let url = server.localURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help("Open in browser")
                .accessibilityLabel("Open localhost:\(String(server.port)) in browser")
            }

            Button(role: .destructive) {
                if category.needsStopConfirmation {
                    showStopConfirm = true
                } else {
                    appState.stop(server)
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .tint(category == .dev ? .red : .orange)
            .accessibilityLabel("Stop \(server.processName) on port \(String(server.port))")
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let url = server.localURL {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
            }
            Button("Set Label…") {
                editingLabel = customLabel ?? ""
                showLabelEditor = true
            }
            if !server.command.isEmpty {
                Button("Copy Command Line") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(server.command, forType: .string)
                }
            }
            Divider()
            Button(category.needsStopConfirmation ? "Stop…" : "Stop", role: .destructive) {
                if category.needsStopConfirmation { showStopConfirm = true }
                else { appState.stop(server) }
            }
        }
        .alert("Label for port \(String(server.port))", isPresented: $showLabelEditor) {
            TextField("e.g. My API server", text: $editingLabel)
            Button("Save") { appState.setLabel(editingLabel, forPort: server.port) }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog(
            "Stop “\(server.processName)”?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop anyway", role: .destructive) { appState.stop(server) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This looks like a \(category.title.lowercased()) process (PID \(String(server.pid))), not one of your dev servers. Stopping it may affect other software.")
        }
    }
}

// MARK: - Row for a saved (favorite / recent) server

struct SavedServerRow: View {
    @EnvironmentObject var appState: AppState
    let server: SavedServer

    @State private var showLabelEditor = false
    @State private var editingLabel = ""
    @State private var showLogs = false
    @State private var showConfigure = false

    private var liveServer: RunningServer? { appState.runningServer(onPort: server.port) }
    private var isRunning: Bool { liveServer != nil || appState.isManagedRunning(server) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: server.method?.iconName ?? "bookmark.fill")
                .foregroundStyle(.tint)
                .font(.title2)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.label.isEmpty ? "localhost:\(String(server.port))" : server.label)
                        .font(.headline)
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .help(isRunning ? "Running" : "Stopped")
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let path = server.folderPath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if appState.recentlyExited.contains(server.id) && !isRunning {
                    Button { showLogs = true } label: {
                        Label("Exited on launch — view log", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .help("This server stopped right after starting. Open the log to see why.")
                }
            }

            Spacer()

            Button { appState.toggleFavorite(server) } label: {
                Image(systemName: server.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(server.isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(server.isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(server.isFavorite ? "Remove from favorites" : "Add to favorites")

            if appState.hasLogs(for: server.id) {
                Button { showLogs = true } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("View server logs")
                .accessibilityLabel("View server logs")
            }

            if isRunning {
                Button(role: .destructive) {
                    if appState.isManagedRunning(server) { appState.stopManaged(server) }
                    else { appState.stopPort(server.port) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else if server.isLaunchable {
                Button { appState.launch(server) } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { showConfigure = true } label: {
                    Label("Set Up…", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
                .help("Tell IO how to start this server so you can launch it")
            }

            Menu {
                Button("Rename…") {
                    editingLabel = server.label
                    showLabelEditor = true
                }
                Button(server.isLaunchable ? "Edit Launch Settings…" : "Set Up…") {
                    showConfigure = true
                }
                Button("Open in Browser") {
                    if let url = server.localURL { NSWorkspace.shared.open(url) }
                }
                if let folderURL = server.folderURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
                    }
                }
                Divider()
                Button("Remove", role: .destructive) { appState.remove(server) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 36)
            .accessibilityLabel("More actions")
        }
        .padding(.vertical, 4)
        .alert("Rename server", isPresented: $showLabelEditor) {
            TextField("Label", text: $editingLabel)
            Button("Save") { appState.setLabel(editingLabel, for: server) }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showLogs) {
            LogConsoleView(server: server)
        }
        .sheet(isPresented: $showConfigure) {
            ConfigureServerView(server: server)
        }
    }

    private var subtitle: String {
        if let method = server.method {
            return "\(method.displayName) · :\(String(server.port))"
        }
        return "Bookmarked · localhost:\(String(server.port))"
    }
}

// MARK: - Live log console

struct LogConsoleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let server: SavedServer

    private var text: String { appState.logText(for: server.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(server.label).font(.headline)
                    Text("localhost:\(String(server.port))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(appState.isManagedRunning(server) ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(appState.isManagedRunning(server) ? "Running" : "Stopped")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "Waiting for output…" : text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: text) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Button {
                    if appState.isManagedRunning(server) { appState.stopManaged(server) }
                    else if server.isLaunchable { appState.launch(server) }
                } label: {
                    Label(appState.isManagedRunning(server) ? "Stop" : "Start",
                          systemImage: appState.isManagedRunning(server) ? "stop.fill" : "play.fill")
                }
                Button("Clear") { appState.clearLog(for: server.id) }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 420)
        .onAppear { appState.clearExitedFlag(server.id) }
    }
}
