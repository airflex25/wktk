#!/bin/bash
# wktk 개발 런처: 서버 + cloudflared 터널 + APK 재빌드 + 디바이스 설치/실행을 한 방에.
# 사용: ./dev.sh
# 종료: Ctrl+C (서버/터널 자동 정리)

set -u

ROOT="/Users/hugh/Documents/Claude/Projects/wktk"
SERVER_DIR="$ROOT/server"
ANDROID_DIR="$ROOT/android"
APK="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
GRADLE_FILE="$ANDROID_DIR/app/build.gradle.kts"
SDK_ROOT="/opt/homebrew/share/android-commandlinetools"
ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR_BIN="$SDK_ROOT/emulator/emulator"
AVD_NAME="${AVD_NAME:-wktk}"
SERVER_LOG="/tmp/wktk-server.log"
TUNNEL_LOG="/tmp/wktk-tunnel.log"
EMU_LOG="/tmp/wktk-emulator.log"

SERVER_PID=""
TUNNEL_PID=""

cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
  [[ -n "$TUNNEL_PID" ]] && kill "$TUNNEL_PID" 2>/dev/null
}
trap cleanup EXIT
trap 'echo; echo "[wktk] 인터럽트, 정리 중..."; exit 130' INT TERM

step() { echo; echo "[wktk] === $1 ==="; }

# ── 사전 체크 ──
for cmd in node npm cloudflared python3; do
  if ! command -v $cmd >/dev/null; then
    echo "[wktk] '$cmd' 가 없습니다. 먼저 설치하세요." >&2
    exit 1
  fi
done

step "1/7 기존 프로세스 정리"
pkill -f "cloudflared tunnel" 2>/dev/null && echo "  - cloudflared 종료" || true
pkill -f "node.*src/index.js" 2>/dev/null && echo "  - node 서버 종료" || true
"$ADB" kill-server >/dev/null 2>&1 || true
"$ADB" start-server >/dev/null 2>&1 || true
sleep 1

step "2/7 시그널링 서버 기동"
cd "$SERVER_DIR"
[[ ! -d node_modules ]] && npm install --silent
node src/index.js > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!
sleep 2
if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo "  서버 시작 실패:"
  cat "$SERVER_LOG"
  exit 1
fi
echo "  → PID $SERVER_PID (localhost:3000)"

step "3/7 Cloudflare 터널 발급"
cloudflared tunnel --url http://localhost:3000 > "$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

URL=""
for i in $(seq 1 30); do
  sleep 1
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -1)
  [[ -n "$URL" ]] && break
done

if [[ -z "$URL" ]]; then
  echo "  터널 URL 발급 실패. 최근 로그:"
  tail -20 "$TUNNEL_LOG"
  exit 1
fi
echo "  → $URL"

# DNS 전파 + 터널 워밍업 대기 (최대 60초)
echo -n "  - /health 도달 대기 "
HEALTH_OK=""
for i in $(seq 1 30); do
  HEALTH=$(curl -fsS -m 3 "$URL/health" 2>/dev/null || true)
  if [[ "$HEALTH" == *'"ok":true'* ]]; then
    HEALTH_OK=1
    echo " ✓"
    break
  fi
  echo -n "."
  sleep 2
done
if [[ -z "$HEALTH_OK" ]]; then
  echo " ✗"
  echo "  ⚠ /health 응답 없음. 터널이 살아있는지 의심됨."
  echo "    터널 로그: tail $TUNNEL_LOG"
fi

step "4/7 build.gradle.kts 업데이트"
python3 - "$URL" "$GRADLE_FILE" <<'PY'
import re, sys
url, path = sys.argv[1], sys.argv[2]
with open(path) as f:
    s = f.read()
new = re.sub(
    r'(SIGNALING_URL", )"\\"[^"]+\\""',
    lambda m: m.group(1) + '"\\"' + url + '\\""',
    s,
)
with open(path, 'w') as f:
    f.write(new)
PY
echo "  → SIGNALING_URL = $URL"

step "5/7 APK 빌드"
cd "$ANDROID_DIR"
./gradlew assembleDebug -q
echo "  → $APK"

step "6/7 디바이스 준비 (에뮬레이터 + 폰)"
"$ADB" reconnect offline >/dev/null 2>&1 || true
sleep 1

# 에뮬레이터: 이미 떠있나? 없으면 부팅 시작.
if "$ADB" devices | awk '$1 ~ /^emulator-/ && $2 == "device"' | grep -q .; then
  echo "  - 에뮬레이터 이미 실행 중"
else
  if [[ ! -x "$EMULATOR_BIN" ]]; then
    echo "  ⚠ emulator 바이너리 없음. sdkmanager 'emulator' 설치 필요."
  elif ! "$EMULATOR_BIN" -list-avds 2>/dev/null | grep -qx "$AVD_NAME"; then
    echo "  ⚠ AVD '$AVD_NAME' 없음. 다른 이름이면 AVD_NAME=xxx ./dev.sh"
    echo "  사용 가능한 AVD:"
    "$EMULATOR_BIN" -list-avds 2>/dev/null | sed 's/^/    /'
  else
    echo "  - 에뮬레이터 '$AVD_NAME' 시작..."
    nohup "$EMULATOR_BIN" -avd "$AVD_NAME" >"$EMU_LOG" 2>&1 &
    disown
    # 부팅 완료 대기 (최대 3분)
    echo -n "  - 부팅 대기 "
    for i in $(seq 1 90); do
      BOOTED=$("$ADB" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
      if [[ "$BOOTED" == "1" ]]; then
        echo " ✓"
        break
      fi
      echo -n "."
      sleep 2
    done
    [[ "$BOOTED" != "1" ]] && echo " ✗ (계속 진행)"
  fi
fi

# 폰: 안 보이면 안내
if ! "$ADB" devices | awk '$1 !~ /^emulator-/ && $2 == "device"' | grep -q .; then
  echo "  - 폰 USB 미연결 (폰에 같이 깔고 싶으면 USB 연결 + 디버깅 허용 후 재실행)"
fi

step "7/7 설치 및 실행"
DEVICES=$("$ADB" devices | awk '$2 == "device" {print $1}')
if [[ -z "$DEVICES" ]]; then
  echo "  ⚠ 연결된 디바이스 없음. 수동 설치:"
  echo "    $ADB install -r $APK"
else
  for D in $DEVICES; do
    echo "  - $D 설치/실행 중..."
    "$ADB" -s "$D" install -r "$APK" >/dev/null
    "$ADB" -s "$D" shell am force-stop com.wktk
    "$ADB" -s "$D" shell am start -n com.wktk/.MainActivity >/dev/null
  done
fi

echo
echo "[wktk] ────────────────────────────────────────────"
echo "[wktk] ✅ 준비 완료"
echo "[wktk] 시그널링 URL: $URL"
echo "[wktk] 서버 로그:    $SERVER_LOG"
echo "[wktk] 터널 로그:    $TUNNEL_LOG"
echo "[wktk] 에뮬 로그:    $EMU_LOG"
echo "[wktk] ────────────────────────────────────────────"
echo "[wktk] 아래는 실시간 서버 로그. Ctrl+C 로 종료."
echo

tail -f "$SERVER_LOG"
