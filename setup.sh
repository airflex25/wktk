#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# wktk 최초 셋업 스크립트
# 실행 전에 Node.js 20+ 와 JDK 17+ 가 설치돼 있어야 합니다.
# 사용법:  chmod +x setup.sh && ./setup.sh
# ──────────────────────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER_JAR="$SCRIPT_DIR/android/gradle/wrapper/gradle-wrapper.jar"
GRADLE_VERSION="8.7"

# ── 색상 출력 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[wktk]${NC} $*"; }
warn()  { echo -e "${YELLOW}[wktk]${NC} $*"; }
error() { echo -e "${RED}[wktk]${NC} $*" >&2; exit 1; }

# ── 전제조건 확인 ────────────────────────────────────────────────────────────
command -v node >/dev/null 2>&1  || error "Node.js가 필요합니다. https://nodejs.org"
command -v java >/dev/null 2>&1  || error "JDK 17+가 필요합니다."

NODE_MAJOR=$(node -e "process.stdout.write(process.version.split('.')[0].slice(1))")
if [ "$NODE_MAJOR" -lt 20 ]; then
  error "Node.js 20 이상이 필요합니다 (현재: $(node -v))"
fi

# ── 1. 서버: npm install ─────────────────────────────────────────────────────
info "서버 의존성 설치 중..."
cd "$SCRIPT_DIR/server"
npm install
info "서버 준비 완료."

# ── 2. Android: gradle-wrapper.jar 다운로드 ─────────────────────────────────
if [ ! -f "$WRAPPER_JAR" ]; then
  info "gradle-wrapper.jar 다운로드 중 (gradle $GRADLE_VERSION)..."
  GRADLE_ZIP="gradle-${GRADLE_VERSION}-bin.zip"
  TMP_DIR=$(mktemp -d)
  curl -fsSL \
    "https://services.gradle.org/distributions/${GRADLE_ZIP}" \
    -o "$TMP_DIR/$GRADLE_ZIP"
  unzip -q "$TMP_DIR/$GRADLE_ZIP" -d "$TMP_DIR"
  cp "$TMP_DIR/gradle-${GRADLE_VERSION}/lib/plugins/gradle-wrapper-${GRADLE_VERSION}.jar" \
     "$WRAPPER_JAR" 2>/dev/null || \
  find "$TMP_DIR" -name "gradle-wrapper*.jar" | head -1 | xargs -I{} cp {} "$WRAPPER_JAR"
  rm -rf "$TMP_DIR"
  info "gradle-wrapper.jar 설치 완료."
else
  info "gradle-wrapper.jar 이미 존재 — 스킵."
fi

# ── 3. Android: local.properties 생성 ───────────────────────────────────────
LOCAL_PROPS="$SCRIPT_DIR/android/local.properties"
if [ ! -f "$LOCAL_PROPS" ]; then
  # ANDROID_HOME 이나 ANDROID_SDK_ROOT 환경변수 우선 활용
  SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -z "$SDK_DIR" ]; then
    # macOS 기본 경로 추정
    CANDIDATE="$HOME/Library/Android/sdk"
    [ -d "$CANDIDATE" ] && SDK_DIR="$CANDIDATE"
  fi
  if [ -n "$SDK_DIR" ]; then
    echo "sdk.dir=$SDK_DIR" > "$LOCAL_PROPS"
    info "local.properties 생성: sdk.dir=$SDK_DIR"
  else
    warn "Android SDK 경로를 자동으로 찾지 못했습니다."
    warn "android/local.properties.example 을 참고해 android/local.properties 를 직접 만들어 주세요."
  fi
else
  info "local.properties 이미 존재 — 스킵."
fi

# ── 완료 ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✅ 셋업 완료!${NC}"
echo ""
echo "  서버 실행 (개발):  cd server && npm run dev"
echo "  APK 빌드:          cd android && ./gradlew assembleDebug"
echo "  에뮬레이터 실행:   cd android && ./gradlew installDebug"
echo ""
