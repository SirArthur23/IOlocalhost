import Foundation

/// Discovers processes listening on local TCP ports using `lsof`.
enum PortScanner {
    static func scan() -> [RunningServer] {
        // -nP: don't resolve host names / port names (faster, numeric)
        // +c0: don't truncate the COMMAND column to 9 characters
        // -iTCP -sTCP:LISTEN: only TCP sockets in the LISTEN state
        let output = Shell.run("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN"])
        var servers = parse(output)

        // One batched `ps` call to attach full command lines by PID.
        let commands = commandLines()
        for i in servers.indices {
            if let cmd = commands[servers[i].pid] { servers[i].command = cmd }
        }
        return servers
    }

    /// Map of PID -> full command line, from a single `ps` invocation.
    static func commandLines() -> [Int32: String] {
        let output = Shell.run("/bin/ps", ["-axww", "-o", "pid=,command="])
        var map: [Int32: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            guard let space = trimmed.firstIndex(of: " ") else { continue }
            guard let pid = Int32(trimmed[..<space]) else { continue }
            let command = trimmed[trimmed.index(after: space)...]
                .trimmingCharacters(in: .whitespaces)
            map[pid] = command
        }
        return map
    }

    /// Parses default-format `lsof` output. Exposed for testing.
    static func parse(_ output: String) -> [RunningServer] {
        var results: [RunningServer] = []
        var seen = Set<String>()

        for line in output.split(separator: "\n").dropFirst() {  // drop header row
            var cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

            // lsof appends a state token such as "(LISTEN)" after the NAME
            // column; drop it so the address:port becomes the last column.
            if let last = cols.last, last.hasPrefix("(") {
                cols.removeLast()
            }

            guard cols.count >= 9,
                  let pid = Int32(cols[1]),
                  let name = cols.last else { continue }

            // lsof escapes spaces in the command name as "\x20".
            let command = cols[0].replacingOccurrences(of: "\\x20", with: " ")
            let user = cols[2]

            // NAME looks like "127.0.0.1:3000", "*:8080" or "[::1]:5173".
            guard let portSubstring = name.split(separator: ":").last,
                  let port = Int(portSubstring) else { continue }

            let address = String(name.dropLast(portSubstring.count + 1))
            let key = "\(pid)-\(port)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            results.append(RunningServer(
                pid: pid,
                port: port,
                processName: command,
                user: user,
                address: address.isEmpty ? "*" : address
            ))
        }

        return results.sorted { $0.port < $1.port }
    }
}
