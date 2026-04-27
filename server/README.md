# wktk-server

WebRTC 시그널링 + 6자리 key 룸 매칭만 담당.

## 실행

```bash
npm install
npm run dev   # node --watch
# 또는
PORT=3000 ROOM_LIMIT=8 npm start
```

`GET /health` → `{ ok: true, ts }`

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `PORT` | 3000 | HTTP 포트 |
| `CORS_ORIGIN` | `*` | Socket.IO CORS origin |
| `ROOM_LIMIT` | 8 | 같은 key 룸의 최대 동시 인원 |

## 코드 구조

- `src/index.js` — HTTP/Socket.IO 부트스트랩
- `src/room.js` — key→peer 룸 상태 (메모리)
- `src/signaling.js` — Socket.IO 이벤트 핸들러

프로토콜 사양은 `../docs/protocol.md`.
