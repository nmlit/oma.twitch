import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// En delad bevakare för alla skärmar/barer: hämtar status, håller tillstånd och
// skickar notis + ljud när en kanal går från offline till live. Inställningarna
// kommer från bar-widgetens post i shell.json (via configure()).
Item {
  id: root

  property var shell: null

  readonly property string pluginId: "oma.twitch"
  readonly property string twitchGlyph: "\uf1e8"
  readonly property string fetchScript: {
    var u = String(Qt.resolvedUrl("fetch.sh") || "")
    if (u.indexOf("file://") === 0) u = u.slice(7)
    return decodeURIComponent(u)
  }

  // Inställningar (sätts av BarWidget.configure)
  property bool configured: false
  property var channels: []
  property real pollMinutes: 2
  property bool soundEnabled: true
  property string soundFile: Model.DEFAULT_SOUND
  property bool notifyOnStartup: false

  // Tillstånd
  property var states: ({})
  property var memory: ({ lastLiveAt: {}, seen: {} })
  readonly property var live: Model.liveList(channels, states)
  readonly property int liveCount: live.length
  property double now: Date.now()
  property bool fetching: false
  property bool pendingPoll: false
  property bool needFull: true
  property int attempt: 0
  property string statusMessage: ""
  property double lastSuccess: 0
  property string lastChannelsKey: ""

  function configure(settings) {
    var s = settings || {}
    function pick(key, fallback) {
      var v = s[key]
      return (v === undefined || v === null || v === "") ? fallback : v
    }
    var nextChannels = Model.parseChannels(pick("channels", ""))
    var key = nextChannels.join(",")
    pollMinutes = Model.toPollMinutes(pick("pollMinutes", 2))
    soundEnabled = Model.toBool(pick("soundEnabled", true), true)
    soundFile = String(pick("soundFile", Model.DEFAULT_SOUND))
    notifyOnStartup = Model.toBool(pick("notifyOnStartup", false), false)
    var first = !configured
    configured = true
    if (first || key !== lastChannelsKey) {
      var added = false
      for (var i = 0; i < nextChannels.length; i++)
        if (channels.indexOf(nextChannels[i]) < 0) added = true
      channels = nextChannels
      lastChannelsKey = key
      if (first || added) needFull = true
      refresh()
    }
  }

  // Manuell uppdatering (panelen/mittenklick): nollställ omförsöken.
  function refresh() {
    attempt = 0
    retryTimer.stop()
    poll()
  }

  function poll() {
    now = Date.now()
    if (!configured || channels.length === 0) {
      statusMessage = configured ? "" : statusMessage
      return
    }
    if (fetchProc.running) { pendingPoll = true; return }
    var cmd = ["sh", root.fetchScript]
    if (needFull) cmd.push("--full")
    fetchProc.command = cmd.concat(channels)
    fetching = true
    fetchProc.running = true
  }

  function handleOutput(text) {
    fetching = false
    now = Date.now()
    var results = {}
    try { results = Model.parseFetchOutput(text, now) } catch (e) { results = {} }
    if (!Model.hasUsableResult(results)) {
      handleFailure()
    } else {
      attempt = 0
      retryTimer.stop()
      needFull = false
      lastSuccess = now
      statusMessage = ""
      var r = Model.applyResults(channels, states, results, memory,
        { notifyOnStartup: notifyOnStartup, now: now })
      memory = r.memory
      states = r.states
      for (var i = 0; i < r.notify.length; i++) announce(r.notify[i])
    }
    if (pendingPoll) { pendingPoll = false; Qt.callLater(poll) }
  }

  // Vid boot startar skalet ofta innan nätverket är uppe. Visa inget fel direkt:
  // försök igen efter 5 s, 10 s, 20 s, 30 s, 1 min och 2 min och behåll senast
  // kända status under tiden. Först därefter visas ett (mjukt) fel i panelen.
  function handleFailure() {
    var delay = Model.retryDelayMs(attempt)
    attempt = attempt + 1
    if (delay >= 0) {
      statusMessage = lastSuccess > 0 ? "" : "Väntar på nätverk… nytt försök om " + Math.round(delay / 1000) + " s"
      retryTimer.interval = delay
      retryTimer.restart()
      return
    }
    statusMessage = "Kunde inte nå Twitch just nu. Försöker igen vid nästa uppdatering."
  }

  function announce(state) {
    Quickshell.execDetached(Model.notifyCommand(state))
    if (soundEnabled) Quickshell.execDetached(Model.soundCommand(soundFile))
  }

  function openChannel(channel) {
    Quickshell.execDetached(["xdg-open", Model.channelUrl(channel)])
  }

  function testNotification() {
    announce({ channel: channels.length ? channels[0] : "twitch", displayName: channels.length ? channels[0] : "Test",
      title: "Testnotis från oma.twitch", game: "" })
  }

  Timer {
    id: pollTimer
    interval: Math.round(root.pollMinutes * 60 * 1000)
    running: root.configured && root.channels.length > 0
    repeat: true
    onTriggered: root.poll()
  }

  Timer {
    id: retryTimer
    interval: 5000
    repeat: false
    onTriggered: root.poll()
  }

  // Uppdaterar "live i 1 h 5 min" i panel/tooltip.
  Timer {
    interval: 30000
    running: root.liveCount > 0
    repeat: true
    onTriggered: root.now = Date.now()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      onStreamFinished: root.handleOutput(this.text)
    }
    stderr: StdioCollector {}
  }

  // omarchy-shell -q oma.twitch toggle    öppna / stäng panelen
  // omarchy-shell -q oma.twitch refresh   hämta direkt
  // omarchy-shell -q oma.twitch test      visa en testnotis med ljud
  IpcHandler {
    target: root.pluginId

    function toggle(): void { if (root.shell) root.shell.toggle(root.pluginId, "{}") }
    function refresh(): void { root.refresh() }
    function test(): void { root.testNotification() }
  }
}
