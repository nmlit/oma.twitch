# oma.twitch

Plingar och visar en notis när dina Twitch-kanaler går live – **utan inloggning**.
Ikonen i Omarchy-baren lyser lila med antal när någon av kanalerna sänder, och panelen visar alla kanaler med status.

Plugin-id: `oma.twitch`

## Installation

### Installera från GitHub

```bash
omarchy plugin add https://github.com/nmlit/oma.twitch.git --enable
```

Widgeten hamnar till höger i baren. Vill du flytta den:

```bash
omarchy bar move oma.twitch --section right
```

Lägg till kanaler (kommaseparerat) – eller gör det direkt i panelen:

```bash
omarchy bar set oma.twitch channels "kanal1,kanal2"
```

Uppdatera:

```bash
omarchy plugin update oma.twitch --yes
omarchy-restart-shell
```

## Användning

| Input | Effekt |
|---|---|
| Vänsterklick | Öppna/stäng panelen |
| Mittenklick | Uppdatera nu |
| Högerklick | Öppna kanalen om exakt en är live, annars panelen |

- **Baren:** Twitch-ikonen är nedtonad när ingen sänder. När någon går live blir den lila med antal (t.ex. ikon + 2). Tooltip listar vilka som är live, spel och hur länge de sänt.
- **Notis + pling:** när en kanal går från offline till live kommer notisen ”🔴 kanal är live!” med titel och spel. Klicka på notisen (eller ”Öppna på Twitch”) så öppnas `twitch.tv/kanal` i webbläsaren.
- **Panelen:** alla kanaler med live/offline, hur länge de sänt, tittare, spel och titel. Klicka på en kanal för att öppna den, ✕ tar bort den. Skriv ett kanalnamn eller klistra in en twitch.tv-länk i fältet och tryck Enter för att lägga till. ”Uppdatera” hämtar direkt och ”Testa notis” visar en testnotis med ljud.
- Tangenter i panelen: `r` uppdatera · `a` lägg till kanal · `Esc` stäng.

## Inställningar

```bash
omarchy bar set oma.twitch channels "shroud,xqc"     # kanaler (namn eller twitch.tv-länkar)
omarchy bar set oma.twitch pollMinutes 2             # hur ofta (min), minst 1
omarchy bar set oma.twitch soundEnabled true         # pling på/av
omarchy bar set oma.twitch soundFile "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga"
omarchy bar set oma.twitch notifyOnStartup false     # notis vid start för kanaler som redan är live
```

- `notifyOnStartup` är av som standard: kanaler som redan sänder när datorn/skalet startar markeras bara som live, utan pling. Samma sak när du lägger till en kanal som redan är live.
- Går en ström ner och upp igen inom 10 minuter (avbrott/omstart av strömmen) kommer ingen ny notis.
- Ljudet spelas med `pw-play` (eller `paplay`). Saknas filen används `bell.oga` från `sound-theme-freedesktop`.
- Inställningarna sparas i `~/.config/omarchy/shell.json`.

## Datakälla (ingen inloggning)

- **Primärt: [DecAPI](https://decapi.me)**, en öppen tjänst som svarar på Twitch-frågor utan nyckel:
  `https://decapi.me/twitch/uptime/<kanal>` ger `<kanal> is offline` eller t.ex. `1 hour, 5 minutes, 3 seconds`.
  Titel (`/twitch/title/<kanal>`) och spel (`/twitch/game/<kanal>`) hämtas bara för kanaler som är live,
  plus en gång vid start/ny kanal för att visa senaste titel och hitta kanalnamn som inte finns.
- **Reserv: Twitch publika GQL** (`gql.twitch.tv`) med samma publika Client-ID som twitch.tv-webben använder.
  Används bara för kanaler där DecAPI inte gav ett vettigt svar (fel, rate limit, nere), i ett enda anrop.
- Allt körs med `curl` (`--connect-timeout 8 --max-time 15 --retry 2 --retry-all-errors`) i `fetch.sh`. Parsning sker i `Model.js`.

## Uppstart och nätverk

Datorn startar ofta skalet innan nätverket är uppe (WoL/boot). Då visas inget fel direkt:

- Misslyckas hämtningen försöker pluginet igen efter 5 s, 10 s, 20 s, 30 s, 1 min och 2 min. Panelen visar ”Väntar på nätverk…” under tiden.
- Senast kända status behålls om en senare hämtning misslyckas, och ett misslyckat svar räknas aldrig som ”offline” (så ingen falsk notis när nätet kommer tillbaka).
- Först när alla försök misslyckats visas ett mjukt meddelande i panelen, och vanlig uppdatering fortsätter.

## Kommandon (IPC)

```bash
omarchy-shell -q oma.twitch refresh   # hämta direkt
omarchy-shell -q oma.twitch test      # testnotis med ljud
omarchy-shell -q oma.twitch toggle    # öppna / stäng panelen
```

## Filstruktur

```
manifest.json
Service.qml     delad bevakare: hämtning, omförsök, notiser, ljud
BarWidget.qml   ikonen i baren
Panel.qml       kanallista, lägg till/ta bort, uppdatera
Model.js        parsning och logik (offline -> live, texter)
fetch.sh        curl mot DecAPI (+ GQL-reserv)
README.md
LICENSE
```

## Licens

MIT
