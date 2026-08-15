import SwiftUI
import AppKit

struct NewServerView: View {
    @EnvironmentObject var appState: AppState

    @State private var folderPath = ""
    @State private var label = ""
    @State private var analysis: ProjectAnalysis?
    @State private var useMethod = true
    @State private var method: ServeMethod = .staticServe
    @State private var customCommand = ""
    @State private var port = "3000"
    @State private var addToFavorites = false
    @State private var launchNow = true
    @State private var statusMessage: String?

    private var portValue: Int { Int(port) ?? (useMethod ? method.defaultPort : 3000) }

    private var canCreate: Bool {
        guard !folderPath.isEmpty else { return false }
        return useMethod || !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Start a New Server").font(.title2.bold())

                GroupBox("Project Folder") {
                    HStack {
                        Image(systemName: "folder")
                        Text(folderPath.isEmpty ? "No folder selected" : folderPath)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(folderPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button(folderPath.isEmpty ? "Choose…" : "Change…") { chooseFolder() }
                    }
                    .padding(6)
                }

                if let analysis { DetectionPanel(analysis: analysis, onPickScript: usePickedScript) }

                GroupBox("How to start it") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $useMethod) {
                            Text("Built-in method").tag(true)
                            Text("Custom command").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if useMethod {
                            Picker("Method", selection: $method) {
                                ForEach(ServeMethod.allCases) { m in
                                    Text(m.displayName).tag(m)
                                }
                            }
                            .onChange(of: method) { _, newValue in port = String(newValue.defaultPort) }
                            Text("Command:  " + method.shellCommand(port: portValue))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else {
                            TextField("e.g. pnpm dev  ·  python3 manage.py runserver",
                                      text: $customCommand, axis: .vertical)
                                .lineLimit(2...4)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            Text("Runs in the project folder above.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }

                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Label").frame(width: 56, alignment: .leading)
                            TextField("My Project", text: $label)
                        }
                        HStack {
                            Text("Port").frame(width: 56, alignment: .leading)
                            TextField("3000", text: $port).frame(width: 100)
                            Spacer()
                        }
                        PortInUseNotice(port: portValue)
                        Toggle("Add to favorites", isOn: $addToFavorites)
                        Toggle("Start immediately", isOn: $launchNow)
                    }
                    .padding(6)
                }

                HStack {
                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    Button {
                        createServer()
                    } label: {
                        Label("Create Server", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                }
            }
            .padding()
        }
        .background(AppBackground())
        .onAppear { appState.refreshRunning() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        if label.isEmpty { label = url.lastPathComponent }
        statusMessage = nil

        let result = ProjectDetector.analyze(url)
        analysis = result
        applyDetection(result)
    }

    /// Apply the analyzer's recommendation to the form.
    private func applyDetection(_ result: ProjectAnalysis) {
        port = String(result.port)
        if let m = result.method {
            useMethod = true
            method = m
        } else if let command = result.command {
            useMethod = false
            customCommand = command
        }
    }

    /// User tapped one of the detected scripts.
    private func usePickedScript(_ entry: ProjectAnalysis.ScriptEntry) {
        useMethod = false
        customCommand = entry.runCommand
        if let p = entry.port { port = String(p) }
    }

    private func createServer() {
        let finalLabel = label.isEmpty
            ? URL(fileURLWithPath: folderPath).lastPathComponent
            : label
        appState.addServer(label: finalLabel, folderPath: folderPath,
                           method: useMethod ? method : nil,
                           customCommand: useMethod ? nil : customCommand,
                           port: portValue, favorite: addToFavorites, launchNow: launchNow)
        statusMessage = launchNow
            ? "Started \(finalLabel) on localhost:\(portValue)"
            : "Saved \(finalLabel)"
    }
}

// MARK: - Port availability notice

/// Shows a warning when the chosen port is already taken. Pass `isSelf` when the
/// occupant is this server's own running instance (shown as a neutral note).
struct PortInUseNotice: View {
    @EnvironmentObject var appState: AppState
    let port: Int
    var isSelf: Bool = false

    var body: some View {
        if let running = appState.runningServer(onPort: port) {
            if isSelf {
                Label("This server is currently running on port \(String(port)).",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label {
                    Text("Port \(String(port)) is already in use by \(running.processName) (PID \(String(running.pid))). Starting here will likely fail or collide.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Detection panel (shared look for the auto-detect result)

struct DetectionPanel: View {
    let analysis: ProjectAnalysis
    var onPickScript: ((ProjectAnalysis.ScriptEntry) -> Void)? = nil

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: analysis.icon)
                        .font(.title2).foregroundStyle(.tint).frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Detected: \(analysis.summary)").font(.headline)
                        Text(analysis.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let command = analysis.command {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !analysis.scripts.isEmpty, let onPickScript {
                    Divider()
                    Text(analysis.packageManager != nil ? "package.json scripts" : "start scripts")
                        .font(.caption2).foregroundStyle(.secondary)
                    FlowScripts(scripts: analysis.scripts, onPick: onPickScript)
                }
            }
            .padding(6)
        }
    }
}

/// Wrapping row of script chips.
private struct FlowScripts: View {
    let scripts: [ProjectAnalysis.ScriptEntry]
    let onPick: (ProjectAnalysis.ScriptEntry) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { chips }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(stride(from: 0, to: scripts.count, by: 3)), id: \.self) { start in
                    HStack {
                        ForEach(scripts[start..<min(start + 3, scripts.count)]) { entry in
                            chip(entry)
                        }
                    }
                }
            }
        }
    }

    private var chips: some View {
        ForEach(scripts) { entry in chip(entry) }
    }

    private func chip(_ entry: ProjectAnalysis.ScriptEntry) -> some View {
        Button { onPick(entry) } label: {
            HStack(spacing: 4) {
                if entry.backgrounds {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Text(entry.name).font(.caption.monospaced())
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .help(entry.backgrounds
              ? "\(entry.runCommand)\n⚠︎ Backgrounds & detaches — IO can start it but can't stop or show logs. Prefer a run_ script."
              : entry.runCommand)
    }
}

// MARK: - Configure / Set Up an existing saved server

struct ConfigureServerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let server: SavedServer

    @State private var label: String
    @State private var folderPath: String
    @State private var port: String
    @State private var useMethod: Bool
    @State private var method: ServeMethod
    @State private var customCommand: String
    @State private var analysis: ProjectAnalysis?

    init(server: SavedServer) {
        self.server = server
        _label = State(initialValue: server.label)
        _folderPath = State(initialValue: server.folderPath ?? "")
        _port = State(initialValue: String(server.port))
        _useMethod = State(initialValue: server.method != nil)
        _method = State(initialValue: server.method ?? .staticServe)
        _customCommand = State(initialValue: server.customCommand ?? "")
    }

    private var portValue: Int { Int(port) ?? server.port }

    private var canLaunch: Bool {
        useMethod ? !folderPath.isEmpty
                  : !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Set Up Server").font(.title2.bold())
                Text("Tell IO how to (re)start this server so you can launch it from here.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            GroupBox("Name & Port") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Label").frame(width: 56, alignment: .leading)
                        TextField("My server", text: $label)
                    }
                    HStack {
                        Text("Port").frame(width: 56, alignment: .leading)
                        TextField("3000", text: $port).frame(width: 100)
                        Spacer()
                    }
                    PortInUseNotice(port: portValue,
                                    isSelf: appState.isManagedRunning(server) && portValue == server.port)
                }.padding(6)
            }

            GroupBox("How to start it") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $useMethod) {
                        Text("Folder + method").tag(true)
                        Text("Custom command").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack {
                        Image(systemName: "folder")
                        Text(folderPath.isEmpty ? "No folder selected" : folderPath)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(folderPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button(folderPath.isEmpty ? "Choose…" : "Change…") { chooseFolder() }
                    }

                    if let analysis {
                        DetectionPanel(analysis: analysis) { entry in
                            useMethod = false
                            customCommand = entry.runCommand
                            if let p = entry.port { port = String(p) }
                        }
                    }

                    if useMethod {
                        Picker("Method", selection: $method) {
                            ForEach(ServeMethod.allCases) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        Text("Command:  " + method.shellCommand(port: portValue))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Shell command (runs in the folder above, or your home folder):")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("e.g. npm run dev  ·  python3 -m http.server 8000",
                                  text: $customCommand, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                }.padding(6)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(start: false) }
                Button("Save & Start") { save(start: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canLaunch)
            }
        }
        .padding()
        .frame(width: 540)
        .onAppear { appState.refreshRunning() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !folderPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: folderPath) }
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            let result = ProjectDetector.analyze(url)
            analysis = result
            port = String(result.port)
            if let m = result.method {
                useMethod = true
                method = m
            } else if let command = result.command {
                useMethod = false
                customCommand = command
            }
        }
    }

    private func save(start: Bool) {
        let updated = appState.configure(
            server,
            label: label,
            folderPath: folderPath.isEmpty ? nil : folderPath,
            method: useMethod ? method : nil,
            customCommand: useMethod ? nil : customCommand,
            port: portValue
        )
        if start { appState.launch(updated) }
        dismiss()
    }
}
