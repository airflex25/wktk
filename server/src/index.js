// wktk signaling server entry.
// 책임은 단 두 가지:
//   1) 6자리 key 룸 매칭
//   2) offer/answer/ice 메시지 중계
// 음성 트래픽은 절대 이 서버를 지나가지 않는다 (WebRTC P2P).

import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { attachSignaling } from './signaling.js';
import { getStats } from './room.js';
import { adminHtml } from './admin-page.js';

const PORT = Number(process.env.PORT ?? 3000);
const ORIGIN = process.env.CORS_ORIGIN ?? '*';
const CF_TURN_KEY_ID = process.env.CF_TURN_KEY_ID;
const CF_TURN_API_TOKEN = process.env.CF_TURN_API_TOKEN;
const TURN_TTL = Number(process.env.TURN_TTL ?? 3600); // 1시간
// 관리자 대시보드 보호용 토큰. 미설정 시 /admin 비활성화.
const ADMIN_TOKEN = process.env.ADMIN_TOKEN;

// Cloudflare TURN 임시 자격증명 발급.
// 클라이언트가 PeerConnection 만들기 전에 호출. 하드코딩 토큰 노출 회피.
async function generateTurnCredentials() {
  if (!CF_TURN_KEY_ID || !CF_TURN_API_TOKEN) {
    throw new Error('CF_TURN_KEY_ID / CF_TURN_API_TOKEN 환경변수 미설정');
  }
  const url = `https://rtc.live.cloudflare.com/v1/turn/keys/${CF_TURN_KEY_ID}/credentials/generate-ice-servers`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CF_TURN_API_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ ttl: TURN_TTL }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Cloudflare TURN ${resp.status}: ${text}`);
  }
  return resp.json();
}

function checkAdminToken(req) {
  if (!ADMIN_TOKEN) return false;
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const fromQuery = url.searchParams.get('token');
  const fromHeader = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  return fromQuery === ADMIN_TOKEN || fromHeader === ADMIN_TOKEN;
}

const http = createServer(async (req, res) => {
  const path = (req.url || '/').split('?')[0];

  if (path === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, ts: Date.now() }));
    return;
  }
  if (path === '/turn-credentials') {
    res.setHeader('Access-Control-Allow-Origin', ORIGIN);
    try {
      const data = await generateTurnCredentials();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data));
    } catch (e) {
      console.error('[wktk] TURN cred error:', e.message);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
    return;
  }

  // 관리자 대시보드. ADMIN_TOKEN 미설정이면 비활성.
  if (path === '/admin' || path === '/admin/') {
    if (!checkAdminToken(req)) {
      res.writeHead(401, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Unauthorized — URL 에 ?token=... 추가 필요');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(adminHtml);
    return;
  }
  if (path === '/admin/stats') {
    if (!checkAdminToken(req)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'unauthorized' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(getStats()));
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
