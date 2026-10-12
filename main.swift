// Momo Hop: one-click project launcher for macOS.
// Copyright (C) 2026 Nabhak <https://github.com/Nabhak/momo-hop>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see the
// GNU General Public License (LICENSE) for details. Derivative works must keep this notice.

import SwiftUI
import AppKit
import SQLite3

// Momo Hop: list project folders on this Mac, open one in Terminal/Ghostty running an AI CLI (claude/codex/gemini).
// Self-contained: no python, no hardcoded paths. History: Claude Code (~/.claude/projects), Codex (~/.codex/sessions),
// Gemini CLI (~/.gemini/projects.json), OpenCode (~/.local/share/opencode), Aider (.aider.chat.history.md), Cursor (recent workspaces).

let home = NSHomeDirectory()
let fm = FileManager.default

func isDir(_ p: String) -> Bool {
    var d: ObjCBool = false
    return fm.fileExists(atPath: p, isDirectory: &d) && d.boolValue
}
func mtime(_ p: String) -> Date {
    ((try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date) ?? .distantPast
}
func real(_ p: String) -> String { URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
func shortPath(_ p: String) -> String {
    p == home ? "~" : p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p
}
/// Same folder-name scheme Claude Code uses under ~/.claude/projects.
func slug(_ p: String) -> String {
    String(String.UnicodeScalarView(p.unicodeScalars.map {
        ($0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-")) ? $0 : "-"
    }))
}
func runCapture(_ exe: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

enum AI: String, CaseIterable, Identifiable, Hashable {
    case claude = "Claude", codex = "Codex", gemini = "Gemini", opencode = "OpenCode", aider = "Aider", cursor = "Cursor"
    var id: String { rawValue }
    /// CLI name when the tool can be launched from a terminal (Cursor is history-only).
    var cli: String? { self == .cursor ? nil : rawValue.lowercased() }
    static var launchable: [AI] { allCases.filter { $0.cli != nil } }
}

struct Project: Identifiable, Hashable {
    let path: String
    let lastActive: Date
    let liveTools: Set<AI>  // AI tools running here right now (only claude/codex are detectable)
    let used: [AI: Date]  // AI tools that have worked in this folder
    var live: Bool { !liveTools.isEmpty }
    var seen: Bool { !used.isEmpty }
    var id: String { path }
    var name: String { path == home ? "~" : URL(fileURLWithPath: path).lastPathComponent }
    var folder: String { shortPath(path) }
}

// MARK: - finding projects
enum Backend {
    static let markers = [".git", "CLAUDE.md", "package.json", "Package.swift", "pyproject.toml", "Cargo.toml", "go.mod"]
    /// Folders whose children are all projects (when the folder exists). Desktop/Documents roots are not scanned:
    /// they trigger macOS permission prompts; use "Add folder…" or history instead.
    static let containers = ["Documents/GitHub", "GitHub", "Developer", "Projects", "Code", "code", "dev", "src", "repos", "Sites"]

    static func isJunk(_ cwd: String) -> Bool {
        cwd == "/" || cwd.hasPrefix("/tmp/") || cwd.hasPrefix("/private/tmp/") || cwd.hasPrefix("/private/var/")
            || cwd.hasPrefix(home + "/.claude/projects")
    }

    static func hasMarker(_ d: String) -> Bool {
        markers.contains { fm.fileExists(atPath: d + "/" + $0) }
            || ((try? fm.contentsOfDirectory(atPath: d)) ?? []).contains { $0.hasSuffix(".xcodeproj") }
    }

    /// Topmost folder at/above cwd (below $HOME) that looks like a project; else cwd.
    static func projectRoot(_ cwd: String) -> String {
        var root = cwd
        var cur = (cwd as NSString).deletingLastPathComponent
        while cur.hasPrefix(home + "/") {
            if fm.fileExists(atPath: cur + "/.git") || fm.fileExists(atPath: cur + "/CLAUDE.md") { root = cur }
            cur = (cur as NSString).deletingLastPathComponent
        }
        return root
    }

    static let cwdRegex = try! NSRegularExpression(pattern: #""cwd":\s*"((?:[^"\\]|\\.)*)""#)

    /// {cwd: last transcript time} from ~/.claude/projects/*/*.jsonl.
    static func transcriptCwds() -> [String: Date] {
        let base = home + "/.claude/projects"
        var found: [String: Date] = [:]
        for d in (try? fm.contentsOfDirectory(atPath: base)) ?? [] {
            let dir = base + "/" + d
            let files = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".jsonl") }
            guard let newest = files.map({ ($0, mtime(dir + "/" + $0)) }).max(by: { $0.1 < $1.1 }),
                  let fh = FileHandle(forReadingAtPath: dir + "/" + newest.0) else { continue }
            let data = (try? fh.read(upToCount: 262_144)) ?? Data()
            try? fh.close()
            let text = String(decoding: data, as: UTF8.self)
            let ns = text as NSString
            for m in cwdRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: m.range(at: 1))
                guard let cwd = (try? JSONSerialization.jsonObject(with: Data(("\"" + raw + "\"").utf8),
                                                                    options: .fragmentsAllowed)) as? String,
                      slug(cwd) == d else { continue }  // session started here (later cwd may drift)
                found[cwd] = max(found[cwd] ?? .distantPast, newest.1)
                break
            }
        }
        return found
    }

    static func rec(_ out: inout [String: Date], _ cwd: String, _ d: Date) {
        if !isJunk(cwd) && isDir(cwd) { out[cwd] = max(out[cwd] ?? .distantPast, d) }
    }

    /// Codex CLI: first line of ~/.codex/sessions/**/rollout-*.jsonl carries the session cwd.
    static func codexCwds() -> [String: Date] {
        var files: [(String, Date)] = []
        let base = home + "/.codex/sessions"
        if let en = fm.enumerator(atPath: base) {
            for case let rel as String in en where rel.hasSuffix(".jsonl") { files.append((base + "/" + rel, mtime(base + "/" + rel))) }
        }
        files.sort { $0.1 > $1.1 }
        let re = try! NSRegularExpression(pattern: #""cwd":\s*"((?:[^"\\]|\\.)*)""#)
        var found: [String: Date] = [:]
        for (path, d) in files.prefix(1500) {
            guard let fh = FileHandle(forReadingAtPath: path) else { continue }
            let text = String(decoding: (try? fh.read(upToCount: 4096)) ?? Data(), as: UTF8.self)
            try? fh.close()
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               let cwd = (try? JSONSerialization.jsonObject(with: Data(("\"" + ns.substring(with: m.range(at: 1)) + "\"").utf8),
                                                             options: .fragmentsAllowed)) as? String {
                rec(&found, cwd, d)
            }
        }
        return found
    }

    /// Gemini CLI: ~/.gemini/projects.json maps folder path -> short name (state in ~/.gemini/tmp/<name>).
    static func geminiCwds() -> [String: Date] {
        var found: [String: Date] = [:]
        guard let data = fm.contents(atPath: home + "/.gemini/projects.json"),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let map = obj["projects"] as? [String: String] else { return found }
        for (cwd, name) in map {
            let t = mtime(home + "/.gemini/tmp/" + name)
            rec(&found, cwd, t == .distantPast ? mtime(home + "/.gemini/projects.json") : t)
        }
        return found
    }

    /// OpenCode: per-project JSON (older builds) and/or SQLite (newer builds). Schema not verified on every version:
    /// every step fails silently, so a mismatch just means "no OpenCode history shown".
    static func openCodeCwds() -> [String: Date] {
        var found: [String: Date] = [:]
        let base = home + "/.local/share/opencode"
        let pdir = base + "/storage/project"
        for n in (try? fm.contentsOfDirectory(atPath: pdir)) ?? [] where n.hasSuffix(".json") {
            guard let data = fm.contents(atPath: pdir + "/" + n),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let wt = o["worktree"] as? String else { continue }
            var t = mtime(pdir + "/" + n)
            if let tm = o["time"] as? [String: Any], let u = tm["updated"] as? Double { t = Date(timeIntervalSince1970: u / 1000) }
            rec(&found, wt, t)
        }
        var db: OpaquePointer?
        if fm.fileExists(atPath: base + "/opencode.db"), sqlite3_open_v2(base + "/opencode.db", &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT directory, MAX(time_updated) FROM session GROUP BY directory", -1, &st, nil) == SQLITE_OK {
                while sqlite3_step(st) == SQLITE_ROW {
                    if let c = sqlite3_column_text(st, 0) {
                        rec(&found, String(cString: c), Date(timeIntervalSince1970: Double(sqlite3_column_int64(st, 1)) / 1000))
                    }
                }
            }
            sqlite3_finalize(st)
        }
        sqlite3_close(db)
        return found
    }

    /// Cursor: recent workspaces recorded in its storage.json as file:// URIs.
    static func cursorCwds() -> [String: Date] {
        var found: [String: Date] = [:]
        guard let data = fm.contents(atPath: home + "/Library/Application Support/Cursor/User/globalStorage/storage.json") else { return found }
        let text = String(decoding: data, as: UTF8.self)
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: #""file://(/[^"]*)""#)
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let path = ns.substring(with: m.range(at: 1)).removingPercentEncoding, isDir(path) else { continue }
            rec(&found, path, mtime(path))
        }
        return found
    }

    /// Which AI CLIs exist on this Mac (asks the user's login shell once, since GUI apps lack the shell PATH).
    static func installedTools() -> Set<AI> {
        let sh = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shell = (sh.hasSuffix("/zsh") || sh.hasSuffix("/bash")) ? sh : "/bin/zsh"
        let names = AI.launchable.compactMap(\.cli)
        let out = runCapture(shell, ["-ilc", "for c in \(names.joined(separator: " ")); do command -v $c; done"])
        var found = Set<AI>()
        for line in out.split(separator: "\n") where line.hasPrefix("/") {
            if let ai = AI.launchable.first(where: { $0.cli == (String(line) as NSString).lastPathComponent }) { found.insert(ai) }
        }
        return found
    }

    /// Project roots that have an interactive claude/codex running right now, with which of the two.
    static func liveRoots() -> [String: Set<AI>] {
        let detectable: [String: AI] = ["claude": .claude, "codex": .codex]
        var tools: [String: AI] = [:]  // pid -> tool
        for line in runCapture("/bin/ps", ["-axo", "pid=,tty=,comm="]).split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if f.count == 3, f[1].hasPrefix("ttys"),
               let ai = detectable[(String(f[2]).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent] { tools[String(f[0])] = ai }
        }
        if tools.isEmpty { return [:] }
        var roots: [String: Set<AI>] = [:]
        var cur: AI?  // lsof -F prints a "p<pid>" line before each process's "n<path>" line
        for line in runCapture("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", tools.keys.joined(separator: ","), "-Fpn"]).split(separator: "\n") {
            if line.hasPrefix("p") { cur = tools[String(line.dropFirst())] }
            else if line.hasPrefix("n/"), let ai = cur { roots[real(projectRoot(String(line.dropFirst()))), default: []].insert(ai) }
        }
        return roots
    }

    static func scanFolders(extraRoots: [String]) -> [(String, Date)] {
        var out: [(String, Date)] = []
        func scan(_ base: String, needMarker: Bool) {
            guard isDir(base) else { return }
            for n in ((try? fm.contentsOfDirectory(atPath: base)) ?? []).sorted() {
                let d = base + "/" + n
                if n.hasPrefix(".") || n == "node_modules" || !isDir(d) { continue }
                if needMarker && !hasMarker(d) { continue }
                out.append((d, mtime(d)))
            }
        }
        for c in containers { scan(home + "/" + c, needMarker: false) }
        for e in extraRoots {
            if e.hasPrefix("P:") {  // a single project added by hand
                let d = String(e.dropFirst(2))
                if isDir(d) { out.append((d, mtime(d))) }
            } else {  // a folder that contains projects
                scan(e, needMarker: false)
                if hasMarker(e) { out.append((e, mtime(e))) }
            }
        }
        return out
    }

    static func load(extraRoots: [String]) -> [Project] {
        var roots: [String: (last: Date, used: [AI: Date])] = [:]
        let sources: [(AI, [String: Date])] = [(.claude, transcriptCwds()), (.codex, codexCwds()),
                                               (.gemini, geminiCwds()), (.opencode, openCodeCwds()), (.cursor, cursorCwds())]
        for (ai, cwds) in sources {
            for (cwd, d) in cwds where !isJunk(cwd) && isDir(cwd) {
                let r = projectRoot(cwd)
                var e = roots[r] ?? (.distantPast, [:])
                e.last = max(e.last, d)
                e.used[ai] = max(e.used[ai] ?? .distantPast, d)
                roots[r] = e
            }
        }
        let live = liveRoots()
        var rows = roots.map { Project(path: $0.key, lastActive: $0.value.last, liveTools: live[real($0.key)] ?? [], used: $0.value.used) }
        var known = Set(rows.map { real($0.path) })
        for (d, m) in scanFolders(extraRoots: extraRoots) where !known.contains(real(d)) {
            known.insert(real(d))
            rows.append(Project(path: d, lastActive: m, liveTools: [], used: [:]))
        }
        rows = rows.map { r in  // Aider keeps its history inside the repo
            let f = r.path + "/.aider.chat.history.md"
            guard fm.fileExists(atPath: f) else { return r }
            var u = r.used
            let t = mtime(f)
            u[.aider] = t
            return Project(path: r.path, lastActive: r.seen ? max(r.lastActive, t) : t, liveTools: r.liveTools, used: u)
        }
        rows.sort { ($0.seen ? 1 : 0, $0.lastActive) > ($1.seen ? 1 : 0, $1.lastActive) }
        return rows
    }
}

// MARK: - opening
enum Mode: String, CaseIterable, Identifiable {
    case recall = "Recall", resume = "Continue", fresh = "New"
    var id: String { rawValue }
    /// Wording used in the sentence bar: "Open with Claude in Ghostty, <label>".
    var label: String {
        switch self { case .recall: return "recap last session"; case .resume: return "continue last chat"; case .fresh: return "start a new chat" }
    }
    /// Modes a tool supports. Recap works for everyone on Claude: the owner's /recall skill when present, else a plain prompt.
    static func available(for ai: AI) -> [Mode] {
        switch ai {
        case .claude: return [.recall, .resume, .fresh]
        case .codex, .opencode, .aider: return [.resume, .fresh]
        default: return [.fresh]
        }
    }
}

enum TermApp: String, CaseIterable, Identifiable {
    case ghostty = "Ghostty", terminal = "Terminal", alacritty = "Alacritty"
    var id: String { rawValue }
    var bundleID: String {
        switch self {
        case .ghostty: return "com.mitchellh.ghostty"
        case .terminal: return "com.apple.Terminal"
        case .alacritty: return "org.alacritty"
        }
    }
    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    static var available: [TermApp] { allCases.filter { $0.url != nil } }
}

/// Apps that can open a folder: code editors, plus the Codex desktop app (via its codex:// deep link).
/// Detected by bundle id; only installed ones are shown.
enum Editor: String, CaseIterable, Identifiable {
    case vscode = "VS Code", cursor = "Cursor", windsurf = "Windsurf", zed = "Zed", sublime = "Sublime Text", nova = "Nova", xcode = "Xcode",
         codexApp = "Codex app"
    var id: String { rawValue }
    var bundleID: String {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .windsurf: return "com.exafunction.windsurf"
        case .zed: return "dev.zed.Zed"
        case .sublime: return "com.sublimetext.4"
        case .nova: return "com.panic.Nova"
        case .xcode: return "com.apple.dt.Xcode"
        case .codexApp: return "com.openai.codex"
        }
    }
    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    static var available: [Editor] { allCases.filter { $0.url != nil } }
}

enum Launcher {
    static func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func asq(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    static func hasClaudeHistory(_ path: String) -> Bool {
        let dir = home + "/.claude/projects/" + slug(path)
        return ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).contains { $0.hasSuffix(".jsonl") }
    }

    /// Command line for tool+mode; falls back to a fresh session when there is nothing to continue.
    static func command(_ p: Project, ai: AI, mode: Mode) -> String {
        guard let cli = ai.cli else { return "" }
        switch (ai, mode) {
        case (.claude, .recall) where hasClaudeHistory(p.path):
            if fm.fileExists(atPath: home + "/.claude/skills/recall") { return "claude " + shq("/recall") }  // owner's own skill
            return "claude --continue " + shq("Summarize where we left off in this project: what was done, what is unfinished, and the suggested next step. Keep it short.")
        case (.claude, .resume) where hasClaudeHistory(p.path): return "claude --continue"
        case (.codex, .resume) where p.used[.codex] != nil: return "codex resume --last"
        case (.opencode, .resume) where p.used[.opencode] != nil: return "opencode --continue"
        case (.aider, .resume) where p.used[.aider] != nil: return "aider --restore-chat-history"
        default: return cli
        }
    }

    /// Opens the folder in a terminal running the tool. Returns an error message, or nil on success.
    /// The command goes into a temp .command script, so no folder name is ever pasted into AppleScript or a shell string.
    static func open(_ p: Project, ai: AI, mode: Mode, app: TermApp) -> String? {
        guard let termURL = app.url else { return "\(app.rawValue) is not installed." }
        let cmd = command(p, ai: ai, mode: mode)
        let tool = ai.cli ?? "claude"
        let script = """
        #!/bin/zsh -li
        cd \(shq(p.path)) || exit 1
        printf '\\033]0;%s\\007' \(shq(p.name))
        if command -v \(tool) >/dev/null 2>&1; then
          \(cmd)
        else
          echo "\(tool) is not installed or not on your PATH."
        fi
        exec "${SHELL:-/bin/zsh}" -l

        """
        let file = NSTemporaryDirectory() + "momo-hop-" + UUID().uuidString + ".command"
        do {
            try script.write(toFile: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file)
        } catch { return "Could not prepare the launch script: \(error.localizedDescription)" }

        switch app {
        case .terminal:
            NSWorkspace.shared.open([URL(fileURLWithPath: file)], withApplicationAt: termURL, configuration: NSWorkspace.OpenConfiguration())
            return nil
        case .alacritty:  // always a new window: Alacritty has no tabs
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p2.arguments = ["-n", "-a", termURL.path, "--args", "--working-directory", p.path, "--title", p.name, "-e", file]
            do { try p2.run() } catch { return "Could not start Alacritty: \(error.localizedDescription)" }
            return nil
        case .ghostty:
            let cfg = "{initial working directory:\(asq(p.path)), command:\(asq(file))}"
            let title = asq("set_tab_title:" + p.name)
            let src = """
            tell application "Ghostty"
              if (count of windows) > 0 then
                set t to new tab in front window with configuration \(cfg)
                perform action \(title) on (focused terminal of t)
              else
                set w to new window with configuration \(cfg)
                perform action \(title) on (focused terminal of (selected tab of w))
              end if
              activate
            end tell
            """
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
            guard let err else { return nil }
            if (err[NSAppleScript.errorNumber] as? Int) == -1743 {
                return "Allow Momo Hop to control Ghostty: System Settings → Privacy & Security → Automation. Or pick Terminal."
            }
            return (err[NSAppleScript.errorMessage] as? String) ?? "Could not control Ghostty. Try Terminal."
        }
    }

    /// Temp launch scripts older than a day are leftovers.
    static func sweepTemp() {
        let dir = NSTemporaryDirectory()
        for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where n.hasPrefix("momo-hop-") && n.hasSuffix(".command") {
            if Date().timeIntervalSince(mtime(dir + n)) > 86_400 { try? fm.removeItem(atPath: dir + n) }
        }
    }
}

// MARK: - UI
let accent = Color(red: 0.94, green: 0.38, blue: 0.23)  // matches the app icon

@MainActor
final class Model: ObservableObject {
    @Published var projects: [Project] = []
    @Published var tools: [AI] = [.claude]
    @Published var error: String?
    @Published var loading = true

    func load(extraRoots: [String]) {
        loading = true
        Task.detached {
            let list = Backend.load(extraRoots: extraRoots)
            await MainActor.run { self.projects = list; self.loading = false }
        }
    }

    func probeTools() {
        Task.detached {
            let found = Backend.installedTools()
            await MainActor.run { let l = AI.launchable.filter(found.contains); if !l.isEmpty { self.tools = l } }
        }
    }

    func openEditor(_ p: Project, editor: Editor) {
        guard let url = editor.url else { error = "\(editor.rawValue) is not installed."; return }
        if editor == .codexApp {  // documented deep link: new chat in that workspace
            let enc = p.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? p.path
            if let link = URL(string: "codex://threads/new?path=" + enc) { NSWorkspace.shared.open(link); NSApp.terminate(nil) }
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: p.path)], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration()) { _, err in
            DispatchQueue.main.async {
                if let err { self.error = "Could not open \(editor.rawValue): \(err.localizedDescription)" } else { NSApp.terminate(nil) }
            }
        }
    }

    func open(_ p: Project, ai: AI, mode: Mode, app: TermApp) {
        if let e = Launcher.open(p, ai: ai, mode: mode, app: app) { error = e } else { NSApp.terminate(nil) }
    }
}

/// "Running" pill: green dot + label on a faint green capsule, same size family as the tool tags.
/// On a selected row (accent highlight behind) it turns into a translucent white pill with white text, like the tags.
struct RunningBadge: View {
    let tools: Set<AI>
    @Environment(\.backgroundProminence) private var prominence
    var body: some View {
        let onAccent = prominence == .increased
        let ink = Color(nsColor: .alternateSelectedControlTextColor)
        HStack(spacing: 4) {
            Circle().fill(.green).frame(width: 6, height: 6)
                .background { if onAccent { Circle().fill(ink).padding(-1) } }  // white rim keeps the green dot visible on blue
            Text("Running")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(onAccent ? AnyShapeStyle(ink) : AnyShapeStyle(Color.primary))
        .padding(.leading, 5).padding(.trailing, 7).padding(.vertical, 2)
        .background(onAccent ? AnyShapeStyle(ink.opacity(0.22)) : AnyShapeStyle(.green.opacity(0.16)), in: Capsule())
        .help(tools.map(\.rawValue).sorted().joined(separator: " and ") + " running in this folder")
    }
}

struct Row: View {
    let p: Project
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.name).font(.headline)
                    ForEach(AI.allCases.filter { p.used[$0] != nil }) { ai in
                        Text(ai.rawValue).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(p.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if p.live { RunningBadge(tools: p.liveTools) }
            Group {
                if p.seen { Text(p.lastActive, format: .relative(presentation: .named)) } else { Text("not opened yet") }
            }
            .font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        // Pin the row separator to the full row width. Without this, the "running" label shifts it to start at the status column.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
    }
}

/// Where "Open" sends the folder: a terminal (runs the AI tool) or an app (editor / Codex desktop).
enum Dest: Hashable, Identifiable {
    case term(TermApp), app(Editor)
    var id: String {
        switch self { case .term(let t): return "term:" + t.rawValue; case .app(let e): return "app:" + e.rawValue }
    }
    var label: String {
        switch self { case .term(let t): return t.rawValue; case .app(let e): return e.rawValue }
    }
}

struct ContentView: View {
    @StateObject private var m = Model()
    @State private var query = ""
    @State private var sel: Set<String> = []
    @AppStorage("tool") private var toolRaw = ""
    @AppStorage("mode") private var modeRaw = ""
    @AppStorage("dest") private var destRaw = ""  // last destination used; "termApp" is the pre-1.1 key
    @AppStorage("termApp") private var termRaw = ""
    @AppStorage("extraRoots") private var extraJSON = "[]"

    var tool: AI { m.tools.first { $0.rawValue == toolRaw } ?? m.tools[0] }
    var modes: [Mode] { Mode.available(for: tool) }
    var mode: Mode { modes.first { $0.rawValue == modeRaw } ?? modes[0] }
    var termDests: [Dest] { (TermApp.available.isEmpty ? [.terminal] : TermApp.available).map(Dest.term) }
    var appDests: [Dest] { Editor.available.map(Dest.app) }
    var dest: Dest {
        let all = termDests + appDests
        return all.first { $0.id == destRaw } ?? all.first { $0.id == "term:" + termRaw } ?? all[0]
    }
    var isTerminal: Bool { if case .term = dest { return true } else { return false } }
    var extraRoots: [String] { (try? JSONDecoder().decode([String].self, from: Data(extraJSON.utf8))) ?? [] }
    func setExtra(_ list: [String]) {
        extraJSON = String(decoding: (try? JSONEncoder().encode(list)) ?? Data("[]".utf8), as: UTF8.self)
        m.load(extraRoots: list)
    }

    var filtered: [Project] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? m.projects : m.projects.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q) }
    }
    var selected: Project? { m.projects.first { sel.contains($0.id) } }
    var hint: String {
        if !isTerminal { return "Opens the folder in \(dest.label)." }
        if let p = selected, mode != .fresh, Launcher.command(p, ai: tool, mode: mode) == tool.cli {
            return "No earlier \(tool.rawValue) session here: starts a clean one."
        }
        switch mode {
        case .recall: return "Open \(tool.rawValue) and summarise where the last session stopped."
        case .resume: return "Resume the last \(tool.rawValue) conversation in that folder."
        case .fresh: return "Start a clean \(tool.rawValue) session."
        }
    }

    /// True when the chosen tool already runs in this project (terminal opens only): Open is held back until "Open anyway".
    func isGuarded(_ p: Project) -> Bool { isTerminal && p.liveTools.contains(tool) }

    func openSelected(_ ids: Set<String>, anyway: Bool = false) {
        guard let p = m.projects.first(where: { ids.contains($0.id) }), anyway || !isGuarded(p) else { return }
        switch dest {
        case .term(let t): m.open(p, ai: tool, mode: mode, app: t)
        case .app(let e): m.openEditor(p, editor: e)
        }
    }
    func addFolder(single: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        panel.message = single ? "Choose a project folder." : "Choose a folder that contains your projects."
        guard panel.runModal() == .OK, let u = panel.url else { return }
        let entry = (single ? "P:" : "") + u.path
        if !extraRoots.contains(entry) { setExtra(extraRoots + [entry]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. find
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search projects", text: $query).textFieldStyle(.plain)
                }
                .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                Menu {
                    Button("Add project…") { addFolder(single: true) }
                    Button("Add folder of projects…") { addFolder(single: false) }
                    ForEach(extraRoots, id: \.self) { r in
                        Button("Remove \(shortPath(r.hasPrefix("P:") ? String(r.dropFirst(2)) : r))") { setExtra(extraRoots.filter { $0 != r }) }
                    }
                    Divider()
                    Button("Reload list") { m.load(extraRoots: extraRoots) }
                } label: { Image(systemName: "plus.circle").font(.title3) }
                .menuStyle(.borderlessButton).fixedSize().help("Add a project or folder")
            }
            .padding(12)
            Divider()
            if let e = m.error {
                Text(e).font(.caption).foregroundStyle(.red).padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            // 2. pick
            List(selection: $sel) {
                Section("Recent") { ForEach(filtered.filter(\.seen)) { Row(p: $0) } }
                Section("Other folders") { ForEach(filtered.filter { !$0.seen }) { Row(p: $0) } }
            }
            .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { openSelected($0) }
            .overlay {
                if m.loading { ProgressView() }
                else if m.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No projects found", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Add the folder where you keep your projects.")
                    } actions: {
                        Button("Add project…") { addFolder(single: true) }
                        Button("Add folder of projects…") { addFolder(single: false) }
                    }
                }
            }
            Divider()
            // 3. open: one sentence, read left to right
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Open")
                    if isTerminal && m.tools.count > 1 {
                        Text("with")
                        Picker("", selection: Binding(get: { tool }, set: { toolRaw = $0.rawValue })) {
                            ForEach(m.tools) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    if termDests.count + appDests.count > 1 {
                        Text("in")
                        Picker("", selection: Binding(get: { dest }, set: { destRaw = $0.id })) {
                            Section("Terminal") { ForEach(termDests) { Text($0.label).tag($0) } }
                            if !appDests.isEmpty { Section("App") { ForEach(appDests) { Text($0.label).tag($0) } } }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    if isTerminal && modes.count > 1 {
                        Text("and")
                        Picker("", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                            ForEach(modes) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    Spacer()
                    Button("Open") { openSelected(sel) }
                        .keyboardShortcut(.defaultAction).controlSize(.large).disabled(sel.isEmpty || selected.map(isGuarded) == true)
                }
                if let p = selected, isGuarded(p) {
                    HStack(spacing: 6) {
                        Text("\(tool.rawValue) is already running here.").foregroundStyle(.orange)
                        Button("Open anyway") { openSelected(sel, anyway: true) }.buttonStyle(.link)
                    }
                    .font(.caption)
                } else {
                    Text(sel.isEmpty ? "Select a project above." : hint).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 480)
        .tint(accent)
        .task {
            Launcher.sweepTemp()
            m.probeTools()
            m.load(extraRoots: extraRoots)
        }
    }
}

@main
struct MomoHopApp: App {
    init() {
        if CommandLine.arguments.contains("--dump") {  // debug: print what the list would contain, then quit
            let df = ISO8601DateFormatter()
            for p in Backend.load(extraRoots: []) {
                print(p.seen ? "seen " : "new  ", df.string(from: p.lastActive), p.live ? "LIVE(" + p.liveTools.map(\.rawValue).sorted().joined(separator: ",") + ")" : "    ", p.used.keys.map(\.rawValue).sorted().joined(separator: ","), p.folder)
            }
            print("tools:", Backend.installedTools().map(\.rawValue).sorted())
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Momo Hop") { ContentView() }
            .windowResizability(.contentMinSize)
            .defaultSize(width: 700, height: 560)
    }
}
