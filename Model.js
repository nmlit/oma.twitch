.pragma library

// Ren logik för oma.twitch (ingen QML här, så den går att testa med node).

var RETRY_DELAYS_MS = [5000, 10000, 20000, 30000, 60000, 120000]
var RENOTIFY_COOLDOWN_MS = 10 * 60 * 1000
var DEFAULT_SOUND = "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga"
var FALLBACK_SOUND = "/usr/share/sounds/freedesktop/stereo/bell.oga"
var MAX_TEXT = 300

// Twitch-inloggningsnamn: 1–25 tecken, a–z, 0–9 och _. Tar även emot
// "https://twitch.tv/namn", "@namn" och blandade skiftlägen.
function normalizeChannel(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw).trim().toLowerCase()
  s = s.replace(/^https?:\/\//, "").replace(/^(www\.|m\.)?twitch\.tv\//, "")
  s = s.replace(/^@/, "").replace(/[\/?#].*$/, "")
  if (!/^[a-z0-9_]{1,25}$/.test(s)) return ""
  return s
}

// "a, b c;d" eller en array -> ["a","b","c","d"] utan dubbletter.
function parseChannels(value) {
  var parts = []
  if (Array.isArray(value)) parts = value
  else parts = String(value === undefined || value === null ? "" : value).split(/[\s,;]+/)
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var c = normalizeChannel(parts[i])
    if (c && out.indexOf(c) < 0) out.push(c)
  }
  return out
}

function channelsToString(list) {
  return parseChannels(list).join(",")
}

function toBool(v, fallback) {
  if (v === true || v === false) return v
  if (v === undefined || v === null || v === "") return fallback
  var s = String(v).trim().toLowerCase()
  if (s === "true" || s === "1" || s === "yes" || s === "ja" || s === "on") return true
  if (s === "false" || s === "0" || s === "no" || s === "nej" || s === "off") return false
  return fallback
}

function toPollMinutes(v) {
  var n = parseFloat(v)
  if (!(n > 0)) n = 2
  return Math.max(1, Math.min(60, n))
}

function cleanText(s) {
  var t = String(s === undefined || s === null ? "" : s).replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  if (t.length > MAX_TEXT) t = t.slice(0, MAX_TEXT - 1) + "…"
  return t
}

// DecAPI /twitch/uptime: "<kanal> is offline" eller "1 hour, 5 minutes, 3 seconds".
// Returnerar { kind: "offline" } | { kind: "live", seconds } | { kind: "unknown" }.
function classifyUptime(text, channel) {
  var s = cleanText(text)
  if (s === "") return { kind: "unknown" }
  if (/ is offline$/i.test(s)) return { kind: "offline" }
  var units = { day: 86400, hour: 3600, minute: 60, second: 1 }
  if (!/^\d+ (day|hour|minute|second)s?(, \d+ (day|hour|minute|second)s?)*$/i.test(s))
    return { kind: "unknown" }
  var total = 0
  var re = /(\d+) (day|hour|minute|second)s?/gi
  var m
  while ((m = re.exec(s)) !== null) total += parseInt(m[1], 10) * units[m[2].toLowerCase()]
  return { kind: "live", seconds: total }
}

function isDecApiError(text) {
  var s = cleanText(text)
  return s === "" || /^(user not found|error|an error|could not|no user|invalid|rate limit|too many)/i.test(s)
}

function emptyState(channel) {
  return { channel: channel, displayName: channel, status: "unknown", title: "", game: "",
    viewers: -1, startedAt: 0, source: "", checkedAt: 0 }
}

// Tolkar utdata från fetch.sh:
//   D<TAB>kanal<TAB>uptime<TAB>titel<TAB>spel       (DecAPI)
//   G<TAB>kanal1,kanal2<TAB><json>                  (Twitch GQL-reserv)
// Returnerar { kanal: state }. Kanaler som inte gick att avgöra får status "unknown".
function parseFetchOutput(text, nowMs) {
  var now = Number(nowMs) || Date.now()
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("D\t") === 0) {
      var f = line.split("\t")
      var ch = normalizeChannel(f[1])
      if (!ch) continue
      var st = emptyState(ch)
      var u = classifyUptime(f[2], ch)
      var title = cleanText(f[3])
      var game = cleanText(f[4])
      st.checkedAt = now
      st.source = "decapi"
      if (u.kind === "offline") {
        if (/^user not found/i.test(title)) st.status = "notfound"
        else st.status = "offline"
      } else if (u.kind === "live") {
        st.status = "live"
        st.startedAt = now - u.seconds * 1000
      }
      if (st.status !== "unknown") {
        if (!isDecApiError(title)) st.title = title
        if (!isDecApiError(game)) st.game = game
      }
      out[ch] = st
    } else if (line.indexOf("G\t") === 0) {
      var tab2 = line.indexOf("\t", 2)
      if (tab2 < 0) continue
      var logins = line.slice(2, tab2).split(",")
      var parsed = parseGql(line.slice(tab2 + 1), logins, now)
      for (var k in parsed) {
        if (!out[k] || out[k].status === "unknown") out[k] = parsed[k]
      }
    }
  }
  return out
}

// Twitch GQL (publik webb-Client-ID, ingen inloggning). users[] kommer i samma
// ordning som logins; null = kanalen finns inte.
function parseGql(jsonText, logins, nowMs) {
  var out = {}
  var data
  try { data = JSON.parse(jsonText) } catch (e) { return out }
  if (Array.isArray(data)) data = data[0]
  var users = data && data.data && data.data.users
  if (!Array.isArray(users)) return out
  for (var i = 0; i < logins.length && i < users.length; i++) {
    var ch = normalizeChannel(logins[i])
    if (!ch) continue
    var st = emptyState(ch)
    st.checkedAt = Number(nowMs) || Date.now()
    st.source = "gql"
    var u = users[i]
    if (u === null) {
      st.status = "notfound"
    } else if (u && typeof u === "object") {
      if (u.displayName) st.displayName = cleanText(u.displayName)
      var s = u.stream
      if (s && typeof s === "object") {
        st.status = "live"
        var t = Date.parse(s.createdAt)
        st.startedAt = isNaN(t) ? st.checkedAt : t
        st.title = cleanText(s.title)
        st.game = s.game && s.game.displayName ? cleanText(s.game.displayName) : ""
        st.viewers = typeof s.viewersCount === "number" ? s.viewersCount : -1
      } else {
        st.status = "offline"
      }
    }
    out[ch] = st
  }
  return out
}

function hasUsableResult(results) {
  for (var k in results) if (results[k] && results[k].status !== "unknown") return true
  return false
}

// Slår ihop nya resultat med tidigare tillstånd och avgör vilka kanaler som
// precis har gått live (offline -> live).
//   prev:     { kanal: state }   tidigare tillstånd
//   results:  { kanal: state }   nya resultat (unknown = behåll tidigare)
//   memory:   { lastLiveAt: { kanal: ms }, seen: { kanal: true } }
//   opts:     { notifyOnStartup: bool, now: ms }
// Returnerar { states, notify: [state], memory }.
function applyResults(channels, prev, results, memory, opts) {
  var now = (opts && Number(opts.now)) || Date.now()
  var notifyOnStartup = !!(opts && opts.notifyOnStartup)
  var mem = {
    lastLiveAt: copyMap(memory && memory.lastLiveAt),
    seen: copyMap(memory && memory.seen)
  }
  var states = {}
  var notify = []
  for (var i = 0; i < channels.length; i++) {
    var ch = channels[i]
    var old = prev && prev[ch] ? prev[ch] : null
    var r = results ? results[ch] : null
    if (!r || r.status === "unknown") {
      states[ch] = old ? copyState(old, { stale: true }) : emptyState(ch)
      continue
    }
    var st = copyState(r, { stale: false })
    // DecAPI:s uptime säger "offline" även för kanaler som inte finns; behåll
    // "finns inte" från en tidigare fullständig kontroll.
    if (st.status === "offline" && old && old.status === "notfound" && st.source === "decapi" && !st.title)
      st.status = "notfound"
    // Behåll senaste kända titel/spel när DecAPI bara gav offline.
    if (st.status === "offline" && old) {
      if (!st.title && old.title) st.title = old.title
      if (!st.game && old.game) st.game = old.game
      if (st.displayName === ch && old.displayName) st.displayName = old.displayName
    }
    if (st.status === "live") {
      var firstSeen = !mem.seen[ch]
      var wasLive = old && old.status === "live"
      var last = mem.lastLiveAt[ch] || 0
      var recentlyLive = last > 0 && (now - last) < RENOTIFY_COOLDOWN_MS
      if (!wasLive && !recentlyLive && (!firstSeen || notifyOnStartup)) notify.push(st)
      mem.lastLiveAt[ch] = now
    }
    mem.seen[ch] = true
    states[ch] = st
  }
  return { states: states, notify: notify, memory: mem }
}

function copyMap(m) {
  var o = {}
  if (m) for (var k in m) o[k] = m[k]
  return o
}

function copyState(s, extra) {
  var o = {}
  for (var k in s) o[k] = s[k]
  if (extra) for (var e in extra) o[e] = extra[e]
  return o
}

function liveList(channels, states) {
  var out = []
  for (var i = 0; i < channels.length; i++) {
    var st = states[channels[i]]
    if (st && st.status === "live") out.push(st)
  }
  return out
}

// 4980 s -> "1 h 23 min", 300 s -> "5 min"
function formatDuration(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (h > 0) return h + " h " + m + " min"
  if (m > 0) return m + " min"
  return "nyss"
}

function uptimeText(state, nowMs) {
  if (!state || state.status !== "live" || !state.startedAt) return ""
  return formatDuration(((Number(nowMs) || Date.now()) - state.startedAt) / 1000)
}

function statusText(state, nowMs) {
  if (!state) return "okänd"
  if (state.status === "live") {
    var u = uptimeText(state, nowMs)
    return "live" + (u ? " · " + u : "")
  }
  if (state.status === "offline") return "offline"
  if (state.status === "notfound") return "finns inte"
  return "hämtar…"
}

function formatViewers(n) {
  if (!(n >= 0)) return ""
  if (n >= 1000) return (Math.round(n / 100) / 10).toString().replace(".", ",") + "k tittare"
  return n + " tittare"
}

function notificationTitle(state) {
  return "🔴 " + (state.displayName || state.channel) + " är live!"
}

function notificationBody(state) {
  var parts = []
  if (state.title) parts.push(state.title)
  if (state.game) parts.push("🎮 " + state.game)
  if (!parts.length) parts.push("twitch.tv/" + state.channel)
  return parts.join("\n")
}

function tooltip(channels, states, nowMs) {
  if (!channels.length) return "Twitch – inga kanaler. Klicka för att lägga till."
  var live = liveList(channels, states)
  if (!live.length) return "Twitch – ingen av " + channels.length + " kanaler är live"
  var lines = ["Live på Twitch:"]
  for (var i = 0; i < live.length; i++) {
    var st = live[i]
    var line = "🔴 " + (st.displayName || st.channel)
    if (st.game) line += " – " + st.game
    var u = uptimeText(st, nowMs)
    if (u) line += " (" + u + ")"
    lines.push(line)
  }
  return lines.join("\n")
}

function retryDelayMs(attempt) {
  var n = Number(attempt)
  if (!(n >= 0) || n >= RETRY_DELAYS_MS.length) return -1
  return RETRY_DELAYS_MS[Math.floor(n)]
}

function channelUrl(channel) {
  return "https://www.twitch.tv/" + normalizeChannel(channel)
}

// Spelar ljudfilen med pw-play, annars paplay. Faller tillbaka till bell.oga.
function soundCommand(file) {
  var f = String(file || "") || DEFAULT_SOUND
  return ["sh", "-c",
    "f=\"$1\"; [ -r \"$f\" ] || f=\"$2\"; [ -r \"$f\" ] || f=\"$3\"; " +
    "if command -v pw-play >/dev/null 2>&1; then exec pw-play \"$f\"; else exec paplay \"$f\"; fi",
    "oma.twitch-sound", f, DEFAULT_SOUND, FALLBACK_SOUND]
}

// notify-send väntar (--wait) på klick; klick på notisen eller "Öppna på Twitch"
// öppnar kanalen i webbläsaren med xdg-open.
function notifyCommand(state) {
  return ["sh", "-c",
    "a=$(notify-send -a oma.twitch -i media-record --wait " +
    "--action=default='Öppna' --action=open='Öppna på Twitch' -- \"$2\" \"$3\" 2>/dev/null); " +
    "case \"$a\" in default|open) xdg-open \"$1\" >/dev/null 2>&1 ;; esac",
    "oma.twitch-notify", channelUrl(state.channel), notificationTitle(state), notificationBody(state)]
}
