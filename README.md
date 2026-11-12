# Unnamed Manager

A keyboard manager for macOS that lives in the menu bar. It grew out of [Unnamed Launcher](https://github.com/juyanith/unnamed-launcher), and window actions (focus, place, move, resize, maximize, minimize) are on the way. Press a leader chord such as Hyper+Space, then one key per menu level, to open apps, files and URLs, run commands, or send shortcuts to the app in front.

If you finish the sequence quickly, nothing appears on screen. If you pause, a small HUD shows where you are and which keys come next. The app in front never loses focus.

## Features

- **Leader chords and menus.** Bindings form a tree with as many levels as you need. Back (Backspace) goes up a level and Cancel (Escape) ends the sequence. You can have as many leaders as you like.
- **Direct bindings.** A chord such as Hyper+T can run an action on its own, with no menu and no HUD.
- **Actions:**
  - **Use Application** focuses an app, starts it, or does whichever fits (the default). Focusing returns to the app's last focused window.
  - **Open** opens a file, folder or URL.
  - **Run Command** runs a process directly, with no shell.
  - **Send Shortcut** sends key chords to the app in front.
  - **Context Aware** picks a different action depending on which app is in front.
  - **Do Nothing.**
  - **Show Help** opens the Help page. The starter config puts it on Hyper+H.
- **Icons in the Guide:** menus show the app's keycaps, apps and Open targets show their own icon, and any entry can have an SF Symbol or a file's icon of its own.
- **A Bindings window** to edit menus, bindings, actions and contexts, record chords, and reorder items. Its Help page lists your leaders and direct bindings and how sequences work (Help in the menu bar menu, or a Show Help binding).
- **One JSON config file** at `~/.config/unnamed-manager/config.json`. The app watches it and reloads it when it changes, so you can keep it in your dotfiles. A config with errors is reported, and the last valid one stays in use.
- **A menu bar menu** to turn the launcher on or off, reload the config, check permissions, and see the last error.

## Requirements

- macOS 27 or later.
- Swift 6.2 or later (the Xcode 27 command line tools).
- **Device Control and Data Access** (called Accessibility before macOS 27) and **Input Monitoring** permissions. The launcher reads keys through an event tap and doesn't capture anything until both are granted. The menu bar menu links to the right pane in System Settings.

## Install

With Homebrew:

```sh
brew tap juyanith/unnamed-manager https://github.com/juyanith/unnamed-manager-mac
brew install --cask unnamed-manager
```

`brew upgrade` then keeps it up to date, and restarts it after an update. Every release is signed with the same certificate, so macOS keeps the permissions granted across updates.

## Build from source

```sh
./build.sh --open
```

This builds a release version into `build/UnnamedManager.app`, signs it and opens it. Nothing is installed, so a Homebrew copy in /Applications stays as it is. SwiftPM's intermediate products go to `~/Library/Developer/UnnamedManager`, outside the repo. To keep a local build, copy it to /Applications yourself.

It signs with the "Unnamed Launcher Code Signing" certificate when it's in your keychain, so a local build has the same signature as the releases. Otherwise it uses your Apple Development certificate, or signs ad hoc. With an ad hoc signature, macOS asks for the permissions again after each rebuild.

## Config

On first launch the app writes a starter config. A small example:

```json
{
  "version": 1,
  "entries": [
    { "keys": "Hyper+Space", "title": "Commands" },
    { "keys": "Hyper+Space E", "title": "Editor", "action": "open-editor" },
    { "keys": "Hyper+Space F", "title": "Find", "action": "search" },
    { "keys": "Hyper+T", "title": "Terminal", "action": "open-terminal" }
  ],
  "actions": {
    "open-editor": { "type": "application", "bundleId": "dev.zed.Zed" },
    "open-terminal": { "type": "application", "bundleId": "com.apple.Terminal" },
    "search": {
      "type": "contextual",
      "variants": { "browser": { "type": "send", "keys": "Primary+L" } },
      "fallback": { "type": "send", "keys": "Primary+F" }
    }
  },
  "contexts": [
    { "id": "browser", "apps": ["com.google.Chrome", "com.apple.Safari"] }
  ]
}
```

Chords use `Ctrl`, `Opt` (or `Alt`), `Shift` and `Cmd`, the symbols ⌃⌥⇧⌘ (`⌃⌥⇧T`), or the groups `Hyper` (⌃⌥⇧⌘), `Meh` (⌃⌥⇧) and `CAG` (⌃⌥⌘). An entry with an `action` is a binding, and one without is a menu. A top-level entry (a single chord) without an action is a leader; with an action it's a direct binding that runs as soon as you press the chord. The full format, including runtime and HUD settings, is in [docs/SPEC.md](docs/SPEC.md).

## Development

```sh
swift test --scratch-path ~/Library/Developer/UnnamedManager/test-build   # unit tests
tools/selftest.sh                                                          # the app's own checks, against a /tmp config
tools/snap.sh                                                              # light and dark snapshots of every page
```

- `Sources/UnnamedManager/` is the app. `Sources/UnnamedManagerKit/` holds the rules and config logic, with no UI, and has the unit tests.
- [ARCHITECTURE.md](ARCHITECTURE.md) covers the targets, threads and seams.
- [docs/](docs/) has the brief, the spec, the stories, the glossary and the design notes.

## Releases

GitHub Actions builds and tests every push and pull request (`.github/workflows/ci.yml`). To publish a release, push a version tag:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

`.github/workflows/release.yml` builds the app with that version, zips it, and attaches it to a GitHub Release. A tag with a hyphen, such as `v0.2.0-beta.1`, makes a pre-release.

It then updates `Casks/unnamed-manager.rb` to the new version, so `brew upgrade` picks it up. Pre-releases leave the cask alone.

Releases are signed with the certificate in these repository secrets (Settings > Secrets and variables > Actions). Without them, a release is signed ad hoc and macOS asks for the permissions again after each update.

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | The "Unnamed Launcher Code Signing" certificate and key, exported from Keychain Access as .p12, then `base64 -i cert.p12`. A "Developer ID Application" certificate works too. |
| `MACOS_CERTIFICATE_PASSWORD` | The .p12 password |

The self-signed certificate keeps the signature the same across releases, but the app isn't notarized, so Gatekeeper blocks a copy downloaded with a browser. The cask clears that. To notarize instead, use a Developer ID certificate (Apple Developer Program) and add:

| Secret | Value |
|---|---|
| `NOTARY_KEY_P8` | An App Store Connect API key (Users and Access > Integrations), `base64 -i AuthKey_XXXX.p8` |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The issuer ID shown above the keys |

To build a release locally: `APP_VERSION=0.2.0 ./build.sh --out dist`.

## License

MIT. See [LICENSE](LICENSE).
