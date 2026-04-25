# Server Patterns

자주 쓰는 서버 측 변경 템플릿. 필요할 때만 읽는다.

## 새 시그널링 이벤트 추가

`server/src/signaling.js`:

```js
socket.on('mute:notify', ({ muted } = {}) => {
  const key = roomOf(peerId);
  if (!key) return;
  // 같은 룸의 다른 피어에게 브로드캐스트
  socket.to(key).emit('peer:mute', { peerId, muted: !!muted });
});
```

원칙:
- 입력은 **반드시 검증**. (key 형식, 필드 존재 여부, 타입)
- 룸을 모르는 상태에서 들어오면 `error { code: 'NOT_IN_ROOM' }` 응답.
- 다른 피어에게 보낼 때 `socket.to(key)` (자신은 제외).
- 특정 한 명에게는 `io.to(targetSocketId).emit(...)`.

## ROOM_LIMIT 동적 조정

지금은 환경변수 + 모듈 로드 시점 상수.
런타임 조정이 필요하면 `room.js`에 `setRoomLimit(n)`을 추가하고 admin 엔드포인트에서 호출.
공개 인터넷에 두지 말 것 (인증 없이 노출 금지).

## 멀티노드로 확장

Socket.IO는 단일 프로세스 가정.
스케일아웃은 `@socket.io/redis-adapter` + Redis. `room.js`의 `Map`도 Redis 해시로 옮긴다.
이 단계가 오면 그때 별도 PR로 분리하자 — 단일 노드 코드를 미리 일반화하지 마라 (YAGNI).

## STUN/TURN

서버는 시그널링만 한다. STUN/TURN 자체는 별도 서비스.
운영에서 NAT 통과 실패가 잦으면 [coturn](https://github.com/coturn/coturn) 한 대 띄우고
클라이언트의 `RtcManager.iceServers` 에만 자격증명을 추가하면 된다.

## 헬스체크 / 메트릭

`/health` 만 있다.
간단한 상태 보고가 필요하면 `/stats` 를 추가해 `{ rooms: rooms.size, peers: peerToKey.size }` 정도만 노출.
공개 환경이면 인증을 붙일 것.
