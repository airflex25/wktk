# 오키도키 시스템 아키텍처

## 한눈에 보는 구성

```
┌─────────────────────────────────────────────────────────────────────┐
│                            사용자 디바이스                              │
│  ┌──────────────┐                              ┌──────────────┐     │
│  │ Android 폰 A │                              │ iPhone B     │     │
│  │ Flutter 앱   │                              │ Flutter 앱   │     │
│  └──────┬───────┘                              └──────┬───────┘     │
└─────────┼──────────────────────────────────────────────┼────────────┘
          │ HTTPS/WSS                            HTTPS/WSS │
          ▼                                                ▼
   ┌──────────────────────────────────────────────────────────┐
   │  Render (Free) — wktk-signaling.onrender.com              │
   │  ┌──────────────────────────────────────────────────┐    │
   │  │  server/ (Node.js + Socket.IO)                   │    │
   │  │  • POST /turn-credentials → Cloudflare API 호출   │    │
   │  │  • GET  /health                                  │    │
   │  │  • WSS  /socket.io/ (Socket.IO)                  │    │
   │  └──────────────────────────────────────────────────┘    │
   └──────────────┬───────────────────────────────────────────┘
                  │ Bearer 인증
                  ▼
   ┌──────────────────────────────────────────────────────────┐
   │  Cloudflare Realtime — TURN 서비스                         │
   │  • 임시 자격증명 발급 (TTL 1시간)                            │
   │  • turn.cloudflare.com:3478,5349                          │
   └──────────────────────────────────────────────────────────┘
                                                                
        ╔══════════ P2P 음성 (WebRTC, DTLS-SRTP) ═══════════╗
   A ◄══╣  STUN으로 직접 연결 시도 (80~90% 성공)             ╠══► B
        ║  실패 시 Cloudflare TURN 으로 릴레이              ║
        ╚════════════════════════════════════════════════════╝
```

## 요약

- **음성은 P2P** — 시그널링 서버나 Cloudflare 서버에 음성 데이터가 머무르지 않는다.
- **시그널링 서버는 매우 가벼움** — 키 매칭 + 메시지 중계만. 메모리 룸 상태, DB 없음.
- **TURN은 NAT 뚫기 실패 시 fallback** — 평소엔 거의 안 거침.
- **모든 통신은 종단간 암호화** — HTTPS/WSS (제어), DTLS-SRTP (음성).

---

## 컴포넌트

### 1. 모바일 앱 — `mobile/` (Flutter)

#### 패키지 ID
- Android: `com.airflex.oktk`
- iOS: `com.wktk.wktk` (변경 가능)

#### 주요 디렉토리
```
mobile/
├── lib/
│   ├── main.dart        — UI + 상태 관리 (StatefulWidget, ValueNotifier)
│   ├── signaling.dart   — Socket.IO 클라이언트, sealed event 스트림
│   └── rtc.dart         — WebRTC mesh, Cloudflare TURN 연동, audio level 측정
├── android/             — 네이티브 안드로이드 래퍼 (Kotlin)
├── ios/                 — 네이티브 iOS 래퍼 (Swift, AppIcon, Info.plist)
└── pubspec.yaml         — 의존성 + 버전
```

#### 주요 의존성
| 패키지 | 용도 |
|--------|------|
| `flutter_webrtc` ^0.12.0 | PeerConnection, MediaStream, getStats |
| `socket_io_client` ^2.0.3 | Socket.IO 4.x 호환 클라이언트 |
| `permission_handler` ^11.3.1 | 마이크 권한 런타임 요청 |

#### 책임 분담
| 레이어 | 책임 |
|--------|------|
| `signaling.dart` | Socket.IO 연결, key 발급/입장, signal 메시지 라우팅 |
| `rtc.dart` | full-mesh PeerConnection, 마이크 ON/OFF, audio level 측정, TURN credential fetch, ICE restart |
| `main.dart` | 화면 상태, 사용자 입력, 상태 → UI 매핑 |

---

### 2. 시그널링 서버 — `server/` (Node.js)

#### 호스팅
- **Render Free Plan** (https://wktk-signaling.onrender.com)
- 자동 배포: GitHub push → 자동 빌드 (`render.yaml` Blueprint)
- 15분 idle 후 sleep, 첫 요청 시 ~30s cold start

#### 코드 구조
```
server/
├── src/
│   ├── index.js         — HTTP/Socket.IO 부트스트랩, /health, /turn-credentials
│   ├── signaling.js     — Socket.IO 이벤트 핸들러
│   └── room.js          — 메모리 기반 키→피어 룸 상태
├── package.json
└── README.md
```

#### HTTP 엔드포인트
| 경로 | 메서드 | 용도 |
|------|--------|------|
| `/health` | GET | 헬스체크 (Render 모니터, 클라이언트 ping) |
| `/turn-credentials` | GET | Cloudflare TURN 임시 자격증명 발급 (Bearer로 CF API 호출) |
| `/socket.io/` | WSS | Socket.IO 시그널링 |

#### Socket.IO 이벤트 (자세한 사양: [protocol.md](protocol.md))
- 클라이언트 → 서버: `key:request`, `key:join`, `key:leave`, `signal`
- 서버 → 클라이언트: `key:assigned`, `key:joined`, `peer:joined`, `peer:left`, `signal`, `error`

#### 룸 관리
- 메모리 `Map<key, Set<peerId>>` 만 유지
- 인원 한도: 8명 (`ROOM_LIMIT`, env로 조정 가능)
- 서버 재시작 시 룸 사라짐 (의도된 동작 — 익명/임시 통화 컨셉)

---

### 3. TURN 서버 — Cloudflare Realtime

#### 설정
- **무료 티어**: 1TB/월. 초과 시 $0.05/GB.
- **Realtime 앱 이름**: `withered-firefly-1ce8`
- **자격증명 발급 방식**: 클라이언트 직접 X. 시그널링 서버가 Cloudflare API 호출 → 임시 ICE servers 반환 (TTL 1시간).

#### 동작 흐름
```
1. 앱 시작 → rtc.start() 에서 백그라운드로 /turn-credentials 호출
2. 서버 → POST https://rtc.live.cloudflare.com/v1/turn/keys/<KEY_ID>/credentials/generate-ice-servers
        (Authorization: Bearer <APP_TOKEN>)
3. 응답: { iceServers: { urls: [...turn.cloudflare.com...], username, credential } }
4. 앱은 PeerConnection 생성 시 이 iceServers 사용
5. STUN 으로 P2P 시도 → 실패 시 TURN 으로 릴레이
```

#### 비용 모델
음성 트래픽이 TURN 통과할 때만 과금. 대부분 (80~90%) 직접 P2P라 트래픽 ≈ 0.
- 1만 MAU 기준 예상 트래픽: ~50-100GB/월 → **$0** (무료 티어 내)
- 천 명 동시 접속 같은 이벤트: ~수GB/일 → **$0~5/월**

---

### 4. 정적 페이지 — GitHub Pages

#### 호스팅
- 저장소: `airflex25/wktk` (master 브랜치, `/docs` 폴더)
- URL: `https://airflex25.github.io/wktk/`

#### 페이지
| URL | 용도 |
|-----|------|
| `/wktk/privacy.html` | 개인정보처리방침 (Play Store 등록 필수) |

`docs/store-description.md` 같은 마크다운은 등록용 텍스트 보관소.

---

### 5. 빌드/배포 파이프라인

#### 코드 저장
- GitHub: `airflex25/wktk` (private)
- master 브랜치 = production

#### 배포 흐름
```
사용자 코드 변경 → git push → master 갱신
                     ├─→ GitHub Pages 자동 갱신 (privacy.html 등)
                     └─→ Render Webhook → server/ 자동 재배포
                                           (1-2분 소요)

모바일 빌드는 수동:
- AAB:  flutter build appbundle --release  → Play Console 업로드
- APK:  flutter build apk --release --split-per-abi  → 직접 공유
- iOS:  Xcode Archive → App Store Connect (또는 TestFlight)
```

#### 키스토어
- `~/keystores/okidoki-release.jks` (Mac 로컬, 백업 필수)
- 비밀번호: `mobile/android/key.properties` (gitignored)
- **잃어버리면 같은 패키지명으로 업데이트 불가능**

---

## 주요 통신 흐름

### 케이스 1: 두 명 페어링 + 통화

```
폰A                    Render 서버                    폰B
 │                        │                            │
 │  Socket.IO connect     │                            │
 │ ──────────────────────►│                            │
 │                        │  Socket.IO connect          │
 │                        │◄────────────────────────────│
 │                        │                            │
 │  key:request           │                            │
 │ ──────────────────────►│                            │
 │  key:assigned 482910   │                            │
 │ ◄──────────────────────│                            │
 │  key:join 482910       │                            │
 │ ──────────────────────►│                            │
 │  key:joined (peers=[]) │                            │
 │ ◄──────────────────────│                            │
 │                        │  key:join 482910            │
 │                        │◄────────────────────────────│
 │                        │  key:joined (peers=[A])     │
 │                        │────────────────────────────►│
 │  peer:joined B         │                            │
 │ ◄──────────────────────│                            │
 │                        │                            │
 │   B(신참)이 offer를 만들어 A에게 보냄 (protocol.md 참고)
 │  signal {to:A, offer}  │  signal {from:B, offer}    │
 │ ◄──────────────────────│◄────────────────────────────│
 │  signal {to:B, answer} │  signal {from:A, answer}   │
 │ ──────────────────────►│────────────────────────────►│
 │  signal {ice candidates 양방향 교환}                  │
 │ ──────────────────────►│────────────────────────────►│
 │ ◄──────────────────────│◄────────────────────────────│
 │                                                      │
 │═══════════ P2P 직접 연결 (WebRTC) ══════════════════│
 │   ICE 협상 성공 시: 직접 UDP 음성 (5-10초 내)          │
 │   실패 시: Cloudflare TURN 경유                       │
 │                                                      │
 │ ─────────── DTLS-SRTP 음성 패킷 ───────────────────►│
 │ ◄────────── DTLS-SRTP 음성 패킷 ─────────────────── │
```

### 케이스 2: PTT 버튼

```
사용자가 PTT 누름 → rtc.setMicEnabled(true)
                      → localAudioTrack.enabled = true
                      → 모든 PeerConnection의 sender 가 음성 송신 시작
                      → 상대방의 onTrack 에서 자동 재생 (DTLS-SRTP 복호화)
                      → 상대 UI 의 audioLevel 업데이트 (파동 애니메이션)

사용자가 PTT 뗌 → rtc.setMicEnabled(false)
                  → localAudioTrack.enabled = false
                  → 빈 패킷 또는 무음 송신 (Opus DTX)
```

### 케이스 3: NAT 뚫기 실패 → TURN

```
1. STUN 으로 후보 수집 (양쪽)
2. ICE candidate 교환 (서버 경유)
3. ICE pair 시도 → 모든 직접 연결 실패
4. 양쪽 클라이언트가 TURN candidate 도 시도
5. Cloudflare TURN 서버 통해 릴레이 연결 성립
6. 음성 트래픽이 Cloudflare 인프라 통과 → 양방향 도달
```

---

## 환경 변수 (서버)

`server/` 의 Render Web Service 환경설정:

| Key | 필수 | 설명 |
|-----|------|------|
| `PORT` | (Render 자동 설정) | HTTP 포트 |
| `CORS_ORIGIN` | ✗ (기본 `*`) | Socket.IO CORS |
| `ROOM_LIMIT` | ✗ (기본 8) | 한 키 룸의 최대 인원 |
| `CF_TURN_KEY_ID` | **✓** | Cloudflare TURN Key ID |
| `CF_TURN_API_TOKEN` | **✓** | Cloudflare TURN App Token |
| `TURN_TTL` | ✗ (기본 3600) | TURN 자격증명 유효시간 (초) |

---

## 비용 구조 (월간 예상)

| 동시 사용자 | Render | Cloudflare TURN | 합계 |
|-------------|--------|------------------|------|
| ~30명 | $0 (Free) | $0 (~50GB) | **$0** |
| ~200명 | $7 (Starter) | $0 (~500GB) | **$7** |
| ~1,000명 | $7-25 | $0~10 (~1-2TB) | **$7-35** |

대부분의 비용은 **시그널링 서버(Render)** 에서 발생. 음성 트래픽은 P2P라 인프라 비용 거의 없음.

---

## 알려진 한계

| 항목 | 한계 | 대응 |
|------|------|------|
| **mesh 인원** | 8명 (`ROOM_LIMIT`) | 그 이상 필요 시 SFU(예: mediasoup) 도입. 8명 mesh 는 한 사람이 7개 PeerConnection 유지 (~500kbps 부하). |
| **iOS 시뮬 음성** | audio I/O 미지원, 묵음 | 실기기 테스트 필수 |
| **Render Free cold start** | 첫 요청 시 ~30초 지연 | Starter 플랜으로 업그레이드 |
| **TURN 유료 임계** | 1TB/월 초과 시 GB당 $0.05 | 트래픽 모니터링 |
| **신원 인증** | 사용자 익명 (의도) | 악용 방지는 ROOM_LIMIT + 키 임시성으로 해결 |

---

## 더 보기

- 시그널링 메시지 사양: [protocol.md](protocol.md)
- 개인정보처리방침: [privacy.html](privacy.html)
- 빌드/배포 절차: [../releases/README.md](../releases/README.md)
- Play Store 등록 텍스트: [store-description.md](store-description.md)
