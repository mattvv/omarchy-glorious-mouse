import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Glorious Model O3 / D3 Wireless battery, dock and lighting via glorious-linux
// (https://github.com/Virel0/glorious-linux): `glorious` on PATH or in ~/.local/bin.
// Left click toggles the details panel (Panel.qml, same lifecycle as cpu-net), right/middle
// click re-reads now.
//
// `glorious mouse raw mouse 82` replies "82: s1 l1 mvH mvL s2 l2 mvH mvL": two
// [status, level %, millivolts BE16] blocks. Confirmed on the O3 2026-11-17 by a battery swap
// (block 1 went 0% -> 59%): block 1 is the hot-swap InfinitePlay battery in the mouse, block 2
// the cell built into the mouse. Glorious CORE (getBatteryInfo) names block 1 the "backup battery"
// and block 2 the "battery", and glorious-linux follows that naming ("secondary" = block 1); here
// the swap pack is the headline number because that's the one you change.
// Dock: receiver target 0xAA, command 0xE2 (from Glorious CORE 2.1.23's getDockChargingStatus):
// payload [status, level %, mV hi, mV lo, ?]; status 0 not connected, 1 charging, 2 charged, 3 fault.
// A sleeping mouse doesn't answer: the last reading stays, dimmed, and the widget hides
// after 2 h without a reply. Battery status codes: 1 charging, 2 discharging, 3 charged, else missing.
//
// Connection: sysfs USB IDs - 3794:a300 = V3 dock/receiver plugged into the PC, 3794:a312 = mouse
// on its own cable (then the dock isn't on the PC and can't be queried). Reads run one at a time
// (conn -> battery -> dock -> lighting): two processes on the same hidraw node collide.
// Lighting: the panel runs this plugin's `glorious-mouse-lighting set ...`, which saves the choice to
// ~/.local/state/glorious-mouse/lighting.json and applies it in the theme colour; the theme-set hook
// re-applies it on every theme change.
BarWidget {
  id: root
  moduleName: "io.github.mattvv.glorious-mouse"

  property bool interactive: true
  property bool concealed: false

  readonly property int mouseBlock: 0
  readonly property string home: Quickshell.env("HOME")
  property string bin: home + "/.local/bin/glorious"   // replaced by `command -v glorious` on first read
  readonly property string lightingBin: decodeURIComponent(Qt.resolvedUrl("glorious-mouse-lighting").toString().replace(/^file:\/\//, ""))
  readonly property string prefFile: home + "/.local/state/glorious-mouse/lighting.json"

  // Connection
  property bool hasDock: false
  property bool hasCable: false
  readonly property string connectionText: hasCable ? "USB cable" : hasDock ? "Wireless via dock" : "Not connected"

  // Lighting (readback from the mouse, cmd 0x94) and the saved preference
  readonly property var effectNames: ["off", "rainbow", "breathing-single", "breathing", "seamless-breathing",
                                      "solid", "fairies", "ghost", "cascade", "prismatic", "wave", "ripple"]
  property string lightEffect: ""
  property int lightBrightness: -1
  property int lightSpeed: -1
  property string lightColor: ""
  property string prefEffect: "solid"
  property int prefSpeed: 50
  property int prefBrightness: -1   // -1 = follow the theme
  property bool applying: false

  // GMMK Pro keyboard (stock firmware, 320f:5044) via `glorious gmmk-pro`. Its lighting can't be
  // read back, so the panel shows the saved choice (~/.local/state/glorious-mouse/keyboard.json).
  readonly property string kbPrefFile: home + "/.local/state/glorious-mouse/keyboard.json"
  property bool hasKeyboard: false
  property string kbEffect: "breathing"
  property int kbSpeed: 50
  property int kbBrightness: -1     // -1 = follow the theme
  property bool kbApplying: false
  property string kbResult: ""

  property int level: -1
  property int status: 0
  property int mv: 0
  property int backupLevel: -1
  property int backupStatus: 0
  property int backupMv: 0
  property int dockLevel: -1
  property int dockStatus: 0
  property int dockMv: 0
  property int ts: 0
  property int dockTs: 0
  property int now: Math.floor(Date.now() / 1000)
  readonly property int age: now - ts
  readonly property bool charging: status === 1 || status === 3
  readonly property bool low: level >= 0 && level <= 30 && !charging
  readonly property bool stale: age >= 600

  function statusText(s) {
    return s === 1 ? "charging" : s === 2 ? "discharging" : s === 3 ? "charged" : "missing"
  }

  function dockStatusText() {
    return ["not connected", "charging", "charged", "fault"][dockStatus] || "unknown"
  }

  function batteryIcon(lvl, chg) {
    if (chg) return "󰂄"
    const icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    return icons[Math.max(0, Math.min(10, Math.round(lvl / 10)))]
  }

  function ageText() {
    if (ts === 0) return "never"
    const m = Math.round(age / 60)
    return m < 1 ? "just now" : m + " min ago"
  }

  // ---- Panel lifecycle (Bar.findPanelWidget requires open/close/opened).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  // ---- Data polling: conn -> battery -> dock (only if plugged in) -> lighting, one at a time.
  readonly property bool busy: connProc.running || readProc.running || dockProc.running
                               || lightProc.running || applyProc.running
  function refresh() {
    root.now = Math.floor(Date.now() / 1000)
    if (!root.busy) connProc.running = true
  }

  // ---- Lighting control (called from Panel.qml)
  function setLighting(effect, speed, brightness) {
    root.prefEffect = effect
    root.prefSpeed = speed
    root.prefBrightness = brightness
    root.applying = true
    applyProc.command = [root.lightingBin, "set", "--effect", effect, "--speed", String(speed),
                         "--brightness", brightness < 0 ? "theme" : String(brightness)]
    if (!root.busy) applyProc.running = true
    else applyRetry.start()
  }

  Timer {
    id: applyRetry
    interval: 400
    repeat: false
    onTriggered: if (!root.busy) applyProc.running = true; else applyRetry.start()
  }

  signal pressed(int button)
  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    if (button === Qt.LeftButton) root.toggle()
    root.pressed(button)
  }

  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }

  visible: ts > 0 && age < 7200
  implicitWidth: label.implicitWidth + Style.spaceReal(14)
  implicitHeight: barSize

  onBarChanged: syncClickRegistration()
  Component.onCompleted: {
    syncClickRegistration()
    refresh()
  }
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
  onOpenedChanged: if (opened) refresh()

  // Every 2 minutes: two small reads, slow enough not to keep the mouse awake.
  Timer {
    interval: 120000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Keeps "x min ago" and the dimming current between reads.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.now = Math.floor(Date.now() / 1000)
  }

  Process {
    id: connProc
    command: ["sh", "-c", "echo \"BIN=$(command -v glorious || echo \"$HOME/.local/bin/glorious\")\"; for d in /sys/bus/usb/devices/*; do v=$(cat $d/idVendor 2>/dev/null); [ \"$v\" = 3794 ] || [ \"$v\" = 320f ] && echo \"$v:$(cat $d/idProduct)\"; done; echo \"MOUSE=$(cat \"$1\" 2>/dev/null)\"; echo \"KB=$(cat \"$2\" 2>/dev/null)\"", "sh", root.prefFile, root.kbPrefFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const b = text.match(/^BIN=(.+)$/m)
        if (b) root.bin = b[1]
        root.hasDock = /\b3794:a300\b/.test(text)
        root.hasCable = /\b3794:a3[12]2\b/.test(text)   // O3 a312, D3 a322
        root.hasKeyboard = /\b320f:5044\b/.test(text)
        if (!root.hasDock) { root.dockLevel = -1; root.dockStatus = 0; root.dockMv = 0 }
        const j = text.match(/^MOUSE=(\{.*\})$/m)
        if (j) {
          try {
            const p = JSON.parse(j[1])
            if (p.effect) root.prefEffect = p.effect
            if (p.speed) root.prefSpeed = p.speed
            root.prefBrightness = (p.brightness === null || p.brightness === undefined) ? -1 : p.brightness
          } catch (e) {}
        }
        const k = text.match(/^KB=(\{.*\})$/m)
        if (k && !root.kbApplying) {
          try {
            const q = JSON.parse(k[1])
            if (q.effect) root.kbEffect = q.effect
            if (q.speed !== undefined) root.kbSpeed = q.speed
            root.kbBrightness = (q.brightness === null || q.brightness === undefined) ? -1 : q.brightness
          } catch (e) {}
        }
      }
    }
    onRunningChanged: if (!running && (root.hasDock || root.hasCable)) readProc.running = true
  }

  Process {
    id: readProc
    command: [root.bin, "mouse", "raw", "mouse", "82"]
    onRunningChanged: {
      if (running) return
      if (root.hasDock) dockProc.running = true
      else lightProc.running = true
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const m = text.match(/82:\s*((?:[0-9a-f]{2}\s*){8})/i)
        if (!m) return
        const b = m[1].trim().split(/\s+/).map(function(h) { return parseInt(h, 16) })
        const o = root.mouseBlock * 4
        const s = (1 - root.mouseBlock) * 4
        root.status = b[o]
        root.level = b[o + 1]
        root.mv = b[o + 2] * 256 + b[o + 3]
        root.backupStatus = b[s]
        root.backupLevel = b[s + 1]
        root.backupMv = b[s + 2] * 256 + b[s + 3]
        root.ts = Math.floor(Date.now() / 1000)
      }
    }
  }

  Process {
    id: dockProc
    command: [root.bin, "mouse", "raw", "receiver", "e2"]
    onRunningChanged: if (!running) lightProc.running = true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const m = text.match(/e2:\s*([0-9a-f]{2})\s+([0-9a-f]{2})\s+([0-9a-f]{2})\s+([0-9a-f]{2})/i)
        if (!m) return
        root.dockStatus = parseInt(m[1], 16)
        root.dockLevel = parseInt(m[2], 16)
        root.dockMv = parseInt(m[3], 16) * 256 + parseInt(m[4], 16)
        root.dockTs = Math.floor(Date.now() / 1000)
      }
    }
  }

  Process {
    id: lightProc
    command: [root.bin, "mouse", "raw", "mouse", "94"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const m = text.match(/94:\s*((?:[0-9a-f]{2}\s*){6,})/i)
        if (!m) return
        const b = m[1].trim().split(/\s+/).map(function(h) { return parseInt(h, 16) })
        root.lightEffect = root.effectNames[b[0]] || ("effect " + b[0])
        root.lightBrightness = b[1]
        root.lightSpeed = b[3] * 256 + b[4]
        root.lightColor = (b.length >= 10 && b[6] === 1)
          ? "#" + [b[7], b[8], b[9]].map(function(v) { return ("0" + v.toString(16)).slice(-2) }).join("")
          : ""
      }
    }
  }

  // The keyboard is its own HID device, so this can run alongside the mouse reads.
  function setKeyboardLighting(effect, speed, brightness) {
    root.kbEffect = effect
    root.kbSpeed = speed
    root.kbBrightness = brightness
    root.kbApplying = true
    kbProc.command = [root.lightingBin, "set", "--device", "keyboard", "--effect", effect,
                      "--speed", String(speed), "--brightness", brightness < 0 ? "theme" : String(brightness)]
    if (kbProc.running) kbRetry.start()
    else kbProc.running = true
  }

  Timer {
    id: kbRetry
    interval: 300
    onTriggered: if (kbProc.running) kbRetry.start(); else kbProc.running = true
  }

  Process {
    id: kbProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const m = text.match(/^keyboard(?: failed)?: (.+)$/m)
        root.kbResult = m ? m[0] : ""
      }
    }
    onRunningChanged: if (!running) root.kbApplying = false
  }

  Process {
    id: applyProc
    command: ["true"]
    onRunningChanged: {
      if (running) return
      root.applying = false
      root.refresh()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName
    function refresh() { root.refresh() }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function mouse() { root.openTab("mouse") }
    function keyboard() { root.openTab("keyboard") }
  }

  function openTab(tab) {
    if (panelLoader.item) panelLoader.item.tab = tab
    if (!root.opened) root.open()
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: "󰍽 " + root.batteryIcon(root.level, root.charging) + " " + root.level + "%"
    color: root.low ? "#ff6b6b" : (root.bar ? root.bar.barForeground : Color.foreground)
    opacity: root.stale ? 0.5 : 1.0
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) root.refresh()
      else root.triggerPress(mouse.button)
    }
  }
}
