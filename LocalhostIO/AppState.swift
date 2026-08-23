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
    /// Working directory per running PID — used to match a saved bookmark to the
    /// *actual* project rather than just the port number. Populated lazily.
    @Published var processCWD: [Int32: String] = [:]

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
        reconcile()                 // fold any persisted duplicate bookmarks
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
                // Drop cwd cache entries for PIDs that are gone.
                let alive = Set(servers.map(\.pid))
                self.processCWD = self.processCWD.filter { alive.contains($0.key) }
                self.refreshCWDs()
                self.reconcile()
            }
        }
    }

    /// Fetch the working directory for dev / bookmarked processes so we can match
    /// a saved project to the process actually running it — even on a new port.
    private func refreshCWDs() {
        let pids = runningServers
            .filter { processCWD[$0.pid] == nil
                && (category(for: $0) == .dev || bookmark(forPort: $0.port) != nil) }
            .map(\.pid)
        guard !pids.isEmpty else { return }
        Task.detached(priority: .utility) {
            var found: [Int32: String] = [:]
            for pid in pids {
                if let cwd = ProcessManager.workingDirectory(for: pid) { found[pid] = cwd }
            }
            await MainActor.run {
                for (pid, cwd) in found { self.processCWD[pid] = cwd }
                self.reconcile()   // new cwds may reveal a project's real port
            }
        }
    }

    /// Keep saved servers tidy: fold duplicate bookmarks that point at the same
    /// project folder into one, and refresh a project's stored port to wherever
    /// it's actually running.
    private func reconcile() {
        var changed = false

        // 1) Merge duplicates by project folder.
        var keptByFolder: [String: Int] = [:]
        var dropIDs: Set<UUID> = []
        for idx in savedServers.indices {
            guard let folder = savedServers[idx].folderPath else { continue }
            if let keepIdx = keptByFolder[folder] {
                var keep = savedServers[keepIdx]
                let dupe = savedServers[idx]
                keep.isFavorite = keep.isFavorite || dupe.isFavorite
                if dupe.lastUsed > keep.lastUsed {
                    keep.label = dupe.label.isEmpty ? keep.label : dupe.label
                    keep.method = dupe.method
                    keep.customCommand = dupe.customCommand
                    keep.port = dupe.port
                    keep.lastUsed = dupe.lastUsed
                } else if keep.label.isEmpty {
                    keep.label = dupe.label
                }
                savedServers[keepIdx] = keep
                dropIDs.insert(dupe.id)
                changed = true
            } else {
                keptByFolder[folder] = idx
            }
        }
        if !dropIDs.isEmpty {
            savedServers.removeAll { dropIDs.contains($0.id) }
            for id in dropIDs { logStore.delete(id); logs[id] = nil }
        }

        // 2) Refresh stored port to the project's live port.
        for idx in savedServers.indices {
            guard savedServers[idx].folderPath != nil,
                  let instance = runningInstance(of: savedServers[idx]),
                  instance.port != savedServers[idx].port else { continue }
            savedServers[idx].port = instance.port
            changed = true
        }

        if changed { store.save(savedServers) }
    }

    /// Ensure we know a running process's cwd (synchronous — for a user action).
    private func ensureCWD(for running: RunningServer) {
        if processCWD[running.pid] == nil {
            processCWD[running.pid] = ProcessManager.workingDirectory(for: running.pid)
        }
    }

    // MARK: - Lookups

    func bookmark(forPort port: Int) -> SavedServer? {
        savedServers.first { $0.port == port }
    }

    /// The live server currently listening on a port, if any.
    func runningServer(onPort port: Int) -> RunningServer? {
        runningServers.first { $0.port == port }
    }

    // MARK: - Project-aware matching (so a reused port doesn't inherit a stale label)

    /// The saved bookmark that truly corresponds to a running process. Prefers a
    /// working-directory match; only falls back to a pure port label (a bookmark
    /// with no folder). A launchable bookmark on the same port but a *different*
    /// folder is intentionally NOT matched.
    func bookmark(for running: RunningServer) -> SavedServer? {
        if let cwd = processCWD[running.pid],
           let byFolder = savedServers.first(where: { $0.folderPath == cwd }) {
            return byFolder
        }
        if let byPort = bookmark(forPort: running.port), byPort.folderPath == nil {
            return byPort
        }
        return nil
    }

    /// The user-chosen label for a specific running process, if any.
    func label(for running: RunningServer) -> String? {
        guard let label = bookmark(for: running)?.label, !label.isEmpty else { return nil }
        return label
    }

    func isFavorite(for running: RunningServer) -> Bool {
        bookmark(for: running)?.isFavorite ?? false
    }

    /// The running process that actually belongs to a saved server. A project is
    /// matched by its working directory *wherever* it's running (it may have moved
    /// ports); a plain port bookmark (no folder) matches by port.
    func runningInstance(of server: SavedServer) -> RunningServer? {
        if let folder = server.folderPath {
            return runningServers.first { processCWD[$0.pid] == folder }
        }
        return runningServers.first { $0.port == server.port }
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

    // MARK: - Labels & favorites (project-aware, for discovered servers)

    /// Set a custom label on a specific running process (project-aware, so a
    /// different app on the same port gets its own bookmark).
    func setLabel(_ label: String, for running: RunningServer) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        ensureCWD(for: running)
        if var b = bookmark(for: running) {
            b.label = trimmed
            upsert(b)
        } else {
            upsert(SavedServer(label: trimmed, port: running.port,
                               folderPath: processCWD[running.pid]))
        }
    }

    /// Favorite a *discovered* running server, capturing how to relaunch it
    /// (working directory + command) while the process is still alive.
    func toggleFavorite(for running: RunningServer) {
        ensureCWD(for: running)
        if var b = bookmark(for: running) {
            b.isFavorite.toggle()
            if b.isFavorite { captureLaunchInfo(&b, from: running) }
            upsert(b)
        } else {
            let fallbackLabel = label(for: running) ?? "localhost:\(running.port)"
            var b = SavedServer(label: fallbackLabel, port: running.port,
                                isFavorite: true, folderPath: processCWD[running.pid])
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
        // Also stop this project's own listener if it lingers — but never an
        // unrelated process that merely reuses the same port.
        if let instance = runningInstance(of: server) { stop(instance) }
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
