// wktk signaling server entry.
// 책임은 단 두 가지:
//   1) 6자리 key 룸 매칭
//   2) offer/answer/ice 메시지 중계
// 음성 트래픽은 절대 이 서버를 지나가지 않는다 (WebRTC P2P).

import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { attachSignaling } from './signaling.js';

const PORT = Number(process.env.PORT ?? 3000);
const ORIGIN = process.env.CORS_ORIGIN ?? '*';

const http = createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, ts: Date.now() }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const io = new Server(http, {
  cors: { origin: ORIGIN },
  // 모바일 백그라운드 진입 시 빠르게 끊고 다시 붙도록 짧게 잡는다.
  pingInterval: 10_000,
  pingTimeout: 8_000,
});

attachSignaling(io);

http.listen(PORT, () => {
  console.log(`[wktk] signaling listening on :${PORT}`);
});
