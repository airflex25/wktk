// 관리자 대시보드 HTML. /admin?token=xxx 로 접근.
// 자동 새로고침 (5초마다 fetch). 모바일에서도 보기 좋은 카드 레이아웃.

export const adminHtml = `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>오키도키 관리자</title>
<style>
  :root {
    --bg: #f6f7f9;
    --card: #ffffff;
    --ink: #1b2330;
    --muted: #8a92a6;
    --accent: #1f5f70;
    --hot: #e94e3d;
    --green: #1e7e34;
    --border: #e2e5ea;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Apple SD Gothic Neo", sans-serif;
    background: var(--bg);
    color: var(--ink);
    padding: 20px;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 16px;
  }
  h1 { font-size: 22px; margin: 0; }
  .last-update { color: var(--muted); font-size: 12px; }
  .stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 10px;
    margin-bottom: 20px;
  }
  .stat {
    background: var(--card);
    border-radius: 12px;
    padding: 14px 16px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
  }
  .stat-label { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; }
  .stat-value { font-size: 24px; font-weight: 700; margin-top: 2px; font-variant-numeric: tabular-nums; }
  .section-label { font-size: 13px; color: var(--muted); margin: 8px 4px; font-weight: 600; }
  .rooms { display: flex; flex-direction: column; gap: 8px; }
  .room {
    background: var(--card);
    border-radius: 10px;
    padding: 12px 16px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    box-shadow: 0 1px 3px rgba(0,0,0,0.04);
  }
  .room-key {
    font-size: 22px;
    font-weight: 700;
    letter-spacing: 4px;
    font-variant-numeric: tabular-nums;
    color: var(--accent);
  }
  .room-meta { color: var(--muted); font-size: 12px; }
  .badge {
    display: inline-block;
    padding: 4px 10px;
    border-radius: 14px;
    font-size: 12px;
    font-weight: 600;
  }
  .badge.full { background: #fde7e4; color: var(--hot); }
  .badge.active { background: #e6f4ea; color: var(--green); }
  .badge.solo { background: #f1f2f4; color: var(--muted); }
  .empty {
    text-align: center;
    padding: 40px 20px;
    color: var(--muted);
    background: var(--card);
    border-radius: 12px;
  }
  .footer {
    margin-top: 24px;
    color: var(--muted);
    font-size: 11px;
    text-align: center;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }
  .live-dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--green);
    margin-right: 4px;
    animation: pulse 2s infinite;
  }
</style>
</head>
<body>

<div class="header">
  <h1>오키도키 관리자</h1>
  <div class="last-update"><span class="live-dot"></span><span id="last-update">--</span></div>
</div>

<div class="stats" id="stats"></div>

<div class="section-label">활성 룸</div>
<div id="rooms" class="rooms"></div>

<div class="footer" id="footer">5초마다 자동 새로고침 · 메모리 기반 (서버 재시작 시 초기화)</div>

<script>
const TOKEN = new URLSearchParams(location.search).get('token') || '';

async function refresh() {
  try {
    const r = await fetch('/admin/stats?token=' + encodeURIComponent(TOKEN));
    if (!r.ok) {
      document.getElementById('rooms').innerHTML =
        '<div class="empty">권한 없음 (HTTP ' + r.status + '). URL에 ?token=... 확인</div>';
      return;
    }
    const data = await r.json();
    render(data);
  } catch (e) {
    document.getElementById('rooms').innerHTML =
      '<div class="empty">서버 응답 없음: ' + e.message + '</div>';
  }
}

function render(d) {
  const fmtUptime = (ms) => {
    const s = Math.floor(ms / 1000);
    const d_ = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    return (d_ ? d_ + '일 ' : '') + (h ? h + '시간 ' : '') + m + '분';
  };
  document.getElementById('stats').innerHTML = [
    ['활성 룸', d.activeRooms],
    ['활성 사용자', d.activePeers],
    ['누적 룸', d.totalRoomsCreated],
    ['누적 접속', d.totalPeersJoined],
    ['업타임', fmtUptime(d.uptimeMs)],
  ].map(([l, v]) =>
    '<div class="stat"><div class="stat-label">' + l + '</div>' +
    '<div class="stat-value">' + v + '</div></div>'
  ).join('');

  const roomsEl = document.getElementById('rooms');
  if (d.rooms.length === 0) {
    roomsEl.innerHTML = '<div class="empty">활성 룸 없음</div>';
  } else {
    roomsEl.innerHTML = d.rooms.map(r => {
      const ageS = Math.floor((Date.now() - r.createdAt) / 1000);
      const age = ageS < 60 ? ageS + '초' :
                   ageS < 3600 ? Math.floor(ageS/60) + '분' :
                   Math.floor(ageS/3600) + '시간 ' + Math.floor((ageS%3600)/60) + '분';
      const cls = r.peerCount >= 8 ? 'full' :
                  r.peerCount >= 2 ? 'active' : 'solo';
      const label = r.peerCount >= 8 ? '꽉참' :
                    r.peerCount >= 2 ? '통화 중' : '대기';
      return '<div class="room">' +
        '<div>' +
          '<div class="room-key">' + r.key + '</div>' +
          '<div class="room-meta">' + age + ' 전 시작</div>' +
        '</div>' +
        '<div style="text-align:right">' +
          '<div class="stat-value" style="font-size:18px">' + r.peerCount + '명</div>' +
          '<div class="badge ' + cls + '">' + label + '</div>' +
        '</div>' +
      '</div>';
    }).join('');
  }

  const t = new Date();
  document.getElementById('last-update').textContent =
    t.toLocaleTimeString('ko-KR');
}

refresh();
setInterval(refresh, 5000);
</script>
</body>
</html>`;
