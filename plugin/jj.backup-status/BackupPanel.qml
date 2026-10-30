import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Machine backup (omarchy-sync): status, schedule, back up now, and restore any of the last 5 backups.
// Click: open the panel. Middle click: back up now. Right click: refresh.
Panel {
  id: root
  moduleName: "jj.backup-status"
  ipcTarget: "jj.backup-status"
  manageIpc: false

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null

  property var info: ({ status: "unknown", message: "", lastEpoch: 0, pending: 0, unpushed: 0, timer: "",
                        nextEpoch: 0, interval: "1h", intervals: [], running: false, remote: "",
                        undocumented: [], missingPackages: [], commits: [] })
  property bool backingUp: false
  property bool restoring: false
  property bool answering: false
  property var confirmCommit: null
  property int confirmChoice: 1
  property bool loaded: false
  property int cursorIndex: -1
  property real now: Date.now() / 1000

  readonly property bool running: backingUp || restoring || answering || info.running === true
  readonly property bool unconfigured: info.status === "unconfigured"
  readonly property bool failed: info.status === "error"
  readonly property bool timerOff: loaded && !unconfigured && info.timer !== "active"
  readonly property var undocumented: info.undocumented || []
  readonly property var commits: info.commits || []
  readonly property bool problem: failed || timerOff || unconfigured
  readonly property var missingPackages: info.missingPackages || []
  // Configuration another machine saved that is waiting for the user's answer (omarchy-sync apply | skip).
  readonly property var incoming: info.incoming || null
  readonly property bool hasIncoming: incoming !== null
  // One row per change the user can apply or decline on its own: files first, then theme/packages/...
  readonly property var incomingItems: {
    if (!hasIncoming) return []
    var both = incoming.both || [], out = []
    ;(incoming.files || []).forEach(function(f) { out.push({ id: f, label: f, both: both.indexOf(f) >= 0 }) })
    ;(incoming.extras || []).forEach(function(e) { out.push({ id: e.id, label: e.label, both: false }) })
    return out
  }
  readonly property int incomingShown: 14
  readonly property bool hasAlert: !unconfigured && (problem || hasIncoming || undocumented.length > 0 || missingPackages.length > 0)
  readonly property var scheduleOptions: {
    var labels = { "15min": "15m", "30min": "30m", "1h": "1h", "6h": "6h", "12h": "12h", "24h": "24h", "off": strings.t("schedule.off") }
    var list = info.intervals && info.intervals.length ? info.intervals : ["15min", "30min", "1h", "6h", "12h", "24h", "off"]
    return list.map(function(v) { return { value: v, label: labels[v] || v } })
  }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color statusColor: problem ? urgent : accent

  readonly property string glyphCloud: ""
  readonly property string glyphUpload: ""
  readonly property string glyphWarn: ""
  readonly property string glyphSync: ""
  readonly property string glyphGithub: ""
  readonly property string glyphFile: ""
  readonly property string glyphBook: ""
  readonly property string glyphUndo: ""
  readonly property string glyphBox: ""

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function ago(epoch) {
    if (!epoch) return strings.t("stat.never")
    var s = Math.max(0, root.now - epoch)
    if (s < 60) return strings.t("time.now")
    if (s < 3600) { var m = Math.floor(s / 60); return strings.tn("time.min", m).arg(m) }
    if (s < 86400) { var h = Math.floor(s / 3600); return strings.tn("time.hour", h).arg(h) }
    var d = Math.floor(s / 86400)
    return strings.tn("time.day", d).arg(d)
  }

  function until(epoch) {
    if (!epoch || root.timerOff) return "—"
    var m = Math.max(1, Math.round((epoch - root.now) / 60))
    if (m >= 60) return Qt.formatTime(new Date(epoch * 1000), "HH:mm")
    return strings.tn("time.inMin", m).arg(m)
  }

  function commitTitle(subject) {
    var s = String(subject || "")
    var m
    if (/^backup: .*(inicial|initial)/.test(s)) return strings.t("commit.initial")
    // backup: <date> · <host> · <what changed>
    if ((m = /^backup: [^·]+·[^·]+· (.+)$/.exec(s))) return m[1]
    if (/^backup: /.test(s)) return strings.t("commit.auto")
    if (/^snapshot: /.test(s)) return strings.t("commit.snapshot")
    if ((m = /^restore: (\S+)/.exec(s))) return strings.t("commit.restore").arg(m[1])
    return s
  }

  function commitMeta(c) {
    var parts = [ago(c.epoch)]
    // Which machine made it, so a restore never picks another machine's backup by mistake.
    if (c.machine && c.machine !== "?") parts.push(c.machine === info.machine ? c.machine + " ✓" : c.machine)
    if (c.files > 0) parts.push(strings.tn("commit.files", c.files).arg(Commons.I18n.formatNumber(c.files)))
    parts.push(String(c.hash || ""))
    return parts.join("  ·  ")
  }

  readonly property string heroMeta: {
    if (unconfigured) return strings.t("meta.unconfigured")
    if (restoring) return strings.t("meta.restoring")
    if (running) return strings.t("meta.running")
    if (failed) return String(info.message || "")
    if (timerOff) return strings.t("meta.off")
    if (info.pending > 0) return strings.tn("meta.pending", info.pending).arg(info.pending)
    if (info.unpushed > 0) return strings.tn("meta.unpushed", info.unpushed).arg(info.unpushed)
    return strings.t("meta.ok")
  }


  function refresh() {
    root.now = Date.now() / 1000
    if (!statusProc.running) statusProc.running = true
  }

  function backupNow() {
    if (root.running) return
    root.backingUp = true
    backupProc.running = true
  }

  function setInterval(value) {
    if (value === root.info.interval) return
    var next = Object.assign({}, root.info); next.interval = value; root.info = next
    intervalProc.command = ["omarchy-sync", "interval", value]
    intervalProc.running = true
  }

  function askRestore(index) {
    var c = root.commits[index]
    if (!c || root.running) return
    root.confirmChoice = 1
    root.confirmCommit = c
  }

  function confirmRestore() {
    var c = root.confirmCommit
    root.confirmCommit = null
    if (!c || root.running) return
    root.restoring = true
    restoreProc.command = ["omarchy-sync", "restore", String(c.hash)]
    restoreProc.running = true
  }

  function setUp() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-sync init"])
    root.close()
  }

  function restoreFromGithub() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-sync restore-github"])
    root.close()
  }

  function answerIncoming(choice, item) {
    answering = true
    answerProc.command = item ? ["omarchy-sync", choice, item] : ["omarchy-sync", choice]
    answerProc.running = true
  }

  function installMissing() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-sync restore-packages"])
  }

  function openUrl(url) {
    if (url) Quickshell.execDetached(["xdg-open", url])
  }

  function openCommit(index) {
    var c = root.commits[index]
    if (c && info.remote) openUrl(info.remote + "/commit/" + c.hash)
  }

  function moveCursor(dy) {
    if (root.commits.length === 0) return
    root.cursorIndex = Math.max(0, Math.min(root.commits.length - 1, root.cursorIndex < 0 ? 0 : root.cursorIndex + dy))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorIndex = -1
    confirmCommit = null
    if (panelFlick) panelFlick.contentY = 0
    refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function backup(): string { root.backupNow(); return "ok" }
  }

  Process {
    id: statusProc
    command: ["omarchy-sync", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object") { root.info = parsed; root.loaded = true }
        } catch (e) {
          root.info = ({ status: "error", message: "omarchy-sync status --json", commits: [], undocumented: [] })
        }
      }
    }
  }

  Process {
    id: backupProc
    command: ["omarchy-sync", "run"]
    onExited: function(exitCode) {
      root.backingUp = false
      root.refresh()
      if (!root.opened)
        Quickshell.execDetached(["notify-send", "-a", "Backup", strings.t("title"),
                                 exitCode === 0 ? strings.t("notify.done") : strings.t("notify.failed")])
    }
  }

  Process {
    id: restoreProc
    onExited: function(exitCode) {
      root.restoring = false
      root.refresh()
      Quickshell.execDetached(["notify-send", "-a", "Backup", strings.t("title"),
                               exitCode === 0 ? strings.t("notify.restored") : strings.t("notify.restoreFailed")])
    }
  }

  Process {
    id: answerProc
    onExited: function(exitCode) {
      root.answering = false
      root.refresh()
    }
  }

  Process {
    id: intervalProc
    onExited: root.refresh()
  }

  Timer {
    interval: root.running ? 3000 : (root.opened ? 15000 : 60000)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.running ? root.glyphUpload : (root.problem ? root.glyphWarn : root.glyphCloud)
    active: root.problem
    labelText: !root.running && root.info.pending > 0 ? String(root.info.pending) : ""
    slotSize: Style.bar.statusSlot
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.backupNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.confirmCommit) { if (dx !== 0) root.confirmChoice = root.confirmChoice === 0 ? 1 : 0; return }
        root.moveCursor(dy)
      }
      onActivateRequested: {
        if (root.confirmCommit) { if (root.confirmChoice === 1) root.confirmRestore(); else root.confirmCommit = null }
        else if (root.cursorIndex >= 0) root.askRestore(root.cursorIndex)
      }
      onCloseRequested: root.confirmCommit ? root.confirmCommit = null : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.confirmCommit) return
        if (t === "o" || t === "O") { if (root.cursorIndex >= 0) root.openCommit(root.cursorIndex) }
        else if (t === "b" || t === "B") root.backupNow()
        else if (t === "r" || t === "R") root.refresh()
        else if (t === "g" || t === "G") root.openUrl(root.info.remote)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(14)

          // ---------- Hero ----------
          PanelHero {
            id: hero
            width: parent.width
            title: strings.t("title")
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                implicitWidth: Style.font.display * 1.25
                implicitHeight: Style.font.display * 1.25
                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.14)
                }
                Text {
                  id: heroGlyph
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.running ? root.glyphSync : (root.problem ? root.glyphWarn : root.glyphCloud)
                  color: root.statusColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display * 0.62
                  RotationAnimator on rotation {
                    running: root.running
                    from: 0; to: 360
                    duration: 1200
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) heroGlyph.rotation = 0
                  }
                }
              }
            }
            trailingControl: Component {
              PanelActionButton {
                id: backupButton
                iconText: root.glyphSync
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.running
                tooltipText: strings.t("action.backup") + "  (b)"
                bordered: true
                onClicked: root.backupNow()
              }
            }
          }

          // ---------- First run ----------
          BorderSurface {
            visible: root.unconfigured
            width: parent.width
            implicitHeight: setupColumn.implicitHeight + Style.space(28)
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

            Column {
              id: setupColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(28)
              spacing: Style.space(10)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: strings.t("setup.title")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: strings.t("setup.body")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
              LinkChip {
                width: parent.width
                glyph: root.glyphCloud
                label: strings.t("setup.action")
                onActivated: root.setUp()
              }
              LinkChip {
                width: parent.width
                glyph: root.glyphCloud
                label: strings.t("setup.restore")
                onActivated: root.restoreFromGithub()
              }
            }
          }

          // ---------- Stats ----------
          Row {
            visible: !root.unconfigured
            width: parent.width
            spacing: Style.space(8)
            readonly property real tileWidth: (width - spacing * 2) / 3

            StatTile { width: parent.tileWidth; label: strings.t("stat.last"); value: root.ago(root.info.lastEpoch) }
            StatTile { width: parent.tileWidth; label: strings.t("stat.next"); value: root.until(root.info.nextEpoch); warn: root.timerOff }
            StatTile {
              width: parent.tileWidth
              label: strings.t("stat.pending")
              value: Commons.I18n.formatNumber(root.info.pending || 0)
              highlight: (root.info.pending || 0) > 0
            }
          }

          // ---------- Schedule ----------
          Column {
            visible: !root.unconfigured
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: strings.t("section.schedule")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              width: parent.width
              options: root.scheduleOptions
              value: root.info.interval || "1h"
              focusable: false
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onChanged: function(v) { root.setInterval(v) }
            }
          }

          // ---------- Alerts ----------
          BorderSurface {
            visible: root.hasAlert && !root.running
            width: parent.width
            implicitHeight: alertColumn.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            borderSpec: Border.controlSpec("normal", root.urgent, root.urgent)

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              Text {
                Layout.alignment: Qt.AlignTop
                textFormat: Text.PlainText
                text: root.glyphWarn
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              Column {
                id: alertColumn
                Layout.fillWidth: true
                spacing: Style.space(3)

                Text {
                  visible: root.hasIncoming
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.hasIncoming ? strings.t("incoming.title").arg(String(root.incoming.from)) : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  wrapMode: Text.WordWrap
                }
                Text {
                  visible: root.hasIncoming
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.hasIncoming
                        ? strings.tn("incoming.files", (root.incoming.files || []).length).arg((root.incoming.files || []).length)
                        : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                Repeater {
                  model: root.hasIncoming ? root.incomingItems.slice(0, root.incomingShown) : []
                  delegate: RowLayout {
                    width: alertColumn.width
                    spacing: Style.space(8)

                    Text {
                      Layout.fillWidth: true
                      textFormat: Text.PlainText
                      elide: Text.ElideMiddle
                      text: modelData.label + (modelData.both ? "  · " + strings.t("incoming.both") : "")
                      color: modelData.both ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    AnswerLink {
                      text: strings.t("incoming.yes")
                      onActivated: root.answerIncoming("apply", modelData.id)
                    }
                    AnswerLink {
                      text: strings.t("incoming.no")
                      onActivated: root.answerIncoming("skip", modelData.id)
                    }
                  }
                }
                Text {
                  visible: root.hasIncoming && root.incomingItems.length > root.incomingShown
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.hasIncoming ? strings.t("incoming.more").arg(root.incomingItems.length - root.incomingShown) : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                RowLayout {
                  visible: root.hasIncoming
                  width: parent.width
                  spacing: Style.space(8)

                  LinkChip {
                    Layout.preferredWidth: chipRowWidth + Style.space(20)
                    glyph: root.glyphBox
                    label: strings.t("incoming.apply")
                    onActivated: root.answerIncoming("apply")
                  }
                  LinkChip {
                    Layout.preferredWidth: chipRowWidth + Style.space(20)
                    glyph: root.glyphFile
                    label: strings.t("incoming.skip")
                    onActivated: root.answerIncoming("skip")
                  }
                }
                Text {
                  visible: root.failed
                  width: parent.width
                  textFormat: Text.PlainText
                  text: String(root.info.message || "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
                Text {
                  visible: root.timerOff
                  width: parent.width
                  textFormat: Text.PlainText
                  text: strings.t("alert.timer")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
                RowLayout {
                  visible: root.missingPackages.length > 0
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: strings.tn("alert.missing", root.missingPackages.length).arg(root.missingPackages.length)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  LinkChip {
                    Layout.preferredWidth: chipRowWidth + Style.space(20)
                    glyph: root.glyphBox
                    label: strings.t("alert.install")
                    onActivated: root.installMissing()
                  }
                }
                Text {
                  visible: root.undocumented.length > 0
                  width: parent.width
                  textFormat: Text.PlainText
                  text: strings.t("alert.undocumented").arg(root.undocumented.join(", "))
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  wrapMode: Text.WordWrap
                }
                Text {
                  visible: root.undocumented.length > 0
                  width: parent.width
                  textFormat: Text.PlainText
                  text: strings.t("alert.undocumentedHelp")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          PanelSeparator { visible: !root.unconfigured; foreground: root.foreground }

          // ---------- History ----------
          Column {
            visible: !root.unconfigured
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: historyHeader.implicitHeight

              PanelSectionHeader {
                id: historyHeader
                text: strings.t("section.history")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: historyHeader.verticalCenter
                visible: root.commits.length > 0
                textFormat: Text.PlainText
                text: strings.t("history.hint")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: root.loaded && root.commits.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: strings.t("history.empty")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              width: parent.width
              spacing: 0

              Repeater {
                model: root.commits
                CommitRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  commit: modelData
                  rowIndex: index
                  last: index === root.commits.length - 1
                }
              }
            }
          }

          PanelSeparator { visible: !root.unconfigured; foreground: root.foreground }

          // ---------- Links ----------
          Row {
            visible: !root.unconfigured
            width: parent.width
            spacing: Style.space(8)
            readonly property real chipWidth: (width - spacing * 2) / 3

            LinkChip { width: parent.chipWidth; glyph: root.glyphGithub; label: strings.t("footer.github"); url: root.info.remote }
            LinkChip { width: parent.chipWidth; glyph: root.glyphFile; label: strings.t("footer.inventory"); url: root.info.remote ? root.info.remote + "/blob/HEAD/INVENTORY.md" : "" }
            LinkChip { width: parent.chipWidth; glyph: root.glyphBook; label: strings.t("footer.agents"); url: root.info.remote ? root.info.remote + "/blob/HEAD/AGENTS.md" : "" }
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.confirmCommit !== null
        selectedIndex: root.confirmChoice
        message: root.confirmCommit
                 ? strings.t("confirm.restore").arg(String(root.confirmCommit.hash)).arg(root.ago(root.confirmCommit.epoch))
                 : ""
        confirmText: strings.t("confirm.ok")
        cancelText: strings.t("confirm.cancel")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.confirmCommit = null
        onConfirmed: root.confirmRestore()
      }
    }
  }

  // Ticks the relative times while the panel is visible.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }

  component StatTile: BorderSurface {
    id: tile
    property string label: ""
    property string value: ""
    property bool highlight: false
    property bool warn: false

    implicitHeight: tileColumn.implicitHeight + Style.space(18)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

    Column {
      id: tileColumn
      anchors.centerIn: parent
      width: parent.width - Style.space(12)
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: tile.value
        color: tile.warn ? root.urgent : (tile.highlight ? root.accent : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: tile.label.toUpperCase()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.1
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }

  component CommitRow: CursorSurface {
    id: row
    property var commit: ({})
    property int rowIndex: 0
    property bool last: false

    hasCursor: root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.space(14)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.info.remote ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.cursorIndex = row.rowIndex
      onClicked: root.openCommit(row.rowIndex)
    }

    // Timeline: a dot plus a line down to the next backup.
    Item {
      id: rail
      width: Style.space(14)
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.top: parent.top
      anchors.bottom: parent.bottom

      Rectangle {
        visible: !row.last
        width: Style.spacing.hairline * 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: dot.verticalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -Style.space(7)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      }
      Rectangle {
        id: dot
        width: Style.space(9)
        height: width
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.space(7) + titleText.implicitHeight / 2 - height / 2
        color: row.rowIndex === 0 ? root.statusColor : "transparent"
        border.width: Style.spacing.hairline * 2
        border.color: row.rowIndex === 0 ? root.statusColor : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
      }
    }

    PanelActionButton {
      id: restoreButton
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: row.hasCursor && !root.running
      iconText: root.glyphUndo
      tooltipText: strings.t("action.restore")
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.askRestore(row.rowIndex)
    }

    Column {
      id: rowContent
      anchors.left: rail.right
      anchors.leftMargin: Style.space(10)
      anchors.right: restoreButton.visible ? restoreButton.left : parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        id: titleText
        width: parent.width
        textFormat: Text.PlainText
        text: root.commitTitle(row.commit.subject)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.rowIndex === 0
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.commitMeta(row.commit)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  // A small text action next to one incoming change (apply or skip just that one).
  component AnswerLink: Text {
    id: link
    signal activated()
    textFormat: Text.PlainText
    color: linkMouse.containsMouse ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: linkMouse.containsMouse
    opacity: root.answering ? 0.4 : 1

    MouseArea {
      id: linkMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      enabled: !root.answering
      cursorShape: Qt.PointingHandCursor
      onClicked: link.activated()
    }
  }

  component LinkChip: CursorSurface {
    id: chip
    property string glyph: ""
    property string label: ""
    property string url: ""
    readonly property real chipRowWidth: chipRow.implicitWidth
    signal activated()

    bordered: true
    foreground: root.foreground
    opacity: url !== "" || chipMouse.actionOnly ? 1 : 0.5
    implicitHeight: chipRow.implicitHeight + Style.space(14)

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      readonly property bool actionOnly: chip.url === "" && (chip.glyph === root.glyphBox || root.unconfigured)
      onClicked: chip.url !== "" ? root.openUrl(chip.url) : chip.activated()
    }
    hasCursor: chipMouse.containsMouse

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
