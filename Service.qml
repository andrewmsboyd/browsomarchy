import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Backend for the Browsomarchy plugin: owns the detected browser list, the
// user's rules/hidden/order preferences (mirrored in from the bar widget's
// shell.json entry, same convention omamode uses), the pending-URL handoff
// used to hand a summoned popup its URL, and the IPC surface that the
// registered .desktop entry calls into when a link is opened anywhere on
// the system. Runs entirely inside omarchy-shell — no daemon of its own.
Item {
  id: root

  // Injected by omarchy-shell, same convention as omamode's Service.qml.
  property var shell: null

  readonly property string pluginId: "io.github.andrewmsboyd.browsomarchy"
  readonly property string desktopId: pluginId + ".desktop"
  // Third-party plugin directories always live here — documented, fixed
  // location (see PluginRegistry.pluginsDir) — so this is safe to hardcode
  // rather than derive from Qt.resolvedUrl().
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId
  readonly property string desktopFilePath: Quickshell.env("HOME") + "/.local/share/applications/" + desktopId

  // ---- Config, pushed in by BarWidget.qml from the shell.json entry ----
  property var rules: []            // [{ regex, desktopId }]
  property var hiddenBrowsers: []   // [desktopId]
  property var order: []            // [desktopId] — user's preferred display order

  // ---- State ----
  property var scannedIds: []       // every installed browser, as detected
  property string pendingUrl: ""    // handed to whichever BarWidget.open() runs next
  property string defaultBrowserId: ""

  readonly property var visibleIds: Model.visibleOrderedIds(root.scannedIds, root.hiddenBrowsers, root.order)
  readonly property var visibleBrowsers: root.visibleIds.map(root.browserInfo)
  readonly property var shortcuts: Model.assignShortcuts(root.visibleIds)
  readonly property bool isDefault: root.defaultBrowserId === root.desktopId

  // cfg's arrays cross from the BarWidget's QML context into this Service's
  // — confirmed empirically that they arrive as sequence-like objects whose
  // own constructor.name still says "Array" but which fail Array.isArray()
  // (a real cross-realm marshalling quirk, not a logic bug: JSON.stringify
  // and .length/indexing on them work fine, only the isArray() brand check
  // doesn't). Util.cloneJson() (JSON.parse(JSON.stringify(...))) forces a
  // genuine native array/object in *this* realm before anything here relies
  // on Array.isArray() — that includes Model.normalizeRules()'s own check.
  function updateConfig(cfg) {
    if (cfg.rules !== undefined) root.rules = Model.normalizeRules(Util.cloneJson(cfg.rules))
    if (cfg.hiddenBrowsers !== undefined) {
      var hidden = Util.cloneJson(cfg.hiddenBrowsers)
      root.hiddenBrowsers = Array.isArray(hidden) ? hidden : []
    }
    if (cfg.order !== undefined) {
      var order = Util.cloneJson(cfg.order)
      root.order = Array.isArray(order) ? order : []
    }
  }

  function browserInfo(id) {
    // Quickshell's DesktopEntries indexes by id *without* the .desktop
    // suffix (the same convention AppLibrary.qml's normalizeDesktopId()
    // strips to and re-adds around gtk-launch) — everywhere else in this
    // plugin (rules, hiddenBrowsers, order, launch.sh, xdg-mime) keeps the
    // full ".desktop" filename, so strip it only for this one lookup.
    var entry = DesktopEntries.byId(id.replace(/\.desktop$/, ""))
    return {
      id: id,
      name: entry ? String(entry.name || id) : id.replace(/\.desktop$/, ""),
      icon: entry ? String(entry.icon || "") : ""
    }
  }

  function rescan() {
    if (!scanProcess.running) scanProcess.running = true
  }

  // Consumed exactly once by whichever BarWidget instance's open() the
  // shell.summon() call landed on.
  function takePendingUrl() {
    var url = root.pendingUrl
    root.pendingUrl = ""
    return url
  }

  function launch(desktopId, url, incognito) {
    var args = [root.pluginDir + "/launch.sh", desktopId, url]
    if (incognito) args.push("--incognito")
    Quickshell.execDetached(args)
  }

  // The IPC entry point our registered .desktop file's Exec= line calls
  // into (`omarchy-shell browsomarchy open %u`). Rule match → launch directly,
  // no UI. Otherwise stash the URL and summon the bar popup exactly like a
  // hotkey would (Bar.qml's findPanelWidget picks the focused monitor).
  function openUrl(url) {
    var trimmed = String(url || "").trim()
    if (!trimmed) return "ignored: empty url"

    var ruleMatch = Model.matchRule(trimmed, root.rules)
    if (ruleMatch) {
      root.launch(ruleMatch, trimmed, false)
      return "rule:" + ruleMatch
    }

    root.pendingUrl = trimmed
    var summoned = root.shell && typeof root.shell.summon === "function"
      && root.shell.summon(root.pluginId, "")

    if (!summoned) {
      // No live bar widget to show the picker in (removed from the bar,
      // or no monitor has a bar at all) — open something rather than
      // silently dropping the link, since this plugin may be the system's
      // registered default browser handler.
      var fallback = root.visibleBrowsers[0]
      root.pendingUrl = ""
      if (fallback) {
        root.launch(fallback.id, trimmed, false)
        return "fallback:" + fallback.id
      }
      return "no picker available"
    }
    return "prompting"
  }

  function desktopFileContent() {
    return [
      "[Desktop Entry]",
      "Type=Application",
      "Name=Browsomarchy",
      "Comment=Choose a browser for this link",
      "Exec=omarchy-shell browsomarchy open %u",
      "Icon=web-browser",
      "Terminal=false",
      "NoDisplay=true",
      "MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;x-scheme-handler/about;x-scheme-handler/unknown;"
    ].join("\n") + "\n"
  }

  // Registers the .desktop file so the desktop database knows this plugin
  // *can* handle links — inert until makeDefault() (or the user) actually
  // points http/https at it. Safe to redo on every shell start.
  function ensureDesktopFile() {
    desktopFile.setText(root.desktopFileContent())
    registerProcess.running = true
  }

  function refreshDefaultBrowserId() {
    if (!defaultProbe.running) defaultProbe.running = true
  }

  // Explicit action (mirrors Browserino's — the macOS app this is inspired
  // by — own "Make default" button) —
  // never run automatically on install.
  function makeDefault() {
    var appsDir = Quickshell.env("HOME") + "/.local/share/applications"
    var cmd = [
      "xdg-mime default " + Util.shellQuote(root.desktopId)
        + " x-scheme-handler/http x-scheme-handler/https text/html"
        + " x-scheme-handler/about x-scheme-handler/unknown",
      "xdg-settings set default-web-browser " + Util.shellQuote(root.desktopId),
      "update-desktop-database " + Util.shellQuote(appsDir)
    ].join(" && ")
    Util.execDetached(cmd)
    defaultCheckTimer.restart()
  }

  FileView {
    id: desktopFile
    path: root.desktopFilePath
    printErrors: false
  }

  Process {
    id: registerProcess
    command: ["bash", "-c", "update-desktop-database " + Util.shellQuote(Quickshell.env("HOME") + "/.local/share/applications") + " 2>/dev/null || true"]
  }

  Process {
    id: scanProcess
    command: [root.pluginDir + "/scan-browsers.sh", root.desktopId]
    stdout: StdioCollector {
      id: scanStdout
      waitForEnd: true
      onStreamFinished: root.scannedIds = Model.parseScanOutput(scanStdout.text)
    }
  }

  Process {
    id: defaultProbe
    command: ["bash", "-c", "xdg-settings get default-web-browser 2>/dev/null || xdg-mime query default x-scheme-handler/https 2>/dev/null"]
    stdout: StdioCollector {
      id: defaultStdout
      waitForEnd: true
      onStreamFinished: root.defaultBrowserId = defaultStdout.text.trim()
    }
  }

  // Gives xdg-mime/xdg-settings a moment to land before re-reading.
  Timer {
    id: defaultCheckTimer
    interval: 1500
    onTriggered: root.refreshDefaultBrowserId()
  }

  Component.onCompleted: {
    root.ensureDesktopFile()
    root.rescan()
    root.refreshDefaultBrowserId()
  }

  IpcHandler {
    target: "browsomarchy"

    function open(url: string): string { return root.openUrl(url) }
    function rescan(): string { root.rescan(); return "ok" }
    function makeDefault(): string { root.makeDefault(); return "ok" }

    function status(): string {
      return JSON.stringify({
        browsers: root.visibleBrowsers,
        defaultBrowser: root.defaultBrowserId,
        isDefault: root.isDefault
      })
    }
  }
}
