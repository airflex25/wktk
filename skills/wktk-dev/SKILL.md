---
name: wktk-dev
description: wktk(워키토키) 프로젝트 전용 개발 가이드. 6자리 키 룸 매칭 + WebRTC P2P 음성 + PTT/VOX 토글 구조의 안드로이드/노드 모노레포에서 작업할 때 사용. 사용자가 wktk 저장소 안에서 "워키토키", "PTT", "VOX", "시그널링", "WebRTC", "6자리 키", "Socket.IO", "RtcManager", "SignalingClient" 같은 단어를 언급하거나, server/, android/ 폴더의 파일을 수정·확장·디버깅하려 할 때 반드시 트리거되어야 한다. 단순한 안드로이드 일반 질문이 아니라 이 프로젝트의 구조·프로토콜·코드 스타일을 따라야 하는 작업이라면 이 스킬을 먼저 읽어야 토큰을 낭비하지 않는다.
---

# wktk 개발 가이드 (token-efficient)

이 스킬은 wktk 저장소를 다룰 때 **탐색 토큰을 줄이기 위한 지름길 지도**다.
파일을 마음대로 검색하기 전에 이 문서를 먼저 읽고, 필요한 영역만 references/ 에서 따로 읽어라.

## 1. 프로젝트 한 줄 요약

6자리 숫자 키를 "주파수"처럼 쓰는 워키토키.
서버는 키별로 사용자를 매칭하고 SDP/ICE만 중계한다 (Node.js + Socket.IO).
음성은 안드로이드 클라이언트끼리 WebRTC P2P로 직접 흐른다 (Kotlin + Compose).
대화 모드는 **PTT 기본**, **VOX 토글** 옵션.

## 2. 어디에 무엇이 있는가 (핵심 지도)

| 일하려는 것 | 파일 | 비고 |
|------------|------|------|
| 시그널링 메시지 추가/수정 | `server/src/signaling.js` + `android/app/src/main/java/com/wktk/signaling/SignalingClient.kt` | 양쪽을 **반드시 같이** 수정 |
| 키 룸 규칙 (제한, 발급) | `server/src/room.js` | 메모리 기반. 멀티노드 시 Redis adapter |
| WebRTC 협상 (offer/answer/ice) | `android/.../webrtc/RtcManager.kt` | "신참이 offer 만든다" 규칙 (§5) |
| PTT/VOX 동작 | `WktkViewModel.kt` 의 `setMicEnabled` 호출부 | PeerConnection은 안 건드린다 |
| 화면 / 버튼 | `android/.../ui/WktkApp.kt` | KeyEntryScreen, RoomScreen, PttButton |
| 단일 상태 | `WktkViewModel.kt` 의 `WktkState`, `WktkIntent` | UI는 이 둘만 본다 |
| 오디오 라우팅 (스피커/모드) | `android/.../audio/AudioRouter.kt` | `MODE_IN_COMMUNICATION` 사용 |
| 프로토콜 사양서 | `docs/protocol.md` | 메시지 이름과 페이로드 변경 시 같이 갱신 |

자주 쓰는 더 긴 코드 패턴은 `references/`:

- `references/server-patterns.md` — 새 시그널링 이벤트 추가 템플릿, ROOM_LIMIT 변경 등
- `references/android-patterns.md` — 새 intent 추가, 새 이벤트 처리, 백그라운드 서비스화
- `references/protocol.md` — 프로토콜 메시지 빠른 참조 (docs/protocol.md의 캐시본)

이 references는 **필요할 때만** 읽어라. 다 읽으면 토큰 낭비.

## 3. 절대 어기지 말 것

1. **음성 데이터를 서버로 보내지 마라.** 이 서버는 시그널링 전용이다. 오디오는 WebRTC P2P로 흐른다. "쉽게 가자" 하면서 서버에 PCM 올리면 설계가 무너진다.
2. **서버와 클라이언트의 메시지 이름은 한 쌍이다.** `key:join` 추가하면 양쪽 다 추가. `docs/protocol.md` 도 같이 업데이트.
3. **PTT/VOX 토글로 PeerConnection을 재협상하지 마라.** `localAudioTrack.setEnabled(...)` 한 줄이면 된다.
4. **신참이 offer를 만든다.** 양쪽이 동시에 offer를 만들면 SDP glare가 생긴다. 룸 입장 시 받은 `peers` 목록이 비어 있지 않으면, 그 사람들에게 내가 offer를 보낸다.
5. **6자리 키 검증은 양쪽에서.** 서버는 `^\d{6}$`, 클라는 `length == 6 && all isDigit`. 한쪽만 막으면 안 된다.
6. **오디오 권한 없이는 RTC를 시작하지 마라.** `MainActivity` 가 RECORD_AUDIO 를 요청한다. RtcManager.start()는 권한이 있을 때만 호출.

## 4. 메시지 프로토콜 (압축 버전)

클라 → 서버:
- `key:request {}` → 서버가 `key:assigned { key }`
- `key:join { key }` → 서버가 `key:joined { key, self, peers[] }`
- `key:leave {}`
- `signal { to, type, payload }` — type은 `"offer" | "answer" | "ice"`

서버 → 클라:
- `key:assigned`, `key:joined`, `peer:joined { peerId }`, `peer:left { peerId }`
- `signal { from, type, payload }`
- `error { code, message }` — code: `INVALID_KEY`, `ROOM_FULL`, `NOT_IN_ROOM`, `PEER_NOT_FOUND`, `BAD_SIGNAL`

페이로드 형식:
```
offer  : { type: "offer",  sdp: "<SDP string>" }
answer : { type: "answer", sdp: "<SDP string>" }
ice    : { sdpMid, sdpMLineIndex, candidate }
```

## 5. 협상 흐름 (한눈에)

```
A 입장 → 서버: peers=[]    → A는 아무에게도 offer 보내지 않음
B 입장 → 서버: peers=[A]   → B가 A에게 offer
                             A는 answer로 응답
                             양쪽 ICE 후보 교환
                             ICE connected → 음성 흐름
```

C가 들어오면 C가 [A, B] 양쪽에게 offer. full-mesh.

## 6. 자주 하는 작업의 짧은 레시피

### 새 시그널링 이벤트 추가하기
1. `server/src/signaling.js` 의 `socket.on(...)` 블록에 핸들러 추가
2. `SignalingClient.kt` 의 `events` 채널에 새 `SignalingEvent` sealed 항목 추가 + `on("...") { ... }` 등록
3. `WktkViewModel.onEvent` 에서 처리, 필요시 `WktkState`/`WktkIntent` 업데이트
4. `docs/protocol.md` 표에 한 줄 추가

### 룸 인원 제한 바꾸기
- `ROOM_LIMIT` 환경변수만 바꾸면 됨. `server/src/room.js` 의 디폴트(4)도 같이 보면 좋다.

### TURN 서버 추가
- `RtcManager.iceServers` 에 `IceServer.builder("turn:...").setUsername(...).setPassword(...)` 추가.

### PTT 단축키/하드웨어 버튼 매핑
- `MainActivity.onKeyDown/Up` 에서 KeyEvent 캐치 → ViewModel 의 `PttPress`/`PttRelease` intent 디스패치.
  키 자체 처리는 `WktkViewModel`의 의존을 깨지 않게 ViewModel 레벨에서만 한다.

### 백그라운드에서도 통화 유지
- 포그라운드 서비스(`FOREGROUND_SERVICE_MICROPHONE`)로 RtcManager + SignalingClient 를 옮긴다.
- 자세한 패턴: `references/android-patterns.md` 의 "ForegroundService" 절.

## 7. 작업 시작 체크리스트 (Claude를 위한)

작업 요청을 받으면 머리속에서:

1. "어느 레이어인가?" — UI / state / signaling / WebRTC / server. 표(§2)에서 파일 후보를 잡는다.
2. "프로토콜이 바뀌는가?" — Yes면 §3.2 규칙대로 양쪽+docs를 모두 건드린다.
3. "PeerConnection 재협상이 필요한가?" — 송수신 토글이면 NO (트랙 enabled), 새 미디어 추가면 YES.
4. 작은 변경이면 references는 안 읽어도 된다. 새 패턴이 필요하면 그때 references/ 안의 해당 파일만 읽는다.

이 순서를 지키면 wktk 저장소에서는 보통 **2~3개 파일만 열어** 끝낼 수 있다.
