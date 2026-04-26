#!/bin/bash
# wktk 빌드 + 디바이스 설치 런처.
# 시그널링 서버는 Render에 호스팅됨 (https://wktk-signaling.onrender.com).
# 사용: ./dev.sh

set -u

ROOT="/Users/hugh/Documents/Claude/Projects/wktk"
ANDROID_DIR="$ROOT/android"
APK="$ANDROID_DIR/app/build/outputs/apk/debug/wktk-debug.apk"
SDK_ROOT="/opt/homebrew/share/android-commandlinetools"
ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR_BIN="$SDK_ROOT/emulator/emulator"
AVD_NAME="${AVD_NAME:-wktk}"
SIGNALING_URL="https://wktk-signaling.onrender.com"
EMU_LOG="/tmp/wktk-emulator.log"

step() { echo; echo "[wktk] === $1 ==="; }

step "1/4 시그널링 서버 깨우기"
echo -n "  - $SIGNALING_URL/health "
HEALTH_OK=""
for i in $(seq 1 30); do
  HEALTH=$(curl -fsS -m 5 "$SIGNALING_URL/health" 2>/dev/null || true)
  if [[ "$HEALTH" == *'"ok":true'* ]]; then
    HEALTH_OK=1
    echo "✓"
    break
  fi
  echo -n "."
  sleep 2
done
if [[ -z "$HEALTH_OK" ]]; then
  echo "✗"
  echo "  ⚠ Render 서버 응답 없음. dashboard.render.com 에서 상태 확인."
  echo "    (그래도 빌드/설치는 진행합니다)"
fi

step "2/4 APK 빌드"
cd "$ANDROID_DIR"
# 증분 빌드. SIGNALING_URL 같은 BuildConfig 상수를 바꿨다면 CLEAN=1 ./dev.sh 로 한 번 강제 clean.
if [[ "${CLEAN:-0}" == "1" ]]; then
  ./gradlew clean assembleDebug -q
else
  ./gradlew assembleDebug -q
fi
echo "  → $APK"

step "3/4 디바이스 준비"
"$ADB" reconnect offline >/dev/null 2>&1 || true
sleep 1

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

if ! "$ADB" devices | awk '$1 !~ /^emulator-/ && $2 == "device"' | grep -q .; then
  echo "  - 폰 USB 미연결 (폰에 같이 깔고 싶으면 USB + 디버깅 허용 후 재실행)"
fi

step "4/4 설치 및 실행"
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
echo "[wktk] ✅ 완료"
echo "[wktk] 시그널링 URL: $SIGNALING_URL"
echo "[wktk] Render 대시보드: https://dashboard.render.com"
echo "[wktk] ────────────────────────────────────────────"
