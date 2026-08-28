import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar icon + dropdown for the Browsomarchy plugin. Doubles as two different
// views of the same popup:
//   - Summoned with a pending URL (Service.openUrl() -> shell.summon()):
//     shows the browser picker for that link.
//   - Clicked manually with no pending URL: shows the management section
//     (hide/reorder browsers, rules, "make default") directly, since
//     there's nothing to pick a browser *for*.
// Implements the open()/close()/opened contract findPanelWidget() (Bar.qml)
// requires, so shell.summon() and hotkeys work exactly like any other
// widget's dropdown.
BarWidget {
  id: root
  moduleName: "io.github.andrewmsboyd.browsomarchy"

  readonly property var service: bar?.shell?.firstPartyServiceFor(moduleName)

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property string activeUrl: ""
  property int selectedIndex: 0
  property bool manageOpen: false
  property string newRuleBrowser: ""

  function open() {
    var url = root.service ? root.service.takePendingUrl() : ""
    root.activeUrl = url
    root.selectedIndex = 0
    root.manageOpen = url === ""
    root.popupOpen = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.popupOpen = false }
  function toggle() { root.popupOpen ? root.close() : root.open() }

  // ---- Settings <-> Service wiring (same convention as omamode) ----
  function pushConfigToService() {
    if (!root.service) return
    root.service.updateConfig({
      rules: root.setting("rules", []),
      hiddenBrowsers: root.setting("hiddenBrowsers", []),
      order: root.setting("order", [])
    })
  }

  function updateSetting(patch) {
    var next = Object.assign({}, root.settings, patch)
    root.settings = next
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, next)
    root.pushConfigToService()
  }

  function toggleHidden(id) {
    var hidden = (root.setting("hiddenBrowsers", []) || []).slice()
    var idx = hidden.indexOf(id)
    if (idx >= 0) hidden.splice(idx, 1)
    else hidden.push(id)
    root.updateSetting({ hiddenBrowsers: hidden })
  }

  function moveBrowser(id, delta) {
    if (!root.service) return
    var full = Model.visibleOrderedIds(root.service.scannedIds, [], root.setting("order", []))
    var idx = full.indexOf(id)
    if (idx < 0) return
    var swapIdx = idx + delta
    if (swapIdx < 0 || swapIdx >= full.length) return
    var tmp = full[idx]
    full[idx] = full[swapIdx]
    full[swapIdx] = tmp
    root.updateSetting({ order: full })
  }

  function addRule(regex, desktopId) {
    if (!regex || !desktopId) return
    var rules = (root.setting("rules", []) || []).slice()
    rules.push({ regex: regex, desktopId: desktopId })
    root.updateSetting({ rules: rules })
  }

  function removeRule(index) {
    var rules = (root.setting("rules", []) || []).slice()
    if (index < 0 || index >= rules.length) return
    rules.splice(index, 1)
    root.updateSetting({ rules: rules })
  }

  function pick(index, incognito) {
    if (!root.service) return
    var list = root.service.visibleBrowsers
    if (index < 0 || index >= list.length) return
    root.service.launch(list[index].id, root.activeUrl, incognito)
    root.close()
  }

  // The shared AppLibrary (used by the app launcher/menu) already solves
  // icon lookup properly: themed lookup plus a manually-scanned icon-name
  // index for icons Qt's theme cache misses. Quickshell.iconPath() alone
  // isn't reliable for third-party app icons like browser logos — reuse
  // the same resolver instead of re-solving that problem here.
  function iconSource(icon) {
    var value = String(icon || "")
    var appLibrary = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    if (appLibrary) return appLibrary.iconSource(value)
    if (value.length === 0) return Quickshell.iconPath("web-browser", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("web-browser", true)
  }

  onServiceChanged: root.pushConfigToService()
  onSettingsChanged: root.pushConfigToService()
  Component.onCompleted: {
    root.pushConfigToService()
    if (root.service && root.service.visibleBrowsers.length > 0)
      root.newRuleBrowser = root.service.visibleBrowsers[0].id
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component {
    id: iconComponent

    Item {
      id: iconRoot
      readonly property var candidates: Model.iconCandidates(
        Qt.resolvedUrl("assets/browser.svg"),
        root.bar ? root.bar.background : Color.background)
      property string candidatesKey: candidates.join("\n")
      property int candidateIndex: 0
      onCandidatesKeyChanged: candidateIndex = 0

      Image {
        anchors.fill: parent
        source: iconRoot.candidateIndex < iconRoot.candidates.length ? iconRoot.candidates[iconRoot.candidateIndex] : ""
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        smooth: true
        onStatusChanged: if (status === Image.Error && iconRoot.candidateIndex < iconRoot.candidates.length)
          Qt.callLater(function() { iconRoot.candidateIndex++ })
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: iconComponent
    tooltipText: "Browsomarchy"
    onPressed: root.toggle()
  }

  // KeyboardPanel (not PopupCard) is deliberate: PopupCard is an xdg-popup,
  // which only receives keyboard input after a click/hover routes focus
  // through its parent surface. Our summon path is external (an xdg-open
  // call, not a click on this bar icon), so an xdg-popup silently failed to
  // capture keys most of the time. KeyboardPanel is a layer-shell surface
  // built for exactly this "keyboard-summoned popup" case (see its own doc
  // comment) — same widget-popup API as PopupCard, plus `focusTarget`.
  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: Style.space(340)
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(520))

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
          return
        }
        if (root.activeUrl === "") return

        var list = root.service ? root.service.visibleBrowsers : []
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
          var idx = event.key - Qt.Key_1
          if (idx < list.length) {
            root.pick(idx, (event.modifiers & Qt.ShiftModifier) !== 0)
            event.accepted = true
          }
        } else if (event.key === Qt.Key_Down) {
          root.selectedIndex = Math.min(list.length - 1, root.selectedIndex + 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.selectedIndex = Math.max(0, root.selectedIndex - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.pick(root.selectedIndex, (event.modifiers & Qt.ShiftModifier) !== 0)
          event.accepted = true
        }
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: parent.width
          spacing: Style.space(10)

          // ---- Picker: only rendered when opened for an actual link ----
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.activeUrl !== ""

            Text {
              width: parent.width
              text: root.activeUrl
              color: root.bar.foreground
              opacity: 0.7
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
            }

            Repeater {
              model: root.service ? root.service.visibleBrowsers : []

              delegate: Rectangle {
                id: pickRow
                required property var modelData
                required property int index

                width: column.width
                height: Style.space(38)
                radius: Style.cornerRadius
                color: index === root.selectedIndex ? Color.menu.selectedBackground : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Image {
                    width: Style.space(20)
                    height: Style.space(20)
                    anchors.verticalCenter: parent.verticalCenter
                    source: root.iconSource(pickRow.modelData.icon)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }

                  Text {
                    width: parent.width - Style.space(20) - Style.space(24) - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: pickRow.modelData.name
                    color: pickRow.index === root.selectedIndex ? Color.menu.selectedText : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    readonly property string shortcut: root.service ? (root.service.shortcuts[pickRow.modelData.id] || "") : ""
                    visible: shortcut !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: shortcut
                    color: pickRow.index === root.selectedIndex ? Color.menu.selectedText : root.bar.foreground
                    opacity: 0.55
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectedIndex = pickRow.index
                  onClicked: function(mouse) { root.pick(pickRow.index, (mouse.modifiers & Qt.ShiftModifier) !== 0) }
                }
              }
            }

            Text {
              width: parent.width
              visible: !root.service || root.service.visibleBrowsers.length === 0
              text: "No browsers detected — use Rescan below."
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "1–9 to pick · Enter to open · Shift+Enter incognito"
              color: root.bar.foreground
              opacity: 0.45
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { visible: root.activeUrl !== ""; foreground: root.bar.foreground }

          // ---- Manage: browsers, rules, default-browser status ----
          Row {
            width: parent.width
            visible: root.activeUrl !== ""

            Text {
              width: parent.width - toggleManageBtn.width
              anchors.verticalCenter: parent.verticalCenter
              text: "Manage browsers & rules"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              id: toggleManageBtn
              text: root.manageOpen ? "Hide" : "Show"
              bordered: true
              foreground: root.bar.foreground
              onClicked: root.manageOpen = !root.manageOpen
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.manageOpen

            PanelSectionHeader { text: "BROWSERS"; foreground: root.bar.foreground }

            Repeater {
              model: root.service ? Model.visibleOrderedIds(root.service.scannedIds, [], root.setting("order", [])).map(root.service.browserInfo) : []

              delegate: Row {
                id: manageRow
                required property var modelData
                required property int index

                readonly property bool hiddenBrowser: (root.setting("hiddenBrowsers", []) || []).indexOf(modelData.id) !== -1

                width: column.width
                spacing: Style.space(6)

                Text {
                  width: parent.width - upBtn.width - downBtn.width - toggleHideBtn.width - parent.spacing * 3
                  anchors.verticalCenter: parent.verticalCenter
                  text: manageRow.modelData.name
                  opacity: manageRow.hiddenBrowser ? 0.4 : 1
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Button {
                  id: upBtn
                  iconText: "▲"
                  foreground: root.bar.foreground
                  onClicked: root.moveBrowser(manageRow.modelData.id, -1)
                }

                Button {
                  id: downBtn
                  iconText: "▼"
                  foreground: root.bar.foreground
                  onClicked: root.moveBrowser(manageRow.modelData.id, 1)
                }

                Button {
                  id: toggleHideBtn
                  text: manageRow.hiddenBrowser ? "Show" : "Hide"
                  bordered: true
                  foreground: root.bar.foreground
                  onClicked: root.toggleHidden(manageRow.modelData.id)
                }
              }
            }

            Button {
              text: "Rescan browsers"
              bordered: true
              foreground: root.bar.foreground
              onClicked: if (root.service) root.service.rescan()
            }

            PanelSeparator { foreground: root.bar.foreground }

            PanelSectionHeader { text: "RULES — auto-open, no prompt"; foreground: root.bar.foreground }

            Repeater {
              model: root.setting("rules", []) || []

              delegate: Row {
                id: ruleRow
                required property var modelData
                required property int index

                width: column.width
                spacing: Style.space(6)

                Text {
                  width: parent.width - browserLabel.width - removeRuleBtn.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  text: ruleRow.modelData.regex
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  id: browserLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.service ? root.service.browserInfo(ruleRow.modelData.desktopId).name : ruleRow.modelData.desktopId
                  opacity: 0.6
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Button {
                  id: removeRuleBtn
                  iconText: "✕"
                  foreground: root.bar.foreground
                  onClicked: root.removeRule(ruleRow.index)
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: ruleRegexField
                width: parent.width - ruleBrowserDropdown.width - addRuleBtn.width - parent.spacing * 2
                foreground: root.bar.foreground
                placeholderText: "regex, e.g. github\\.com"
              }

              Dropdown {
                id: ruleBrowserDropdown
                width: Style.space(120)
                showLabel: false
                options: root.service ? root.service.visibleBrowsers.map(function(b) { return { value: b.id, label: b.name } }) : []
                value: root.newRuleBrowser
                foreground: root.bar.foreground
                onChanged: function(v) { root.newRuleBrowser = v }
              }

              Button {
                id: addRuleBtn
                text: "Add"
                bordered: true
                foreground: root.bar.foreground
                enabled: ruleRegexField.text.length > 0 && root.newRuleBrowser !== ""
                onClicked: {
                  root.addRule(ruleRegexField.text, root.newRuleBrowser)
                  ruleRegexField.clear()
                }
              }
            }

            PanelSeparator { foreground: root.bar.foreground }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width - makeDefaultBtn.width
                anchors.verticalCenter: parent.verticalCenter
                text: root.service && root.service.isDefault
                  ? "Browsomarchy is your default browser"
                  : "Default browser: " + (root.service ? root.service.defaultBrowserId : "…")
                color: root.bar.foreground
                opacity: 0.75
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Button {
                id: makeDefaultBtn
                text: "Make default"
                bordered: true
                foreground: root.bar.foreground
                enabled: !(root.service && root.service.isDefault)
                onClicked: if (root.service) root.service.makeDefault()
              }
            }
          }
        }
      }
    }
  }
}
