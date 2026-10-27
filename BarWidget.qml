import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root

  readonly property string pluginId: "oma.twitch"
  readonly property color twitchPurple: "#9146FF"
  // Live-färg: temats röda (color1/red i colors.toml) via Commons.Color.urgent.
  readonly property color liveColor: Commons.Color.urgent
  moduleName: pluginId

  readonly property var watcher: bar && bar.shell ? bar.shell.serviceFor(pluginId) : null
  readonly property int liveCount: watcher ? watcher.liveCount : 0
  readonly property bool anyLive: liveCount > 0
  readonly property string glyph: watcher ? watcher.twitchGlyph : "\uf1e8"
  readonly property bool showsCount: anyLive && !vertical
  readonly property string tooltip: watcher
    ? Model.tooltip(watcher.channels, watcher.states, watcher.now)
    : "Twitch"

  // Skicka inställningarna till tjänsten (en delad bevakare för alla barer).
  function pushSettings() {
    if (watcher && typeof watcher.configure === "function") watcher.configure(root.settings || {})
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function handlePress(button) {
    if (button === Qt.MiddleButton) { if (watcher) watcher.refresh() }
    else if (button === Qt.RightButton) {
      var live = watcher ? watcher.live : []
      if (live.length === 1) watcher.openChannel(live[0].channel)
      else root.togglePanel()
    }
    else root.togglePanel()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }

  visible: watcher !== null
  implicitWidth: showsCount ? textButton.implicitWidth : iconButton.implicitWidth
  implicitHeight: showsCount ? textButton.implicitHeight : iconButton.implicitHeight

  onBarChanged: { injectPanel(); pushSettings() }
  onSettingsChanged: { injectPanel(); pushSettings() }
  onWatcherChanged: pushSettings()
  Component.onCompleted: pushSettings()

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

  BarIconButton {
    id: iconButton
    anchors.fill: parent
    visible: !root.showsCount
    bar: root.bar
    text: root.glyph
    slotSize: Style.bar.statusSlot
    active: root.anyLive
    activeColor: root.liveColor
    dimmed: !root.anyLive
    tooltipText: root.tooltip
    onPressed: function(b) { root.handlePress(b) }
  }

  WidgetButton {
    id: textButton
    anchors.fill: parent
    visible: root.showsCount
    bar: root.bar
    text: root.glyph + " " + root.liveCount
    active: true
    activeColor: root.liveColor
    tooltipText: root.tooltip
    onPressed: function(b) { root.handlePress(b) }
  }
}
