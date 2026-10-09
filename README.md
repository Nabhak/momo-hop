<p align="center">
  <img src="assets/icon.png" width="128" alt="Momo Hop icon">
</p>

<h1 align="center">Momo Hop</h1>

<p align="center">
  Hop into any project in one click.<br>
  A small native Mac app that lists your project folders and opens the one you pick in your terminal or editor, already running your AI coding tool.
</p>

---

## Why

You work on many projects and use more than one AI coding tool. Getting back into a project usually means: open a terminal, `cd` somewhere, remember which tool you used there, type its command, maybe resume the last chat.

Momo Hop turns that into: **pick a project, press Enter.**

```
Open  with [Claude ▾]  in [Ghostty ▾]  and [continue last chat ▾]        [ Open ]
```

## Features

- **One list for all your AI tools.** Projects come from the history of Claude Code, Codex, Gemini CLI, OpenCode, Aider and Cursor. Each row shows which tools you used there and when.
- **Also lists folders you have never opened with an AI**, so you can start fresh anywhere.
- **Open it where you like.** Terminal, Ghostty, Alacritty, or an app: VS Code, Cursor, Windsurf, Zed, Sublime Text, Nova, Xcode, the Codex desktop app.
- **Picks up where you left off.** Continue the last chat, or ask for a short recap of the last session, or start a new chat.
- **Remembers your choices** (tool, destination, mode) for next time.
- **Only shows what you have.** Tools and apps that are not installed on your Mac are hidden. Nothing to configure.
- **Private.** Everything is read locally. No network access, no accounts, no analytics.

## Supported tools

| Tool | Shows history | Launch | Continue last chat | Recap |
|---|:-:|:-:|:-:|:-:|
| [Claude Code](https://docs.claude.com/en/docs/claude-code) | ✅ | ✅ | ✅ | ✅ |
| [Codex CLI](https://github.com/openai/codex) | ✅ | ✅ | ✅ | – |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | ✅ | ✅ | – | – |
| [OpenCode](https://opencode.ai) | ✅ ¹ | ✅ | ✅ | – |
| [Aider](https://aider.chat) | ✅ | ✅ | ✅ | – |
| Cursor | ✅ | open as app | – | – |

¹ OpenCode's on-disk format is read on a best-effort basis; if it changes, the OpenCode badge simply won't appear.

**Open in app:** VS Code, Cursor, Windsurf, Zed, Sublime Text, Nova, Xcode, Codex desktop app.
Claude Desktop cannot open a given folder from outside today ([anthropics/claude-code#54614](https://github.com/anthropics/claude-code/issues/54614)).

**Terminals:** Ghostty (new tab in your front window), Terminal and Alacritty (new window).

## Install

Requires macOS 14 or later. Apple Silicon and Intel.

### Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). No Xcode project, no dependencies.

```bash
git clone https://github.com/Nabhak/momo-hop.git
cd momo-hop
./build.sh
```

This builds a universal app to `~/Applications/Momo Hop.app` and a zip at `dist/Momo-Hop.zip`.

### Using a zip on another Mac

The app is ad-hoc signed, not notarized. macOS will block it the first time. After moving it to `/Applications`:

```bash
xattr -dr com.apple.quarantine "/Applications/Momo Hop.app"
```

or open **System Settings → Privacy & Security → Open Anyway**.

## Usage

1. Open Momo Hop. Type to filter the list.
2. Select a project. Double-click it or press Enter to open with your last settings.
3. Change the bar at the bottom to open it differently: another AI tool (**with**), another terminal or app (**in**), a different start (**and**).

Add projects that are not listed with the **＋** button:

- **Add project…** adds one folder.
- **Add folder of projects…** adds a folder whose sub-folders are all projects.

Folders are also found automatically in `~/Documents/GitHub`, `~/GitHub`, `~/Developer`, `~/Projects`, `~/Code`, `~/dev`, `~/src`, `~/repos` and `~/Sites`.

### Recap

For Claude, "recap last session" continues the last chat and asks Claude to summarise where you left off. If you have your own `/recall` skill in `~/.claude/skills/recall`, that is used instead.

## How it works

- Reads each tool's own history files to learn which folders you used it in (`~/.claude/projects`, `~/.codex/sessions`, `~/.gemini/projects.json`, `~/.local/share/opencode`, `.aider.chat.history.md`, Cursor's recent workspaces).
- Writes a small temporary launch script and opens it in the terminal you chose, so folder names are never pasted into a shell command.
- For Ghostty it uses AppleScript to add a tab; for Terminal and Alacritty it opens a window.

## Permissions

macOS may ask for:

- **Automation → Ghostty**, to open a tab (only if you use Ghostty).
- **Documents folder**, to list projects in `~/Documents`.

Because the app is ad-hoc signed, each rebuilt version is a new app to macOS and may ask again.

## Known limits

- History formats are internal to each tool and may change. The app fails quietly: a missing badge, never a crash.
- A custom `CLAUDE_CONFIG_DIR` is not visible to GUI apps; only `~/.claude` is read.
- Terminal and Alacritty open a new window, not a tab (neither can be scripted to add one without extra permissions).
- Tested on macOS 26 on Apple Silicon. Intel, older macOS, and the less common terminals/editors are untested.

## Development

```bash
./build.sh                                                         # build + install + zip
"$HOME/Applications/Momo Hop.app/Contents/MacOS/MomoHop" --dump    # print the project list and exit
swiftc -o /tmp/mkicon make-icon.swift && /tmp/mkicon /tmp/AppIcon.iconset   # redraw the icon PNGs
```

The whole app is one file, `main.swift`. To add an AI tool: add a case to `AI`, a history reader in `Backend`, and a launch command in `Launcher.command`.

## Disclaimer

Momo Hop is an independent project. It is not affiliated with or endorsed by Anthropic, OpenAI, Google, Cursor, or any other tool it works with. Product names belong to their owners.

## License

[MIT](LICENSE)
