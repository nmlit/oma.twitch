import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Panel: kanallista med live/offline, klick öppnar kanalen, lägg till/ta bort
// kanaler och manuell uppdatering.
Panel {
  id: root
  moduleName: "oma.twitch"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var watcher: hostWidget ? hostWidget.watcher : null
  readonly property var channels: watcher ? watcher.channels : []
  readonly property var states: watcher ? watcher.states : ({})
  readonly property double now: watcher ? watcher.now : Date.now()

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.62)
  readonly property color liveColor: "#eb0400"
  readonly property color twitchPurple: "#9146FF"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string inputError: ""

  function open() {
    root.controller.show()
    if (root.watcher && !root.watcher.fetching) root.watcher.refresh()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  // Skriver kanallistan till widgetens post i shell.json (samma som
  // `omarchy bar set oma.twitch channels "a,b"`).
  function saveChannels(list) {
    var csv = Model.channelsToString(list)
    var entry = { id: root.moduleName }
    var current = root.hostWidget ? root.hostWidget.settings : root.settings
    if (current) for (var k in current) if (k !== "id") entry[k] = current[k]
    entry.channels = csv
    if (root.watcher) root.watcher.configure(entry)
    var ok = false
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      try { ok = root.bar.shell.updateEntryInline(root.moduleName, entry) !== false } catch (e) { ok = false }
    }
    if (!ok) Quickshell.execDetached(["omarchy", "bar", "set", root.moduleName, "channels", csv])
  }

  function addFromInput() {
    var parsed = Model.parseChannels(input.text)
    if (!parsed.length) {
      inputError = input.text.trim() === "" ? "" : "Ogiltigt kanalnamn (a–z, 0–9, _)"
      return
    }
    var next = root.channels.slice()
    var added = 0
    for (var i = 0; i < parsed.length; i++) {
      if (next.indexOf(parsed[i]) < 0) { next.push(parsed[i]); added++ }
    }
    if (!added) { inputError = "Kanalen finns redan i listan"; return }
    inputError = ""
    input.text = ""
    saveChannels(next)
  }

  function removeChannel(ch) {
    var next = []
    for (var i = 0; i < root.channels.length; i++) if (root.channels[i] !== ch) next.push(root.channels[i])
    saveChannels(next)
  }

  function headerStatus() {
    if (!root.watcher) return ""
    if (root.watcher.fetching) return "uppdaterar…"
    var n = root.watcher.liveCount
    if (!root.channels.length) return ""
    return n === 0 ? "ingen live" : (n === 1 ? "1 live" : n + " live")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: input.activeFocus
      onCloseRequested: root.close()
      onTextKey: function(text) {
        if (text === "r" && root.watcher) root.watcher.refresh()
        else if (text === "a" || text === "i") input.forceActiveFocus()
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(8)

        // Rubrik
        Item {
          width: parent.width
          height: Math.max(titleRow.implicitHeight, refreshButton.implicitHeight)

          Row {
            id: titleRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: "\uf1e8  Twitch"
              color: root.twitchPurple
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.headerStatus()
              color: root.watcher && root.watcher.liveCount > 0 ? root.liveColor : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Button {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Uppdatera"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            enabled: root.watcher ? !root.watcher.fetching : false
            opacity: enabled ? 1 : 0.5
            onClicked: if (root.watcher) root.watcher.refresh()
          }
        }

        Text {
          width: parent.width
          visible: !!(root.watcher && root.watcher.statusMessage)
          text: root.watcher ? root.watcher.statusMessage : ""
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.channels.length === 0
          text: "Inga kanaler ännu. Lägg till en nedan, t.ex. ”shroud” eller en twitch.tv-länk."
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Kanaler
        Repeater {
          model: root.channels

          Rectangle {
            id: rowItem
            required property string modelData
            readonly property var st: root.states[modelData] || null
            readonly property bool isLive: !!(st && st.status === "live")
            readonly property string subtitle: {
              if (!st) return ""
              var parts = []
              if (st.game) parts.push(st.game)
              if (st.title) parts.push(st.title)
              return parts.join(" · ")
            }

            width: contentColumn.width
            height: rowCol.implicitHeight + Style.space(8)
            radius: Style.cornerRadius
            color: rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent"

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.watcher) root.watcher.openChannel(rowItem.modelData)
            }

            Column {
              id: rowCol
              anchors.left: parent.left
              anchors.right: removeButton.left
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                spacing: Style.space(6)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: rowItem.isLive ? root.liveColor : "transparent"
                  border.width: rowItem.isLive ? 0 : 1
                  border.color: root.dim
                }
                Text {
                  text: rowItem.st && rowItem.st.displayName ? rowItem.st.displayName : rowItem.modelData
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: rowItem.isLive
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.statusText(rowItem.st, root.now)
                    + (rowItem.isLive && rowItem.st.viewers >= 0 ? " · " + Model.formatViewers(rowItem.st.viewers) : "")
                  color: rowItem.isLive ? root.liveColor : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Text {
                width: parent.width
                visible: rowItem.subtitle !== ""
                text: rowItem.subtitle
                color: rowItem.isLive ? root.fg : root.dim
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Button {
              id: removeButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              tooltipText: "Ta bort " + rowItem.modelData
              foreground: root.dim
              fontSize: Style.font.bodySmall
              onClicked: root.removeChannel(rowItem.modelData)
            }
          }
        }

        // Lägg till kanal
        Row {
          width: parent.width
          spacing: Style.space(6)

          Rectangle {
            width: parent.width - addButton.width - parent.spacing
            height: addButton.height
            radius: Style.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: root.inputError !== "" ? (root.bar ? root.bar.urgent : Commons.Color.urgent)
              : input.activeFocus ? root.fg : root.dim

            TextInput {
              id: input
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              verticalAlignment: TextInput.AlignVCenter
              color: root.fg
              selectionColor: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              clip: true
              onTextChanged: root.inputError = ""
              onAccepted: root.addFromInput()
              Keys.onEscapePressed: { text = ""; keyCatcher.forceActiveFocus() }

              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: input.text === "" && !input.activeFocus
                text: "Lägg till kanal (namn eller länk) + Enter"
                color: root.dim
                font: input.font
                elide: Text.ElideRight
              }
            }
          }

          Button {
            id: addButton
            text: "Lägg till"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.addFromInput()
          }
        }

        Text {
          width: parent.width
          visible: root.inputError !== ""
          text: root.inputError
          color: root.bar ? root.bar.urgent : Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          width: parent.width
          height: testButton.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.right: testButton.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.watcher
              ? "Kollar var " + root.watcher.pollMinutes + " min · ljud " + (root.watcher.soundEnabled ? "på" : "av")
              : ""
            color: root.dim
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: testButton
            anchors.right: parent.right
            text: "Testa notis"
            foreground: root.dim
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: if (root.watcher) root.watcher.testNotification()
          }
        }

        Text {
          width: parent.width
          text: "Klicka på en kanal för att öppna den · r uppdatera · a lägg till · esc stäng"
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
