import Foundation
import SwiftUI

/// The single source of truth for the UI. Owns the running-server scan results
/// and the persisted list of saved servers (labels / favorites / launchables).
@MainActor
final class AppState: ObservableObject {
    @Published var runningServers: [RunningServer] = []
    @Published var savedServers: [SavedServer] = []
    @Published var lastRefresh: Date = .now
    /// Live console output for servers we launched this session, keyed by id.
    @Published var logs: [UUID: String] = [:]
    /// Servers that exited unexpectedly shortly after we started them.
    @Published var recentlyExited: Set<UUID> = []

    private let store = Store()
    private let logStore = LogStore()
    private let launcher = ServerLauncher()
    private var timer: Timer?
    private let maxLogCharacters = 80_000
    private var launchTimes: [UUID: Date] = [:]
    private var intentionallyStopping: Set<UUID> = []

    // MARK: Managed-server lifecycle (used by the quit handler)

    var managedRunningCount: Int { launcher.runningCount }
    var hasManagedServersRunning: Bool { launcher.runningCount > 0 }
    func stopAllManaged() { launcher.stopAll() }

    // MARK: Derived collections

    /// Running servers organised into smart groups (Adobe, Docker, Development…).
    var runningGroups: [ServerGroup] {
        ProcessClassifier.group(runningServers)
    }

    var favorites: [SavedServer] {
        savedServers.filter(\.isFavorite).sorted { $0.label.lowercased() < $1.label.lowercased() }
    }

    /// Recent = launchable, non-favorite entries, newest first.
    var recents: [SavedServer] {
        savedServers
            .filter { !$0.isFavorite && $0.isLaunchable }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    init() {
        savedServers = store.load()
        logs = logStore.loadAll()   // restore logs from previous sessions
        refreshRunning()
        startAutoRefresh()
    }

    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRunning() }
        }
    }

    func refreshRunning() {
        Task.detached(priority: .userInitiated) {
            let servers = PortScanner.scan()
            await MainActor.run {
                self.runningServers = servers
                self.lastRefresh = .now
            }
        }
    }

    // MARK: - Lookups

    func bookmark(forPort port: Int) -> SavedServer? {
        savedServers.first { $0.port == port }
    }

    /// The user-chosen label for a port, if any.
    func label(forPort port: Int) -> String? {
        guard let label = bookmark(forPort: port)?.label, !label.isEmpty else { return nil }
        return label
    }

    func isFavorite(port: Int) -> Bool {
        bookmark(forPort: port)?.isFavorite ?? false
    }

    /// The live server currently listening on a port, if any.
    func runningServer(onPort port: Int) -> RunningServer? {
        runningServers.first { $0.port == port }
    }

    func category(for server: RunningServer) -> ServerCategory {
        ProcessClassifier.classify(server.processName).category
    }

    // MARK: - Running server actions

    func stop(_ server: RunningServer) {
        ProcessManager.stop(pid: server.pid)
        runningServers.removeAll { $0.id == server.id }   // optimistic
        scheduleRefresh(after: 0.8)
    }

    /// Stop whatever is listening on a port (used from the Favorites view).
    func stopPort(_ port: Int) {
        guard let server = runningServer(onPort: port) else { return }
        stop(server)
    }

    // MARK: - Labels & favorites (by port, for discovered servers)

    func setLabel(_ label: String, forPort port: Int) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if var b = bookmark(forPort: port) {
            b.label = trimmed
            upsert(b)
        } else {
            upsert(SavedServer(label: trimmed, port: port))
        }
    }

    func toggleFavorite(forPort port: Int, fallbackLabel: String) {
        if var b = bookmark(forPort: port) {
            b.isFavorite.toggle()
            upsert(b)
        } else {
            upsert(SavedServer(label: fallbackLabel, port: port, isFavorite: true))
        }
    }

    /// Favorite a *discovered* running server, capturing how to relaunch it
    /// (working directory + command) while the process is still alive.
    func toggleFavorite(for running: RunningServer) {
        let fallbackLabel = label(forPort: running.port) ?? "localhost:\(running.port)"
        if var b = bookmark(forPort: running.port) {
            b.isFavorite.toggle()
            if b.isFavorite { captureLaunchInfo(&b, from: running) }
            upsert(b)
        } else {
            var b = SavedServer(label: fallbackLabel, port: running.port, isFavorite: true)
            captureLaunchInfo(&b, from: running)
            upsert(b)
        }
    }

    /// Fill in folder + command for a bookmark from a live process, if we can
    /// recover them. Leaves the bookmark "needs setup" when we can't.
    private func captureLaunchInfo(_ bookmark: inout SavedServer, from running: RunningServer) {
        guard !bookmark.isLaunchable else { return }
        if bookmark.folderPath == nil {
            bookmark.folderPath = ProcessManager.workingDirectory(for: running.pid)
        }
        if (bookmark.customCommand ?? "").isEmpty {
            bookmark.customCommand = ProcessManager.relaunchCommand(for: running)
        }
    }

    /// Save manual launch configuration (from the Set Up… sheet). Returns the
    /// updated server so the caller can immediately start it if desired.
    @discardableResult
    func configure(_ server: SavedServer, label: String, folderPath: String?,
                   method: ServeMethod?, customCommand: String?, port: Int) -> SavedServer {
        var s = server
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty { s.label = trimmedLabel }
        s.folderPath = (folderPath?.isEmpty == false) ? folderPath : nil
        s.method = method
        s.customCommand = (customCommand?.isEmpty == false) ? customCommand : nil
        s.port = port
        upsert(s)
        return s
    }

    // MARK: - Saved server actions

    func launch(_ server: SavedServer) {
        guard let command = server.resolvedCommand() else { return }
        var updated = server
        updated.lastUsed = .now
        upsert(updated)

        let id = updated.id
        let directory = updated.workingDirectory
        logStore.reset(id)
        logs[id] = ""   // fresh console on (re)launch
        recentlyExited.remove(id)
        launchTimes[id] = .now
        appendLog("$ cd \(directory)\n$ \(command)\n", for: id)

        launcher.launch(id: id, command: command, directory: directory,
            onOutput: { [weak self] chunk in self?.appendLog(chunk, for: id) },
            onExit: { [weak self] in self?.handleExit(id) })
        scheduleRefresh(after: 1.5)
    }

    /// Called when a launched server ends. Flags an unexpected quick exit so the
    /// row can show a failure badge (unless the user asked it to stop).
    private func handleExit(_ id: UUID) {
        appendLog("\n— process exited —\n", for: id)
        let wasQuick = launchTimes[id].map { Date().timeIntervalSince($0) < 5 } ?? false
        if intentionallyStopping.remove(id) == nil, wasQuick {
            recentlyExited.insert(id)
        }
        refreshRunning()
    }

    func clearExitedFlag(_ id: UUID) { recentlyExited.remove(id) }

    // MARK: - Logs

    func logText(for id: UUID) -> String { logs[id] ?? "" }
    func hasLogs(for id: UUID) -> Bool { logs[id] != nil }
    func clearLog(for id: UUID) {
        logs[id] = ""
        logStore.reset(id)
    }

    private func appendLog(_ chunk: String, for id: UUID) {
        var text = logs[id] ?? ""
        text += chunk
        if text.count > maxLogCharacters {
            text = String(text.suffix(maxLogCharacters))
        }
        logs[id] = text
        logStore.append(chunk, for: id)
    }

    func stopManaged(_ server: SavedServer) {
        intentionallyStopping.insert(server.id)   // so onExit isn't flagged as a failure
        launcher.stop(server.id)
        // Also stop anything still listening on that port that we didn't track.
        stopPort(server.port)
        scheduleRefresh(after: 0.8)
    }

    func isManagedRunning(_ server: SavedServer) -> Bool {
        launcher.isRunning(server.id)
    }

    func addServer(label: String, folderPath: String, method: ServeMethod?,
                   customCommand: String?, port: Int, favorite: Bool, launchNow: Bool) {
        // Reuse an existing bookmark for this port if present.
        var server = bookmark(forPort: port) ?? SavedServer(label: label, port: port)
        server.label = label
        server.folderPath = folderPath
        server.method = method
        server.customCommand = (customCommand?.isEmpty == false) ? customCommand : nil
        server.isFavorite = server.isFavorite || favorite
        server.lastUsed = .now
        upsert(server)
        if launchNow { launch(server) }
    }

    func toggleFavorite(_ server: SavedServer) {
        var s = server
        s.isFavorite.toggle()
        upsert(s)
    }

    func setLabel(_ label: String, for server: SavedServer) {
        var s = server
        s.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        upsert(s)
    }

    func remove(_ server: SavedServer) {
        savedServers.removeAll { $0.id == server.id }
        store.save(savedServers)
        logs[server.id] = nil
        logStore.delete(server.id)
    }

    // MARK: - Helpers

    private func upsert(_ server: SavedServer) {
        if let idx = savedServers.firstIndex(where: { $0.id == server.id }) {
            savedServers[idx] = server
        } else {
            savedServers.append(server)
        }
        store.save(savedServers)
    }

    private func scheduleRefresh(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.refreshRunning()
        }
    }
}
