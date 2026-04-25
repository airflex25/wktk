#!/usr/bin/env bash
# 시그널링 이벤트 이름이 서버/클라이언트/문서에서 모두 정의되어 있는지 빠르게 확인.
# 사용: bash skills/wktk-dev/scripts/check-protocol-sync.sh
# 결과: 한쪽에만 있는 이벤트가 있으면 화면에 출력.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SERVER="$ROOT/server/src/signaling.js"
CLIENT="$ROOT/android/app/src/main/java/com/wktk/signaling/SignalingClient.kt"
PROTOCOL="$ROOT/docs/protocol.md"

# 매우 단순한 추출: on('event' / emit('event' 패턴
grep_events() {
  grep -oE "(on|emit)\(['\"][a-z:_-]+['\"]" "$1" | grep -oE "['\"][a-z:_-]+['\"]" | tr -d \"\' | sort -u
}

server_events=$(grep_events "$SERVER" || true)
client_events=$(grep_events "$CLIENT" || true)

echo "[server events]"
echo "$server_events"
echo
echo "[client events]"
echo "$client_events"
echo
echo "[only in server]"
comm -23 <(echo "$server_events") <(echo "$client_events") || true
echo
echo "[only in client]"
comm -13 <(echo "$server_events") <(echo "$client_events") || true
echo
echo "[missing from docs]"
for e in $(echo "$server_events" "$client_events" | tr ' ' '\n' | sort -u); do
  if ! grep -q "\`$e\`" "$PROTOCOL" 2>/dev/null; then
    echo "$e"
  fi
done
