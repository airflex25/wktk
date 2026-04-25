# Signaling Protocol

전송: Socket.IO (WebSocket 위). 모든 메시지는 JSON.

## 클라이언트 → 서버

| 이벤트 | 페이로드 | 설명 |
|--------|---------|------|
| `key:request` | `{}` | 사용 중이지 않은 랜덤 6자리 키 요청 |
| `key:join` | `{ key: "482910" }` | 해당 키 룸에 입장. 서버가 현재 피어 목록을 응답 |
| `key:leave` | `{}` | 룸에서 나가기 |
| `signal` | `{ to: "<peerId>", type: "offer"\|"answer"\|"ice", payload: any }` | 특정 피어에게 시그널링 메시지 전달 |

## 서버 → 클라이언트

| 이벤트 | 페이로드 | 설명 |
|--------|---------|------|
| `key:assigned` | `{ key: "482910" }` | `key:request` 응답 |
| `key:joined` | `{ key, self: "<peerId>", peers: ["<id>", ...] }` | 룸 입장 확인. 기존 피어 목록 포함 |
| `peer:joined` | `{ peerId }` | 다른 피어가 같은 룸에 들어옴 |
| `peer:left` | `{ peerId }` | 다른 피어가 나감 |
| `signal` | `{ from: "<peerId>", type, payload }` | 다른 피어가 보낸 시그널링 메시지 |
| `error` | `{ code, message }` | 오류 (예: 잘못된 키 형식) |

## 키 규칙

- 형식: 정확히 숫자 6자 (`/^\d{6}$/`)
- 대소문자 없음, 공백 없음
- `000000`~`999999` 모두 사용 가능
- 같은 키에 동시에 들어올 수 있는 인원 제한: 기본 4명 (서버 설정)

## 연결 협상 순서

1. 클라이언트가 `key:join` → 서버는 `key:joined`로 기존 피어 목록 반환
2. **신참(나중에 들어온 사람)** 이 기존 피어들에게 `signal { type: "offer" }` 전송
3. 기존 피어는 `signal { type: "answer" }` 응답
4. 양쪽 모두 ICE 후보가 모이는 대로 `signal { type: "ice" }` 전송
5. PeerConnection이 `connected` 상태가 되면 음성 흐름 시작

이 "신참이 offer를 만든다" 규칙이 충돌(glare)을 막는다.

## 오류 코드

| code | 의미 |
|------|------|
| `INVALID_KEY` | 키 형식 위반 |
| `ROOM_FULL` | 인원 초과 |
| `NOT_IN_ROOM` | 룸에 없는데 leave/signal 시도 |
| `PEER_NOT_FOUND` | signal의 대상 peerId가 룸에 없음 |
