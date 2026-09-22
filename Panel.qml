import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.wouldja.fans"
  ipcTarget: "io.github.wouldja.fans"

  property bool available: false
  property string mode: "auto"
  property int manual: 40
  property var duties: [25, 45, 65, 85, 100]
  property int cpuTemp: 0
  property int gpuTemp: 0
  property int cpuRpm: 0
  property int gpuRpm: 0
  property int hwDuty: 0
  property int duty: 0
  property bool loaded: false

  property real wheelAccumulator: 0
  property bool persistQueued: false
  property bool liveQueued: false
  property var pendingPayload: ({})

  property string focusSection: "mode"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property string iconGlyph: String.fromCodePoint(0xF0210)
  readonly property string applyBin: {
    var url = String(Qt.resolvedUrl("apply.py"))
    return url.indexOf("file://") === 0 ? url.slice(7) : url
  }

  function currentState() {
    return {
      available: root.available,
      mode: root.mode,
      manual: root.manual,
      duties: root.duties,
      cpuTemp: root.cpuTemp,
      gpuTemp: root.gpuTemp,
      cpuRpm: root.cpuRpm,
      gpuRpm: root.gpuRpm,
      hwDuty: root.hwDuty,
      duty: root.duty
    }
  }

  function applyPath() {
    var path = root.applyBin
    if (path.indexOf("%") !== -1) {
      try { path = decodeURIComponent(path) } catch (e) {}
    }
    return path
  }

  function applyParsed(parsed) {
    if (!parsed) return
    root.available = parsed.available === true
    root.mode = parsed.mode || "auto"
    root.manual = parsed.manual
    root.duties = parsed.duties
    applySensors(parsed)
    root.loaded = true
  }

  function applySensors(parsed) {
    if (!parsed) return
    root.available = parsed.available === true
    root.cpuTemp = parsed.cpuTemp
    root.gpuTemp = parsed.gpuTemp
    root.cpuRpm = parsed.cpuRpm
    root.gpuRpm = parsed.gpuRpm
    root.hwDuty = parsed.hwDuty
    root.duty = parsed.duty
    root.loaded = true
  }

  function refreshSensors() {
    if (sensorProc.running) return
    sensorProc.command = ["python3", applyPath(), "sensors"]
    sensorProc.running = true
  }

  function restore() {
    if (restoreProc.running) return
    restoreProc.command = ["python3", applyPath(), "restore"]
    restoreProc.running = true
  }

  function queueApply(kind) {
    root.pendingPayload = {
      mode: root.mode,
      manual: root.manual,
      duties: root.duties
    }
    if (kind === "live") root.liveQueued = true
    else root.persistQueued = true
    if (!setProc.running) flushApply()
  }

  function flushApply() {
    if (!root.persistQueued && !root.liveQueued) return
    root.persistQueued = false
    root.liveQueued = false
    setProc.command = ["python3", applyPath(), "set", Model.statePayload(root.pendingPayload)]
    setProc.running = true
  }

  function setMode(mode) {
    root.mode = mode
    queueApply("apply")
  }

  function setManual(value, live) {
    root.manual = Model.clamp(value, 25, 100)
    root.mode = "manual"
    queueApply(live ? "live" : "apply")
  }

  function setDuty(index, value, live) {
    var next = Model.normalizeDuties(root.duties)
    next[index] = Model.clamp(value, 0, 100)
    root.duties = next
    root.mode = "curve"
    queueApply(live ? "live" : "apply")
  }

  function nudgeManual(steps) {
    if (root.mode !== "manual") return
    setManual(root.manual + steps * 5, false)
  }

  function moveCursor(delta) {
    var count = Model.modes.length
    root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + delta))
    root.focusSection = "mode"
  }

  function activateCursor() {
    if (root.selectedIndex >= 0 && root.selectedIndex < Model.modes.length)
      setMode(Model.modes[root.selectedIndex].value)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: restore()

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refreshSensors()
  }

  onOpenedChanged: if (opened) root.refreshSensors()

  Process {
    id: sensorProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySensors(Model.parseState(text))
    }
  }

  Process {
    id: restoreProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyParsed(Model.parseState(text))
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySensors(Model.parseState(text))
    }
    onRunningChanged: {
      if (running) return
      if (root.persistQueued || root.liveQueued) root.flushApply()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    tooltipText: root.cpuTemp > 0 ? "Fans  " + root.cpuTemp + "°C" : "Fans"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.setMode("auto")
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.nudgeManual(wheel.steps)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: "Fans"
            meta: Model.heroMeta({
              available: root.available,
              mode: root.mode,
              cpuTemp: root.cpuTemp,
              cpuRpm: root.cpuRpm
            })
            detail: root.loaded && !root.available ? "No driver" : ""
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: heroIcon
          }

          Row {
            width: parent.width
            spacing: Style.space(16)

            Column {
              spacing: Style.space(2)
              Text {
                text: "CPU"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: (root.cpuTemp > 0 ? root.cpuTemp + "°C" : "—") + (root.cpuRpm > 0 ? "   " + root.cpuRpm + " rpm" : "")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
              }
            }

            Column {
              spacing: Style.space(2)
              visible: root.gpuTemp > 0 || root.gpuRpm > 0
              Text {
                text: "GPU"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: (root.gpuTemp > 0 ? root.gpuTemp + "°C" : "—") + (root.gpuRpm > 0 ? "   " + root.gpuRpm + " rpm" : "")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.loaded && !root.available
              ? "The fan controller is not loaded, so these controls cannot reach the fans yet."
              : Model.blurb(root.mode)
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.spacing.xs

            Repeater {
              model: Model.modes

              Button {
                required property var modelData
                required property int index
                width: parent.width
                text: modelData.label
                fontSize: Style.font.body
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                selected: root.mode === modelData.value
                hasCursor: root.cursorActive && root.focusSection === "mode" && root.selectedIndex === index
                onClicked: root.setMode(modelData.value)
                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "mode"
                  root.selectedIndex = index
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground; visible: root.mode === "manual" || root.mode === "curve" }

          SliderSection {
            visible: root.mode === "manual"
            width: parent.width
            sectionId: "manual"
            title: "SPEED"
            minimum: 25
            maximum: 100
            step: 5
            value: root.manual
            valueText: Math.round(dragging ? liveValue : root.manual) + "%"
            onMoved: function(v) { root.setManual(v, true) }
            onReleased: function(v) { root.setManual(v, false) }
          }

          Column {
            visible: root.mode === "curve"
            width: parent.width
            spacing: Style.space(12)

            Repeater {
              model: Model.points

              SliderSection {
                required property int modelData
                required property int index
                width: parent.width
                sectionId: "curve" + index
                title: modelData + "°C"
                minimum: 0
                maximum: 100
                step: 5
                value: root.duties[index]
                valueText: Math.round(dragging ? liveValue : root.duties[index]) + "%"
                onMoved: function(v) { root.setDuty(index, v, true) }
                onReleased: function(v) { root.setDuty(index, v, false) }
              }
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }

  Component {
    id: heroIcon
    Text {
      textFormat: Text.PlainText
      text: root.iconGlyph
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.display
    }
  }

  component SliderSection: Column {
    id: sliderSection
    required property string sectionId
    required property string title
    required property string valueText
    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 5
    property alias dragging: slider.dragging
    property alias liveValue: slider.liveValue
    signal moved(real value)
    signal released(real value)

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(header.implicitHeight, valueLabel.implicitHeight)

      PanelSectionHeader {
        id: header
        text: sliderSection.title
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueLabel
        textFormat: Text.PlainText
        text: sliderSection.valueText
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    CursorSurface {
      width: parent.width
      height: slider.implicitHeight + Style.spacing.controlGap
      hasCursor: root.cursorActive && root.focusSection === sliderSection.sectionId
      foreground: root.bar.foreground
      outline: true

      PanelSlider {
        id: slider
        bar: root.bar
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        minimum: sliderSection.minimum
        maximum: sliderSection.maximum
        step: sliderSection.step
        integer: true
        value: sliderSection.value
        onMoved: function(v) { sliderSection.moved(v) }
        onReleased: function(v) { sliderSection.released(v) }
      }

      HoverHandler {
        onHoveredChanged: if (hovered) {
          root.cursorActive = true
          root.focusSection = sliderSection.sectionId
          root.selectedIndex = -1
        }
      }
    }
  }
}
