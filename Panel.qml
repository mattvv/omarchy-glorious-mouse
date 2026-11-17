import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Details panel for the Mouse Battery bar widget (structure copied from cpu-net/Panel.qml).
// BarWidget.qml owns polling and injects `bar`, `settings`, `anchorItem`, `hostWidget`.
Panel {
  id: root
  moduleName: "io.github.mattvv.glorious-mouse"
  ipcTarget: "io.github.mattvv.glorious-mouse"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var w: hostWidget
  readonly property bool hasKb: !!w && w.hasKeyboard
  property string tab: "mouse"   // "mouse" | "keyboard"; Tab / Shift+Tab flips it before leaving the panel
  readonly property bool kbTab: hasKb && tab === "keyboard"

  readonly property color contentForeground: root.barForeground
  readonly property color dim: Qt.darker(root.barForeground, 1.4)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function blockBar(pct) {
    const n = Math.max(0, Math.min(10, Math.round(pct / 10)))
    return "■".repeat(n) + "□".repeat(10 - n)
  }

  function volts(mv) { return mv > 0 ? (mv / 1000).toFixed(2) + " V" : "" }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(1000))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.hasKb && ((direction > 0 && root.tab === "mouse") || (direction < 0 && root.tab === "keyboard")))
          root.tab = root.tab === "mouse" ? "keyboard" : "mouse"
        else
          root.switchPanel(direction)
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: root.kbTab ? "GMMK Pro" : "Glorious Model O3"
          meta: root.kbTab ? "USB · stock firmware" : (root.w ? root.w.connectionText + " · read " + root.w.ageText() : "")
          detail: root.kbTab ? "" : (root.w && root.w.charging ? "CHARGING" : (root.w && root.w.low ? "SWAP BATTERY" : ""))
          iconComponent: Component {
            Text {
              text: root.kbTab ? "󰌌" : "󰍽"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        ButtonGroup {
          visible: root.hasKb
          options: [{ value: "mouse", label: "󰍽  Mouse" }, { value: "keyboard", label: "󰌌  Keyboard" }]
          value: root.tab
          focusable: false
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onChanged: function(v) { root.tab = v }
        }

        Column {
          id: row
          width: parent.width

          Column {
            id: mouseCol
            visible: !root.kbTab
            width: row.width
            spacing: Style.space(14)

            PanelSeparator { foreground: root.contentForeground }

            MeterRow {
              icon: root.w ? root.w.batteryIcon(root.w.level, root.w.charging) : ""
              label: "MOUSE BATTERY"
              percent: root.w ? Math.max(0, root.w.level) : 0
              caption: root.w ? root.w.statusText(root.w.status) + "  " + root.volts(root.w.mv) : ""
            }

            MeterRow {
              visible: root.w && root.w.hasDock
              icon: "󰂄"
              label: "DOCK BATTERY"
              percent: root.w && root.w.dockStatus !== 0 ? Math.max(0, root.w.dockLevel) : 0
              caption: root.w
                ? (root.w.dockLevel < 0 ? "no reading yet" : root.w.dockStatusText()
                   + (root.w.dockStatus !== 0 ? "  " + root.volts(root.w.dockMv) : ""))
                : ""
            }

            Text {
              visible: root.w && !root.w.hasDock
              width: parent.width
              wrapMode: Text.WordWrap
              text: "󰂄  DOCK: not connected to this PC" + (root.w && root.w.hasCable ? " (mouse is on its cable)" : "")
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            MeterRow {
              icon: "󰁹"
              label: "BUILT-IN BACKUP"
              percent: root.w ? Math.max(0, root.w.backupLevel) : 0
              caption: root.w ? root.w.statusText(root.w.backupStatus) + "  " + root.volts(root.w.backupMv) : ""
            }

            PanelSeparator { foreground: root.contentForeground }

            PanelSectionHeader {
              width: parent.width
              text: "LIGHTING"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.w
                ? (root.w.applying ? "Applying…"
                   : "Now: " + (root.w.lightEffect || "unknown")
                     + (root.w.lightColor ? " " + root.w.lightColor : "")
                     + (root.w.lightBrightness >= 0 ? " @" + root.w.lightBrightness + "%" : ""))
                  + "   · colour follows the theme"
                : ""
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: [
                [{ value: "solid", label: "Solid" }, { value: "breathing-single", label: "Breathe" },
                 { value: "seamless-breathing", label: "Seamless" }, { value: "ghost", label: "Ghost" }],
                [{ value: "fairies", label: "Fairies" }, { value: "cascade", label: "Cascade" },
                 { value: "prismatic", label: "Prismatic" }, { value: "wave", label: "Wave" }],
                [{ value: "ripple", label: "Ripple" }, { value: "breathing", label: "Breathe+" },
                 { value: "rainbow", label: "Rainbow" }, { value: "off", label: "Off" }]
              ]
              delegate: ButtonGroup {
                required property var modelData
                options: modelData
                value: root.w ? root.w.prefEffect : ""
                focusable: false
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onChanged: function(v) {
                  if (root.w) root.w.setLighting(v, root.w.prefSpeed, root.w.prefBrightness)
                }
              }
            }

            Text {
              text: "Speed  " + (root.w ? root.w.prefSpeed : "")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
            PanelSlider {
              width: parent.width
              bar: root.bar
              minimum: 10
              maximum: 100
              step: 5
              integer: true
              value: root.w ? root.w.prefSpeed : 50
              onReleased: function(v) {
                if (root.w) root.w.setLighting(root.w.prefEffect, Math.round(v), root.w.prefBrightness)
              }
            }

            Item {
              width: parent.width
              implicitHeight: brightLabel.implicitHeight
              Text {
                id: brightLabel
                text: "Brightness  " + (root.w && root.w.prefBrightness >= 0 ? root.w.prefBrightness + "%" : "theme")
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }
              ButtonGroup {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "theme", label: "Theme" }, { value: "custom", label: "Custom" }]
                value: root.w && root.w.prefBrightness >= 0 ? "custom" : "theme"
                focusable: false
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onChanged: function(v) {
                  if (!root.w) return
                  root.w.setLighting(root.w.prefEffect, root.w.prefSpeed,
                                     v === "theme" ? -1 : Math.max(10, root.w.lightBrightness))
                }
              }
            }
            PanelSlider {
              visible: root.w && root.w.prefBrightness >= 0
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.w && root.w.prefBrightness >= 0 ? root.w.prefBrightness : 70
              onReleased: function(v) {
                if (root.w) root.w.setLighting(root.w.prefEffect, root.w.prefSpeed, Math.round(v))
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Swap at 30% or below (the mouse flashes red). Right-click the bar item to re-read."
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
          }

          Column {
            id: kbCol
            visible: root.kbTab
            width: row.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "LIGHTING"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.w ? (root.w.kbApplying ? "Applying…" : (root.w.kbResult || "Saved: " + root.w.kbEffect) + "   · colour follows the theme") : ""
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: [
                [{ value: "solid", label: "Solid" }, { value: "breathing", label: "Breathe" },
                 { value: "wave", label: "Wave" }, { value: "spiral", label: "Spiral" }],
                [{ value: "ripple", label: "Ripple" }, { value: "trace", label: "Trace" },
                 { value: "fast-trace", label: "Fast trace" }, { value: "acid", label: "Acid" }],
                [{ value: "matrix", label: "Matrix" }, { value: "matrix-3", label: "Matrix 3" },
                 { value: "heartbeat", label: "Heartbeat" }, { value: "pingpong", label: "Pingpong" }],
                [{ value: "digital-times", label: "Digital" }, { value: "kamehameha", label: "Kamehameha" },
                 { value: "surmount", label: "Surmount" }],
                [{ value: "glorious", label: "Glorious" }, { value: "wave-2", label: "Wave 2" },
                 { value: "rainbow", label: "Rainbow" }, { value: "off", label: "Off" }]
              ]
              delegate: ButtonGroup {
                required property var modelData
                options: modelData
                value: root.w ? root.w.kbEffect : ""
                focusable: false
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onChanged: function(v) {
                  if (root.w) root.w.setKeyboardLighting(v, root.w.kbSpeed, root.w.kbBrightness)
                }
              }
            }

            Text {
              text: "Speed  " + (root.w ? root.w.kbSpeed : "")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
            PanelSlider {
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.w ? root.w.kbSpeed : 50
              onReleased: function(v) {
                if (root.w) root.w.setKeyboardLighting(root.w.kbEffect, Math.round(v), root.w.kbBrightness)
              }
            }

            Item {
              width: parent.width
              implicitHeight: kbBrightLabel.implicitHeight
              Text {
                id: kbBrightLabel
                text: "Brightness  " + (root.w && root.w.kbBrightness >= 0 ? root.w.kbBrightness + "%" : "theme")
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }
              ButtonGroup {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                options: [{ value: "theme", label: "Theme" }, { value: "custom", label: "Custom" }]
                value: root.w && root.w.kbBrightness >= 0 ? "custom" : "theme"
                focusable: false
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onChanged: function(v) {
                  if (root.w) root.w.setKeyboardLighting(root.w.kbEffect, root.w.kbSpeed, v === "theme" ? -1 : 70)
                }
              }
            }
            PanelSlider {
              visible: root.w && root.w.kbBrightness >= 0
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.w && root.w.kbBrightness >= 0 ? root.w.kbBrightness : 70
              onReleased: function(v) {
                if (root.w) root.w.setKeyboardLighting(root.w.kbEffect, root.w.kbSpeed, Math.round(v))
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "The keyboard can't report its lighting; this is your last choice. A few effects, such as Wave 2, keep their own colours."
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Item { width: parent.width; height: Style.space(4) }
      }
    }
  }

  component MeterRow: Column {
    id: meter
    required property string icon
    required property string label
    required property int percent
    property string caption: ""
    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(headerIcon.implicitHeight, headerLabel.implicitHeight, headerPct.implicitHeight)

      Text {
        id: headerIcon
        text: meter.icon
        color: meter.percent <= 30 ? "#ff6b6b" : root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        width: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: headerLabel
        text: meter.label
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.left: headerIcon.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: headerPct
        text: meter.percent + "%"
        color: root.dim
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      width: parent.width
      text: "[" + root.blockBar(meter.percent) + "]" + (meter.caption !== "" ? "   " + meter.caption : "")
      color: root.dim
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }
}
