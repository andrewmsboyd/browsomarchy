// Pure helpers for the Browsomarchy plugin: parsing the browser-scan output,
// applying the user's hide/reorder preferences, regex rule matching, and
// keyboard-shortcut assignment. Kept dependency-free (no QML types) so this
// is easy to hand-test apart from the Service/BarWidget plumbing.

// scan-browsers.sh emits one JSON object per line: {"id": "brave.desktop"}.
// Returns the ids in the order the scan found them, deduped.
function parseScanOutput(text) {
  var lines = String(text || "").split("\n")
  var seen = {}
  var ids = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var row = JSON.parse(line)
      var id = String(row && row.id || "")
      if (id && !seen[id]) {
        seen[id] = true
        ids.push(id)
      }
    } catch (e) {
      // Ignore malformed lines rather than losing the whole scan.
    }
  }
  return ids
}

// Applies the saved display order and hidden set to the freshly-scanned id
// list. Ids from `order` that are still installed come first, in that order;
// any newly-detected id not yet in `order` is appended afterward
// (alphabetically, so new browsers appear in a stable spot). Hidden ids are
// dropped entirely.
function visibleOrderedIds(scannedIds, hiddenIds, order) {
  var installed = {}
  for (var i = 0; i < scannedIds.length; i++) installed[scannedIds[i]] = true

  var hidden = {}
  for (var h = 0; h < (hiddenIds || []).length; h++) hidden[hiddenIds[h]] = true

  var result = []
  var placed = {}

  var savedOrder = order || []
  for (var j = 0; j < savedOrder.length; j++) {
    var id = savedOrder[j]
    if (!installed[id] || placed[id] || hidden[id]) continue
    result.push(id)
    placed[id] = true
  }

  var rest = []
  for (var k = 0; k < scannedIds.length; k++) {
    var sid = scannedIds[k]
    if (placed[sid] || hidden[sid]) continue
    rest.push(sid)
  }
  rest.sort()
  return result.concat(rest)
}

// First-match-wins, same semantics as Browserino's Rule engine: case
// insensitive regex tested against the full URL string. Returns the
// matching rule's desktopId, or "" if nothing matches (including on an
// invalid regex, which is treated as a non-match rather than an error).
function matchRule(url, rules) {
  var text = String(url || "")
  var list = rules || []
  for (var i = 0; i < list.length; i++) {
    var rule = list[i]
    if (!rule || !rule.regex || !rule.desktopId) continue
    try {
      var re = new RegExp(rule.regex, "i")
      if (re.test(text)) return rule.desktopId
    } catch (e) {
      // Invalid regex saved by the user — skip it rather than throwing.
    }
  }
  return ""
}

// Digit shortcuts for the first nine visible rows: {"brave.desktop": "1", ...}
function assignShortcuts(visibleIds) {
  var map = {}
  for (var i = 0; i < visibleIds.length && i < 9; i++) {
    map[visibleIds[i]] = String(i + 1)
  }
  return map
}

function normalizeRules(rawRules) {
  var list = Array.isArray(rawRules) ? rawRules : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (!r || typeof r !== "object") continue
    var regex = String(r.regex || "")
    var desktopId = String(r.desktopId || "")
    if (regex && desktopId) out.push({ regex: regex, desktopId: desktopId })
  }
  return out
}

// Relative-luminance based icon selection (same convention the built-in
// agents plugin and omamode use): the base asset is drawn light-on-transparent
// for a dark bar; the "-light" twin is drawn dark-on-transparent for a light
// bar. Returns URLs in preference order so the caller can fall back.
function colorChannelLuminance(value) {
  var channel = Number(value)
  if (!isFinite(channel)) return 0
  return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
}

function colorLuminance(color) {
  if (!color) return 0
  return 0.2126 * colorChannelLuminance(color.r)
    + 0.7152 * colorChannelLuminance(color.g)
    + 0.0722 * colorChannelLuminance(color.b)
}

function iconCandidates(baseUrl, surfaceColor) {
  var base = String(baseUrl)
  var candidates = []
  if (colorLuminance(surfaceColor) >= 0.5) candidates.push(base.replace(/\.svg$/, "-light.svg"))
  candidates.push(base)
  return candidates
}

if (typeof module !== "undefined") {
  module.exports = {
    parseScanOutput: parseScanOutput,
    visibleOrderedIds: visibleOrderedIds,
    matchRule: matchRule,
    assignShortcuts: assignShortcuts,
    normalizeRules: normalizeRules,
    colorLuminance: colorLuminance,
    iconCandidates: iconCandidates
  }
}
