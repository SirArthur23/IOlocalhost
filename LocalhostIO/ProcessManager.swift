import Foundation
import Darwin

/// Tiny helper to run a command-line tool and capture its output.
enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Stops / inspects arbitrary processes by PID.
enum ProcessManager {
    /// Politely ask a process to terminate.
    static func stop(pid: Int32) {
        kill(pid, SIGTERM)
    }

    /// Forcefully kill a process.
    static func forceStop(pid: Int32) {
        kill(pid, SIGKILL)
    }

    /// The full command line for a PID, e.g. "node /path/to/server.js".
    static func commandLine(for pid: Int32) -> String {
        Shell.run("/bin/ps", ["-p", "\(pid)", "-o", "command="])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The original argv of a process via sysctl(KERN_PROCARGS2). Note: some
    /// processes (e.g. Node/Next) rewrite their argv memory to set a custom
    /// title, in which case the original arguments are unrecoverable.
    static func realArguments(pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        return buffer.withUnsafeBufferPointer { raw -> [String]? in
            guard let base = raw.baseAddress else { return nil }
            var argc: Int32 = 0
            memcpy(&argc, base, MemoryLayout<Int32>.size)
            var offset = MemoryLayout<Int32>.size

            let execPath = String(cString: base + offset)
            offset += execPath.utf8.count
            while offset < size && base[offset] == 0 { offset += 1 }   // skip padding

            var args: [String] = []
            var collected: Int32 = 0
            while collected < argc && offset < size {
                let arg = String(cString: base + offset)
                args.append(arg)
                offset += arg.utf8.count + 1
                collected += 1
            }
            return args
        }
    }

    /// The working directory of a process (via lsof).
    static func workingDirectory(for pid: Int32) -> String? {
        let output = Shell.run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
        for line in output.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// Best-effort recovery of a runnable command for a discovered server.
    /// Returns nil when the original command can't be recovered (caller should
    /// then ask the user to configure it).
    static func relaunchCommand(for server: RunningServer) -> String? {
        if let argv = realArguments(pid: server.pid), let cmd = plausibleCommand(argv) {
            return cmd
        }
        // Fall back to the ps command line if it looks like a real path.
        let ps = server.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if ps.hasPrefix("/") && !ps.contains("(") { return ps }
        return nil
    }

    private static func plausibleCommand(_ argv: [String]) -> String? {
        guard let first = argv.first, first.contains("/") else { return nil }
        guard !argv.contains("") else { return nil }   // title-rewrite artifact
        return argv.map(shellQuote).joined(separator: " ")
    }

    /// Quote a single shell argument safely.
    static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = s.allSatisfy { $0.isLetter || $0.isNumber || "@%+=:,./-_".contains($0) }
        if safe { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
