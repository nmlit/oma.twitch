#!/bin/sh
# oma.twitch – hämtar live-status utan inloggning.
#
#   sh fetch.sh [--full] kanal1 kanal2 ...
#
# Primär källa: DecAPI (https://decapi.me), en öppen proxy mot Twitch-API:t.
#   /twitch/uptime/<kanal>  -> "<kanal> is offline" eller "1 hour, 5 minutes, 3 seconds"
#   /twitch/title/<kanal>, /twitch/game/<kanal> hämtas bara för kanaler som är live
#   (eller för alla med --full, t.ex. första gången, för att hitta kanaler som inte finns).
# Reserv: kanaler där DecAPI inte gav ett tolkbart svar frågas i ett enda anrop mot
# Twitch publika GQL-endpoint med webbklientens publika Client-ID (ingen inloggning).
#
# Utdata (tolkas av Model.js):
#   D<TAB>kanal<TAB>uptime<TAB>titel<TAB>spel
#   G<TAB>kanal1,kanal2<TAB><json>

full=0
if [ "$1" = "--full" ]; then full=1; shift; fi
[ $# -gt 0 ] || exit 0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/oma.twitch.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM HUP

UA="oma.twitch/1.0 (+https://github.com/nmlit/oma.twitch)"
GQL_CLIENT_ID="kimne78kx3ncx6brgo4mv6wki5h1ko"
DECAPI="${OMA_TWITCH_DECAPI:-https://decapi.me}"

get() {
  curl -fsSL --compressed --connect-timeout 8 --max-time 15 \
    --retry 2 --retry-delay 2 --retry-all-errors -A "$UA" "$1" 2>/dev/null \
    | head -c 2000 | tr '\t\r\n' '   '
}

looks_ok() {
  case "$1" in
    *" is offline") return 0 ;;
    [0-9]*" second"*|[0-9]*" minute"*|[0-9]*" hour"*|[0-9]*" day"*) return 0 ;;
  esac
  return 1
}

one() {
  c=$1
  u=$(get "$DECAPI/twitch/uptime/$c")
  t=""
  g=""
  if looks_ok "$u"; then
    case "$u" in
      *" is offline") [ "$full" = 1 ] && { t=$(get "$DECAPI/twitch/title/$c"); g=$(get "$DECAPI/twitch/game/$c"); } ;;
      *) t=$(get "$DECAPI/twitch/title/$c"); g=$(get "$DECAPI/twitch/game/$c") ;;
    esac
  fi
  printf 'D\t%s\t%s\t%s\t%s\n' "$c" "$u" "$t" "$g" > "$tmp/d.$c"
}

chans=""
for c in "$@"; do
  case "$c" in ""|*[!a-z0-9_]*) continue ;; esac
  chans="$chans $c"
  one "$c" &
done
wait

failed=""
for c in $chans; do
  [ -f "$tmp/d.$c" ] || continue
  cat "$tmp/d.$c"
  u=$(cut -f3 "$tmp/d.$c")
  looks_ok "$u" || failed="$failed $c"
done

if [ -n "$failed" ]; then
  list=""
  names=""
  for c in $failed; do
    list="$list\\\"$c\\\","
    names="$names$c,"
  done
  list=${list%,}
  names=${names%,}
  body="{\"query\":\"query{users(logins:[$list]){login displayName stream{createdAt title viewersCount game{displayName}}}}\"}"
  json=$(curl -fsSL --compressed --connect-timeout 8 --max-time 15 --retry 2 --retry-delay 2 --retry-all-errors \
    -A "$UA" -H "Client-ID: $GQL_CLIENT_ID" -H "Content-Type: application/json" \
    --data "$body" https://gql.twitch.tv/gql 2>/dev/null | head -c 200000 | tr '\t\r\n' '   ')
  [ -n "$json" ] && printf 'G\t%s\t%s\n' "$names" "$json"
fi
exit 0
