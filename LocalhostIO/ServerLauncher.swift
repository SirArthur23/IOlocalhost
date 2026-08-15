import Foundation
import Darwin

// MARK: - A single launched server process

/// A child server launched in its **own process group**, with its combined
/// stdout/stderr streamed back via `onOutput`. Stopping signals the whole
/// group, so child processes (e.g. the `node` a `npm` script spawns) die too.
final class ServerProcess {
    let pid: pid_t
    private let readFD: Int32
    private var source: DispatchSourceRead?
    private(set) var isRunning = true

    var onOutput: ((String) -> Void)?
    var onExit: (() -> Void)?

    init?(command: String, directory: String) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        let r = fds[0], w = fds[1]

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        // Run inside the project folder, pipe stdout+stderr back to us.
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        posix_spawn_file_actions_adddup2(&actions, w, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, w, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, r)
        posix_spawn_file_actions_addclose(&actions, w)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        // Put the child in a brand-new process group (pgid == child pid) so we
        // can later kill the entire group with kill(-pid, …).
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        // A login shell so PATH picks up Homebrew / nvm / pyenv tooling.
        let argv = ["/bin/zsh", "-lc", command]
        var cargv = argv.map { strdup($0) } + [UnsafeMutablePointer<CChar>?(nil)]
        var cenv = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") } + [UnsafeMutablePointer<CChar>?(nil)]
        defer {
            cargv.forEach { if let p = $0 { free(p) } }
            cenv.forEach { if let p = $0 { free(p) } }
        }

        var newPid: pid_t = 0
        let rc = posix_spawn(&newPid, "/bin/zsh", &actions, &attr, &cargv, &cenv)
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attr)
        close(w)   // parent only reads

        guard rc == 0 else { close(r); return nil }
        self.pid = newPid
        self.readFD = r
        startReading()
    }

    private func startReading() {
        let src = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: .global(qos: .utility))
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = read(self.readFD, &buf, buf.count)
            if n > 0 {
                if let text = String(bytes: buf[0..<n], encoding: .utf8), let cb = self.onOutput {
                    DispatchQueue.main.async { cb(text) }
                }
            } else {
                self.finish()   // EOF — the process is gone
            }
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            close(self.readFD)
        }
        self.source = src
        src.resume()
    }

    private func finish() {
        guard isRunning else { return }
        isRunning = false
        var status: Int32 = 0
        waitpid(pid, &status, 0)   // reap, no zombies
        source?.cancel()
        if let cb = onExit { DispatchQueue.main.async { cb() } }
    }

    /// Terminate the whole process group; force-kill if it lingers.
    func stop() {
        guard isRunning else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isRunning else { return }
            kill(-self.pid, SIGKILL)
        }
    }
}

// MARK: - Launches and tracks the servers the app starts

final class ServerLauncher {
    private var processes: [UUID: ServerProcess] = [:]

    func isRunning(_ id: UUID) -> Bool {
        processes[id]?.isRunning ?? false
    }

    /// Number of servers we launched that are still alive.
    var runningCount: Int {
        processes.values.filter { $0.isRunning }.count
    }

    /// Stop every server we launched (used when quitting the app).
    func stopAll() {
        for process in processes.values { process.stop() }
    }

    /// Start a server with a resolved command in a directory. Returns false if
    /// it's already running or the process failed to spawn.
    @discardableResult
    func launch(id: UUID, command: String, directory: String,
                onOutput: @escaping (String) -> Void,
                onExit: @escaping () -> Void) -> Bool {
        if let existing = processes[id], existing.isRunning { return true }

        guard let proc = ServerProcess(command: command, directory: directory) else { return false }
        proc.onOutput = onOutput
        proc.onExit = { [weak self] in
            self?.processes[id] = nil
            onExit()
        }
        processes[id] = proc
        return true
    }

    /// Stop a server we launched (kills its whole process group).
    func stop(_ id: UUID) {
        processes[id]?.stop()
        // The reference is cleared by the process's own onExit handler once it
        // actually dies, so the reader/source stay alive until then.
    }
}
