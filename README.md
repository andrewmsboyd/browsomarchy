# Browsomarchy

An Omarchy shell (Quickshell) plugin that lets you pick which browser opens a
link, instead of always launching the same one. A Linux/Quickshell take on
[Browserino](https://github.com/AlexStrNik/Browserino) for macOS — with one
deliberate difference: opening a link doesn't spawn a separate window. It
pops the same bar dropdown you'd get from clicking the icon, on whichever
monitor has focus.

- **Picker** — links open a dropdown listing every detected browser. Click
  one, or use the keyboard: digits `1`-`9` pick instantly, arrow keys move
  the selection, `Enter` opens it, `Shift+Enter` opens it in a private
  window.
- **Rules** — regex → browser rules bypass the picker entirely for URLs you
  always want in a specific browser (e.g. `github\.com` → a work profile).
- **Hide / reorder** — tuck away a browser you never want to pick, or change
  the display order, from the same dropdown's management section.
- **Make default** — a button (and IPC command) to register Browsomarchy as
  the system's default browser via `xdg-mime`/`xdg-settings`. Never runs
  automatically — you flip it on when you're ready.

## Installation

```
omarchy plugin add https://github.com/andrewmsboyd/browsomarchy.git --enable
```

This adds the widget to your bar and enables its background service. Move
the icon with:

```
omarchy bar move io.github.andrewmsboyd.browsomarchy --section right
```

Then, once you're happy with it, click **Make default** in the dropdown (or
run `omarchy-shell browsomarchy makeDefault`) to actually make it your
system's link handler.

## Usage

Click the browser icon in the bar to open the dropdown:

- With no link pending, it shows the management section directly: browsers
  (hide/reorder), rules, and the "Make default" status/button.
- When a link is opened anywhere on the system (a browser dropdown pending),
  the same dropdown instead shows the picker for that link, with the
  management section tucked under a "Show" toggle underneath.
- The picker reliably grabs keyboard focus the instant it opens — even
  though it's triggered from outside the shell (an `xdg-open` call, not a
  click on the bar icon) — so `1`-`9` and arrow keys work immediately with
  no need to mouse over the popup first.

### CLI / IPC access

```
omarchy-shell browsomarchy status        # {"browsers":[...],"defaultBrowser":"...","isDefault":true}
omarchy-shell browsomarchy open <url>     # what the registered .desktop entry calls
omarchy-shell browsomarchy rescan         # re-scan installed browsers
omarchy-shell browsomarchy makeDefault    # register as the system default browser
```

## Configuration

All configuration (rules, hidden browsers, custom order) is stored inline in
the widget's own entry in `~/.config/omarchy/shell.json` — the same
mechanism Omarchy's built-in widgets use — under the keys `rules`,
`hiddenBrowsers`, `order`. Everything is editable from the dropdown; there's
no separate config file.

## How it works / dependencies

- Runs entirely inside the existing `omarchy-shell` process — not sandboxed,
  runs with your user permissions. No daemon of its own, and never starts a
  second Quickshell process.
- The picker popup uses Quickshell's `KeyboardPanel` (a layer-shell surface
  built for exactly this "opened from outside, must capture keys
  immediately" case) rather than the more common `PopupCard` (an xdg-popup,
  which only receives keyboard input after a click routes focus through its
  parent surface — fine for a bar icon you just clicked, unreliable for a
  popup an external `xdg-open` call just summoned).
- Browser detection greps installed `.desktop` files for
  `MimeType=...x-scheme-handler/http...` (Quickshell's own `DesktopEntries`
  parses names/icons but not `MimeType=`, so a small bundled script,
  `scan-browsers.sh`, fills that one gap) — no packages installed by this
  plugin. Note: Quickshell's `DesktopEntries.byId()` indexes ids *without*
  the `.desktop` suffix, unlike `gtk-launch`/`xdg-mime`, which want it — see
  `Service.qml:browserInfo()`.
- Launching a browser uses `gtk-launch` (same mechanism the built-in app
  launcher uses) via the bundled `launch.sh`; the incognito path resolves
  the browser's binary and picks a private-window flag using the same
  heuristic already in `/usr/share/omarchy/bin/omarchy-launch-browser`.
  Either path finishes with `omarchy-hyprland-focus-app` so a reused browser
  window on another workspace gets brought to you instead of left behind.
- "Make default" runs `xdg-mime default`, `xdg-settings set
  default-web-browser`, and `update-desktop-database` — standard XDG
  mechanisms, the same ones that plain browser installs use.
- The registered `.desktop` file
  (`~/.local/share/applications/io.github.andrewmsboyd.browsomarchy.desktop`)
  is (re)written on every shell start so it stays in sync with this plugin's
  directory, but making it the *default* handler is always an explicit,
  separate step.

## Known limitations

- **Incognito reliability**: Shift+Enter asks the chosen browser to open a
  private window via a command-line flag (`--incognito` / `--private-window`
  / `--inprivate` depending on the browser). Chromium-family browsers with
  an existing window sometimes honor this as a plain new window instead of
  a genuinely private one — an upstream single-instance-IPC quirk, not
  something this plugin can fully control.
- **Tab vs. window reuse**: launching normally (no incognito) asks the
  browser to reuse its running instance via `gtk-launch`, which in turn
  relies entirely on the browser's own singleton IPC to decide tab-vs-window.
  Empirically this comes down to *which workspace the browser's existing
  window is on*: reusing a window already visible on your current workspace
  opens a tab there; a window parked on a different workspace is often
  answered with a brand new window instead (a Wayland cross-workspace
  activation limitation, not something a launch script controls). Either
  way, `launch.sh` finishes with `omarchy-hyprland-focus-app` so whichever
  window resulted ends up in front of you.

## Removal

```
omarchy plugin remove io.github.andrewmsboyd.browsomarchy
```

If Browsomarchy is currently your default browser, pick another one first
(`xdg-settings set default-web-browser <id>.desktop`, or reinstall a browser
normally) — removing the plugin does not un-register it as the handler.

## Attribution

This plugin's design and implementation — architecture, Service/BarWidget
code, the browser-detection and launch scripts, marketplace packaging — was
written by [Claude](https://claude.com/claude-code) (Anthropic), working
interactively with [@andrewmsboyd](https://github.com/andrewmsboyd), who
directed the design (including the core "reuse the bar dropdown, don't spawn
a window" requirement, the rename, and the keyboard-focus and window-reuse
fixes), tested it on real hardware, and reviewed/approved every change.
Noted here for transparency since GitHub's Contributors graph only credits
identities tied to a real linked account, which doesn't exist for an AI
assistant working locally.

## License

MIT — see [LICENSE](LICENSE).
