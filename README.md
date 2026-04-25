# wktk — 6-Digit Key Walkie-Talkie

랜덤 6자리 키를 "주파수"처럼 사용하는 워키토키 안드로이드 앱.
같은 키를 입력한 사용자끼리 자동으로 음성으로 연결됩니다.

## 구조

| 폴더 | 역할 | 스택 |
|------|------|------|
| `server/` | 6자리 키 매칭 + WebRTC 시그널링만 담당 | Node.js + Socket.IO |
| `android/` | 모바일 클라이언트 (PTT 기본 / VOX 토글) | Kotlin + Jetpack Compose + WebRTC |
| `docs/` | 프로토콜·아키텍처 문서 | Markdown |
| `.claude/skills/wktk-dev/` | 이 프로젝트 전용 Claude 스킬 (토큰 절약용) | SKILL.md |

## 핵심 설계 원칙

1. **서버는 무겁지 않다** — 서버는 키별 룸 매칭과 SDP/ICE 교환만 한다. 음성은 P2P(WebRTC)로 직접 흐른다.
2. **6자리 키 = 주파수** — `000000`~`999999`. 사용자가 직접 입력하거나 서버에서 랜덤 발급받을 수 있다.
3. **두 가지 대화 모드** — 기본은 버튼을 누른 동안만 송신(PTT), 토글하면 항상 송신(VOX/Open Mic).
4. **로그인·계정 없음** — 키만 알면 들어간다. 신원은 임시 peerId로만 구분.

## 빠른 시작

### 전제조건

- Node.js 20+
- JDK 17+
- Android Studio (Koala 이상 권장) 또는 안드로이드 SDK + Gradle

### 1단계 — 셋업 (최초 1회)

```bash
chmod +x setup.sh && ./setup.sh
```

이 스크립트는 다음을 수행합니다:
- `server/node_modules` 설치 (`npm install`)
- `android/gradle/wrapper/gradle-wrapper.jar` 다운로드
- `android/local.properties` 자동 생성 (SDK 경로)

### 2단계 — 서버 실행

```bash
cd server
npm run dev          # 개발 (파일 변경 시 자동 재시작)
# 또는
npm start            # 프로덕션
```

서버는 기본 포트 **3000**에서 실행됩니다.
환경변수는 `server/.env.example` 참고.

### 3단계 — 안드로이드 빌드

```bash
cd android
./gradlew assembleDebug          # APK 빌드
./gradlew installDebug           # 연결된 기기/에뮬레이터에 설치
```

또는 **Android Studio**에서 `android/` 폴더를 열고 ▶ Run.

> **에뮬레이터 사용 시**: `app/build.gradle.kts`의 `SIGNALING_URL`이
> `http://10.0.2.2:3000`으로 설정돼 있어 로컬 서버에 자동 연결됩니다.
> 실기기 사용 시 서버의 IP 주소로 변경하세요.

### 사용 방법

1. 앱을 실행하면 **서버 연결됨** 표시 확인
2. **새 키 받기** → 랜덤 6자리 키 자동 생성, 또는 원하는 6자리 숫자 직접 입력
3. **입장** → 같은 키를 입력한 상대방과 자동 연결
4. 기본 **PTT 모드**: 원형 버튼을 누르는 동안 송신
5. **VOX 토글** 켜면 항상 오픈마이크 모드

자세한 내용은 `docs/architecture.md`, `docs/protocol.md` 참고.

## Claude로 개발할 때

이 저장소를 Cowork/Claude Code로 열면 `.claude/skills/wktk-dev/SKILL.md`가
자동으로 인식됩니다. 이 스킬은:

- 파일이 어디에 있어야 하는지 알려줍니다 (탐색 토큰 절약)
- 시그널링 메시지 스펙을 압축해 보여줍니다
- 자주 쓰는 코드 패턴을 references/ 로 분리해 필요할 때만 읽도록 합니다
