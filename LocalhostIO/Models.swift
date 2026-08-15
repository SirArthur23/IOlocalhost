import Foundation

// MARK: - Running server (discovered live via lsof)

/// A process currently listening on a local TCP port.
struct RunningServer: Identifiable, Hashable {
    var id: String { "\(pid)-\(port)-\(address)" }
    let pid: Int32
    let port: Int
    let processName: String
    let user: String
    let address: String
    /// Full command line (from `ps`), e.g. "node /path/to/server.js --port 3000".
    var command: String = ""

    var localURL: URL? { URL(string: "http://localhost:\(port)") }
}

// MARK: - Saved server / bookmark (persisted)

/// A user-saved entry. It can be:
///  - a *bookmark* of a discovered server (just `label` + `port`), or
///  - a *launchable* server (also has `folderPath` + `method`).
/// Promoted to the Favorites section when `isFavorite` is true.
struct SavedServer: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var port: Int
    var isFavorite: Bool = false
    var lastUsed: Date = .now
    var folderPath: String? = nil
    var method: ServeMethod? = nil
    /// A raw shell command to start this server, used when there's no `method`
    /// (e.g. captured from an externally-started server).
    var customCommand: String? = nil

    /// Can we start this server? Either a folder+method, or a custom command.
    var isLaunchable: Bool {
        (folderPath != nil && method != nil) ||
        !(customCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The command we'd run to (re)start it, if known.
    func resolvedCommand() -> String? {
        if let method, folderPath != nil { return method.shellCommand(port: port) }
        let custom = (customCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? nil : custom
    }

    /// Directory to launch in (the saved folder, falling back to home).
    var workingDirectory: String {
        folderPath ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var folderURL: URL? { folderPath.map { URL(fileURLWithPath: $0) } }
    var localURL: URL? { URL(string: "http://localhost:\(port)") }
}

// MARK: - Serve methods

/// The different ways the app knows how to serve a folder.
enum ServeMethod: String, Codable, CaseIterable, Identifiable {
    case viteReact
    case nextjs
    case npmDev
    case npmStart
    case pythonHTTP
    case phpBuiltin
    case staticServe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .viteReact:   return "React / Vite (npm run dev)"
        case .nextjs:      return "Next.js (npm run dev)"
        case .npmDev:      return "Node (npm run dev)"
        case .npmStart:    return "Node (npm start)"
        case .pythonHTTP:  return "Python (http.server)"
        case .phpBuiltin:  return "PHP (built-in server)"
        case .staticServe: return "Static files (npx serve)"
        }
    }

    var iconName: String {
        switch self {
        case .viteReact, .nextjs, .npmDev, .npmStart: return "shippingbox.fill"
        case .pythonHTTP:  return "ladybug.fill"
        case .phpBuiltin:  return "chevron.left.forwardslash.chevron.right"
        case .staticServe: return "doc.richtext.fill"
        }
    }

    var defaultPort: Int {
        switch self {
        case .viteReact:   return 5173
        case .nextjs:      return 3000
        case .npmDev:      return 3000
        case .npmStart:    return 3000
        case .pythonHTTP:  return 8000
        case .phpBuiltin:  return 8080
        case .staticServe: return 3000
        }
    }

    /// The shell command run inside the project folder to start the server.
    func shellCommand(port: Int) -> String {
        switch self {
        case .viteReact:   return "npm run dev -- --port \(port)"
        case .nextjs:      return "npm run dev -- -p \(port)"
        case .npmDev:      return "npm run dev"
        case .npmStart:    return "npm start"
        case .pythonHTTP:  return "python3 -m http.server \(port)"
        case .phpBuiltin:  return "php -S localhost:\(port)"
        case .staticServe: return "npx --yes serve -l \(port) ."
        }
    }
}

// MARK: - Project detection

/// The result of inspecting a folder: what kind of project it is and the most
/// likely way to start it.
struct ProjectAnalysis {
    var summary: String              // e.g. "Next.js app · pnpm"
    var reason: String               // e.g. "package.json + pnpm-lock.yaml"
    var icon: String                 // SF Symbol
    var method: ServeMethod?         // mapped built-in method, if one fits
    var command: String?             // exact recommended shell command
    var port: Int
    var packageManager: String?      // npm / yarn / pnpm / bun
    var scripts: [ScriptEntry]       // package.json scripts, dev/start first

    struct ScriptEntry: Identifiable, Hashable {
        var id: String { name }
        let name: String     // "dev" or "run_ghost_hub_local"
        let raw: String      // package.json command, or the script's relative path
        let runCommand: String   // how to run it, e.g. "pnpm dev" or "./ops/run_x.sh"
        var port: Int? = nil // detected port for this entry, if known
        var backgrounds: Bool = false  // script detaches (nohup … &) — IO can't manage it
    }

    static let unknown = ProjectAnalysis(
        summary: "Unrecognized folder",
        reason: "No known project files found — pick a method or enter a command.",
        icon: "questionmark.folder",
        method: .staticServe,
        command: "npx --yes serve -l 3000 .",
        port: 3000, packageManager: nil, scripts: []
    )
}

enum ProjectDetector {
    /// Backwards-compatible: best serve methods, best first.
    static func suggestMethods(for folderURL: URL) -> [ServeMethod] {
        if let m = analyze(folderURL).method { return [m] }
        return [.staticServe, .pythonHTTP, .npmDev]
    }

    /// Inspect a folder and describe how to start it.
    static func analyze(_ folderURL: URL) -> ProjectAnalysis {
        let fm = FileManager.default
        let path = folderURL.path
        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: (path as NSString).appendingPathComponent(name))
        }
        func read(_ name: String) -> String? {
            guard let data = fm.contents(atPath: (path as NSString).appendingPathComponent(name))
            else { return nil }
            return String(data: data, encoding: .utf8)
        }

        // Ghost (Ghost-CLI install) — check before generic Node detection, since
        // the install folder usually has no root package.json.
        if exists(".ghost-cli") || (exists("config.development.json") && exists("content")) {
            let isDev = exists("config.development.json")
            var port = 2368
            if let cfg = read(isDev ? "config.development.json" : "config.production.json")
                        ?? read("config.production.json") ?? read("config.development.json"),
               let data = cfg.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let server = json["server"] as? [String: Any] {
                    if let p = server["port"] as? Int { port = p }
                    else if let s = server["port"] as? String, let p = Int(s) { port = p }
                } else if let urlStr = json["url"] as? String,
                          let comps = URLComponents(string: urlStr), let p = comps.port {
                    port = p
                }
            }
            return .init(summary: "Ghost site", reason: "Found a Ghost install (.ghost-cli)",
                         icon: "newspaper.fill", method: nil,
                         command: isDev ? "ghost run --development" : "ghost run",
                         port: port, packageManager: nil, scripts: [])
        }

        if exists("package.json") { return analyzeNode(read: read, exists: exists) }

        // Python — Django / Flask / generic
        if exists("manage.py") {
            return .init(summary: "Django app", reason: "Found manage.py", icon: "ladybug.fill",
                         method: nil, command: "python3 manage.py runserver 0.0.0.0:8000",
                         port: 8000, packageManager: nil, scripts: [])
        }
        let pyEntry = ["app.py", "wsgi.py", "main.py", "server.py"].first(where: exists)
        if let entry = pyEntry {
            let flask = (read(entry)?.range(of: "flask", options: .caseInsensitive) != nil)
                || (read("requirements.txt")?.range(of: "flask", options: .caseInsensitive) != nil)
            if flask {
                return .init(summary: "Flask app", reason: "Found \(entry) using Flask",
                             icon: "ladybug.fill", method: nil, command: "flask run --port 5000",
                             port: 5000, packageManager: nil, scripts: [])
            }
            return .init(summary: "Python app", reason: "Found \(entry)", icon: "ladybug.fill",
                         method: nil, command: "python3 \(entry)", port: 8000,
                         packageManager: nil, scripts: [])
        }
        if exists("requirements.txt") || exists("pyproject.toml") {
            return .init(summary: "Python project", reason: "Found requirements/pyproject",
                         icon: "ladybug.fill", method: .pythonHTTP,
                         command: "python3 -m http.server 8000", port: 8000,
                         packageManager: nil, scripts: [])
        }

        // PHP / Laravel
        if exists("artisan") {
            return .init(summary: "Laravel app", reason: "Found artisan",
                         icon: "chevron.left.forwardslash.chevron.right", method: nil,
                         command: "php artisan serve --port 8000", port: 8000,
                         packageManager: nil, scripts: [])
        }
        if exists("composer.json") || exists("index.php") {
            return .init(summary: "PHP project", reason: "Found composer.json/index.php",
                         icon: "chevron.left.forwardslash.chevron.right", method: .phpBuiltin,
                         command: "php -S localhost:8080", port: 8080,
                         packageManager: nil, scripts: [])
        }

        // Ruby / Rails
        if exists("bin/rails") || (read("Gemfile")?.range(of: "rails", options: .caseInsensitive) != nil) {
            return .init(summary: "Rails app", reason: "Found Rails (Gemfile/bin/rails)",
                         icon: "diamond.fill", method: nil, command: "bin/rails server -p 3000",
                         port: 3000, packageManager: nil, scripts: [])
        }
        if exists("config.ru") {
            return .init(summary: "Rack app", reason: "Found config.ru", icon: "diamond.fill",
                         method: nil, command: "rackup -p 9292", port: 9292,
                         packageManager: nil, scripts: [])
        }

        // Go / Rust
        if exists("go.mod") {
            return .init(summary: "Go app", reason: "Found go.mod", icon: "g.circle.fill",
                         method: nil, command: "go run .", port: 8080,
                         packageManager: nil, scripts: [])
        }
        if exists("Cargo.toml") {
            return .init(summary: "Rust app", reason: "Found Cargo.toml", icon: "gearshape.2.fill",
                         method: nil, command: "cargo run", port: 8080,
                         packageManager: nil, scripts: [])
        }

        // Static site generators
        if exists("hugo.toml") || exists("hugo.yaml") || (exists("config.toml") && exists("content")) {
            return .init(summary: "Hugo site", reason: "Found Hugo config", icon: "globe",
                         method: nil, command: "hugo server -p 1313", port: 1313,
                         packageManager: nil, scripts: [])
        }
        if exists("_config.yml") {
            return .init(summary: "Jekyll site", reason: "Found _config.yml", icon: "globe",
                         method: nil, command: "bundle exec jekyll serve --port 4000", port: 4000,
                         packageManager: nil, scripts: [])
        }

        // Custom start scripts (ops/ convention: start_x.sh / run_x.sh …)
        let startScripts = detectStartScripts(path: path, fm: fm)
        if let primary = startScripts.first {
            let isGhost = startScripts.contains { $0.name.lowercased().contains("ghost") }
            return .init(
                summary: isGhost ? "Ghost project · ops scripts" : "Project · shell scripts",
                reason: "Found \(startScripts.count) start script\(startScripts.count == 1 ? "" : "s") in ops/scripts/bin — pick one below",
                icon: isGhost ? "newspaper.fill" : "terminal.fill",
                method: nil, command: primary.runCommand,
                port: primary.port ?? (isGhost ? 2368 : 3000),
                packageManager: nil, scripts: startScripts)
        }

        // Plain static
        if exists("index.html") {
            return .init(summary: "Static site", reason: "Found index.html",
                         icon: "doc.richtext.fill", method: .staticServe,
                         command: "npx --yes serve -l 3000 .", port: 3000,
                         packageManager: nil, scripts: [])
        }

        return .unknown
    }

    // MARK: Custom start-script detection

    /// Find runnable "start" shell scripts in common ops folders. The
    /// foreground `run_*` variants are preferred so IO can manage them directly.
    private static func detectStartScripts(path: String, fm: FileManager) -> [ProjectAnalysis.ScriptEntry] {
        let dirs = ["ops", "scripts", "bin", ""]
        let include = ["start", "run", "serve", "dev", "up", "launch", "boot", "ghost"]
        let exclude = ["stop", "status", "restart", "down", "build", "test",
                       "deploy", "install", "lint", "clean", "setup", "reset", "backup"]
        var entries: [ProjectAnalysis.ScriptEntry] = []
        var seen = Set<String>()

        for sub in dirs {
            let dirPath = sub.isEmpty ? path : (path as NSString).appendingPathComponent(sub)
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files.sorted() where file.hasSuffix(".sh") {
                let lower = file.lowercased()
                guard include.contains(where: lower.contains),
                      !exclude.contains(where: lower.contains) else { continue }
                let rel = sub.isEmpty ? file : "\(sub)/\(file)"
                guard seen.insert(rel).inserted else { continue }
                let full = (path as NSString).appendingPathComponent(rel)
                let text = (fm.contents(atPath: full)).flatMap { String(data: $0, encoding: .utf8) }
                entries.append(.init(name: String(file.dropLast(3)), raw: rel,
                                     runCommand: "./\(rel)",
                                     port: portFromScript(at: full, projectPath: path, fm: fm),
                                     backgrounds: scriptBackgrounds(text)))
            }
        }

        // If a backgrounding script has a foreground sibling for the same service
        // (e.g. start_x.sh vs run_x.sh), drop the backgrounding one — IO can only
        // manage the foreground variant.
        func baseName(_ n: String) -> String {
            var s = n.lowercased()
            for prefix in ["start_", "run_", "serve_", "dev_", "launch_", "boot_", "up_"] where s.hasPrefix(prefix) {
                s.removeFirst(prefix.count); break
            }
            return s
        }
        let foregroundBases = Set(entries.filter { !$0.backgrounds }.map { baseName($0.name) })
        let filtered = entries.filter { !($0.backgrounds && foregroundBases.contains(baseName($0.name))) }

        // Foreground `run_*` first, then `start_*`, then others; managed before detached.
        func rank(_ e: ProjectAnalysis.ScriptEntry) -> Int {
            if e.backgrounds { return 3 }
            let l = e.name.lowercased()
            if l.hasPrefix("run") { return 0 }
            if l.hasPrefix("start") { return 1 }
            return 2
        }
        return filtered.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name < $1.name }
    }

    /// True if a shell script backgrounds/detaches its work (nohup … & / disown).
    private static func scriptBackgrounds(_ text: String?) -> Bool {
        guard let text else { return false }
        if text.contains("nohup") || text.contains("disown") { return true }
        // A command line ending in "&" (but not "&&"), on any line.
        return text.range(of: "(?m)[^&]&[ \\t]*(#.*)?$", options: .regularExpression) != nil
    }

    /// Best-effort port for a start script: parse the script text, or follow a
    /// referenced Ghost folder to its config.
    private static func portFromScript(at scriptPath: String, projectPath: String, fm: FileManager) -> Int? {
        guard let data = fm.contents(atPath: scriptPath),
              let text = String(data: data, encoding: .utf8) else { return nil }

        for pattern in ["localhost:([0-9]{2,5})", "--port[ =]([0-9]{2,5})", "PORT[ =\"]+([0-9]{2,5})"] {
            if let s = firstCapture(text, pattern), let p = Int(s) { return p }
        }
        // Follow a referenced "<something>ghost<something>local" folder's config.
        if let dir = firstCapture(text, "([A-Za-z0-9._-]*ghost[A-Za-z0-9._-]*local)") {
            let cfg = ((projectPath as NSString).appendingPathComponent(dir) as NSString)
                .appendingPathComponent("config.development.json")
            if let d = fm.contents(atPath: cfg),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let server = j["server"] as? [String: Any], let p = server["port"] as? Int {
                return p
            }
        }
        return nil
    }

    private static func firstCapture(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: Node project analysis

    private static func analyzeNode(read: (String) -> String?, exists: (String) -> Bool) -> ProjectAnalysis {
        let pm = packageManager(exists: exists)
        let lockName = lockfileName(exists: exists)

        var deps: [String: Any] = [:]
        var scriptsDict: [String: String] = [:]
        if let raw = read("package.json"),
           let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            deps = ((json["dependencies"] as? [String: Any]) ?? [:])
                .merging((json["devDependencies"] as? [String: Any]) ?? [:]) { a, _ in a }
            scriptsDict = (json["scripts"] as? [String: String]) ?? [:]
        }
        func has(_ name: String) -> Bool { deps[name] != nil }

        // Ordered script list, dev/start/serve/preview first.
        let priority = ["dev", "start", "serve", "preview", "develop"]
        let orderedNames = priority.filter { scriptsDict[$0] != nil }
            + scriptsDict.keys.filter { !priority.contains($0) }.sorted()
        let scripts = orderedNames.map { name in
            ProjectAnalysis.ScriptEntry(name: name, raw: scriptsDict[name] ?? "",
                                        runCommand: runScript(name, pm: pm))
        }

        // Identify framework -> (summary, method, default script, port)
        let framework: (name: String, method: ServeMethod?, script: String, port: Int)
        if has("next") {
            framework = ("Next.js", .nextjs, pick("dev", scriptsDict) ?? "start", 3000)
        } else if has("nuxt") {
            framework = ("Nuxt", .npmDev, pick("dev", scriptsDict) ?? "dev", 3000)
        } else if exists("angular.json") || has("@angular/core") {
            framework = ("Angular", .npmStart, pick("start", scriptsDict) ?? "start", 4200)
        } else if has("@remix-run/dev") || has("@remix-run/react") {
            framework = ("Remix", .npmDev, pick("dev", scriptsDict) ?? "dev", 3000)
        } else if has("gatsby") {
            framework = ("Gatsby", .npmDev, pick("develop", scriptsDict) ?? "develop", 8000)
        } else if has("astro") {
            framework = ("Astro", .npmDev, pick("dev", scriptsDict) ?? "dev", 4321)
        } else if has("@sveltejs/kit") || has("svelte") {
            framework = ("SvelteKit", .viteReact, pick("dev", scriptsDict) ?? "dev", 5173)
        } else if has("react-scripts") {
            framework = ("Create React App", .npmStart, pick("start", scriptsDict) ?? "start", 3000)
        } else if has("vite") {
            framework = ("Vite", .viteReact, pick("dev", scriptsDict) ?? "dev", 5173)
        } else if has("@vue/cli-service") || has("vue") {
            framework = ("Vue", .npmDev, pick("serve", scriptsDict) ?? pick("dev", scriptsDict) ?? "serve", 8080)
        } else {
            let script = pick("dev", scriptsDict) ?? pick("start", scriptsDict) ?? pick("serve", scriptsDict) ?? "dev"
            framework = ("Node app", scriptsDict["start"] != nil && scriptsDict["dev"] == nil ? .npmStart : .npmDev, script, 3000)
        }

        let command = runScript(framework.script, pm: pm)
        let summary = "\(framework.name) · \(pm)"
        let reason = "package.json (\(framework.name))" + (lockName.map { " + \($0)" } ?? "")
        return .init(summary: summary, reason: reason, icon: "shippingbox.fill",
                     method: framework.method, command: command, port: framework.port,
                     packageManager: pm, scripts: scripts)
    }

    private static func pick(_ name: String, _ scripts: [String: String]) -> String? {
        scripts[name] != nil ? name : nil
    }

    private static func packageManager(exists: (String) -> Bool) -> String {
        if exists("pnpm-lock.yaml") { return "pnpm" }
        if exists("yarn.lock") { return "yarn" }
        if exists("bun.lockb") { return "bun" }
        return "npm"
    }

    private static func lockfileName(exists: (String) -> Bool) -> String? {
        for name in ["pnpm-lock.yaml", "yarn.lock", "bun.lockb", "package-lock.json"] where exists(name) {
            return name
        }
        return nil
    }

    /// How to invoke a package.json script for the detected package manager.
    static func runScript(_ name: String, pm: String) -> String {
        switch pm {
        case "yarn": return "yarn \(name)"
        case "pnpm": return "pnpm \(name)"
        case "bun":  return "bun run \(name)"
        default:     return name == "start" ? "npm start" : "npm run \(name)"
        }
    }
}

// MARK: - Process classification & grouping

/// Broad buckets used to colour-code rows and warn before stopping.
enum ServerCategory: Int, Comparable {
    case dev          // your dev servers — safe to stop
    case application  // known third-party apps (Adobe, Docker, …) — caution
    case system       // macOS daemons — don't stop
    case unknown      // unclassified

    static func < (lhs: ServerCategory, rhs: ServerCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .dev:         return "Development"
        case .application: return "Application"
        case .system:      return "System"
        case .unknown:     return "Other"
        }
    }

    /// Whether stopping should require confirmation first.
    var needsStopConfirmation: Bool { self != .dev }
}

/// A run of servers that belong together (e.g. all of Adobe's ports).
struct ServerGroup: Identifiable {
    var id: String { name }
    let name: String
    let category: ServerCategory
    var servers: [RunningServer]
}

/// Maps a process name to a friendly group + a safety category.
enum ProcessClassifier {
    // Known third-party apps → (friendly group name, matching tokens).
    private static let appVendors: [(group: String, tokens: [String])] = [
        ("Adobe",          ["adobe", "creative cloud", "ccx", "coresync"]),
        ("Docker",         ["docker", "com.docke"]),
        ("Dify",           ["dify"]),
        ("Dropbox",        ["dropbox"]),
        ("Google",         ["google", "chrome"]),
        ("Spotify",        ["spotify"]),
        ("Slack",          ["slack"]),
        ("Zoom",           ["zoom"]),
        ("Ollama",         ["ollama"]),
        ("Databases",      ["postgres", "mysqld", "mariadb", "redis-server", "mongod"]),
    ]

    // Dev runtimes / tools → category .dev (grouped under "Development").
    private static let devTokens: [String] = [
        "node", "npm", "npx", "yarn", "pnpm", "bun", "deno",
        "vite", "next", "nuxt", "webpack", "rollup", "esbuild", "parcel",
        "python", "python3", "flask", "gunicorn", "uvicorn", "uwsgi", "hypercorn",
        "php", "ruby", "rails", "puma", "rackup", "unicorn",
        "java", "gradle", "dotnet", "dart", "flutter", "ng", "http-server", "serve",
        "ghost",
    ]

    // macOS system daemons → category .system.
    private static let systemTokens: [String] = [
        "controlcenter", "rapportd", "sharingd", "identityservices", "remoted",
        "mdnsresponder", "launchd", "sshd", "cupsd", "airplay", "nfsd",
        "coreaudiod", "bluetoothd", "netbiosd", "s7lord", "rapport", "wifiagent",
        "apsd", "trustd", "configd", "distnoted",
    ]

    static func classify(_ processName: String) -> (group: String, category: ServerCategory) {
        let name = processName.lowercased()

        for vendor in appVendors where vendor.tokens.contains(where: name.contains) {
            return (vendor.group, .application)
        }
        if devTokens.contains(where: { name == $0 || name.hasPrefix($0) }) {
            return ("Development", .dev)
        }
        if systemTokens.contains(where: name.contains) {
            return ("System", .system)
        }
        return (processName, .unknown)
    }

    /// Group + sort running servers for display.
    static func group(_ servers: [RunningServer]) -> [ServerGroup] {
        var buckets: [String: ServerGroup] = [:]
        for server in servers {
            let (name, category) = classify(server.processName)
            if buckets[name] == nil {
                buckets[name] = ServerGroup(name: name, category: category, servers: [])
            }
            buckets[name]?.servers.append(server)
        }
        for key in buckets.keys {
            buckets[key]?.servers.sort { $0.port < $1.port }
        }
        // Dev first, then application, system, other; alphabetical within a category.
        return buckets.values.sorted {
            $0.category != $1.category ? $0.category < $1.category : $0.name < $1.name
        }
    }
}
