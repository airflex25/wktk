// 관리자 대시보드 + 로그인 페이지.
// /admin 으로 접근 → 로그인 폼 → 토큰 검증 후 대시보드 표시.
// 토큰은 localStorage 에 저장되어 다음 방문 시 자동 로그인.

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
    min-height: 100vh;
  }
  .hidden { display: none !important; }

  /* 로그인 폼 */
  .login-wrap {
    min-height: 80vh;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .login-card {
    width: 100%;
    max-width: 360px;
    background: var(--card);
    border-radius: 16px;
    padding: 32px 24px;
    box-shadow: 0 4px 16px rgba(0,0,0,0.06);
  }
  .login-card h1 {
    margin: 0 0 4px;
    font-size: 22px;
    text-align: center;
  }
  .login-card .sub {
    color: var(--muted);
    font-size: 13px;
    text-align: center;
    margin-bottom: 24px;
  }
  .input {
    width: 100%;
    padding: 12px 14px;
    font-size: 14px;
    border: 1px solid var(--border);
    border-radius: 10px;
    outline: none;
    background: #fbfcfd;
  }
  .input:focus { border-color: var(--accent); background: #fff; }
  .btn {
    width: 100%;
    padding: 12px;
    margin-top: 12px;
    border: none;
    border-radius: 10px;
    background: var(--accent);
    color: #fff;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
  }
  .btn:hover { opacity: 0.9; }
  .btn.logout {
    width: auto;
    padding: 6px 12px;
    background: transparent;
    color: var(--muted);
    border: 1px solid var(--border);
    font-size: 12px;
    margin: 0;
  }
  .err {
    color: var(--hot);
    font-size: 13px;
    text-align: center;
    margin-top: 12px;
    min-height: 18px;
  }

  /* 대시보드 */
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 16px;
  }
  h1 { font-size: 22px; margin: 0; }
  .last-update { color: var(--muted); font-size: 12px; display: flex; align-items: center; gap: 8px; }
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
    animation: pulse 2s infinite;
  }
</style>
</head>
<body>

<!-- 로그인 폼 -->
<div id="login-view" class="login-wrap hidden">
  <form id="login-form" class="login-card">
    <h1>오키도키 관리자</h1>
    <div class="sub">관리자 비밀번호를 입력하세요</div>
    <input
      id="token-input"
      class="input"
      type="password"
      placeholder="비밀번호"
      autocomplete="current-password"
      required
      autofocus
    />
    <button type="submit" class="btn">로그인</button>
    <div id="login-err" class="err"></div>
  </form>
</div>

<!-- 대시보드 -->
<div id="dashboard-view" class="hidden">
  <div class="header">
    <h1>오키도키 관리자</h1>
    <div class="last-update">
      <button id="logout-btn" class="btn logout" type="button">로그아웃</button>
      <span><span class="live-dot"></span> <span id="last-update">--</span></span>
    </div>
  </div>
  <div class="stats" id="stats"></div>
  <div class="section-label">활성 룸</div>
  <div id="rooms" class="rooms"></div>
  <div class="footer">5초마다 자동 새로고침 · 메모리 기반 (서버 재시작 시 초기화)</div>
</div>

<script>
const TOKEN_KEY = 'okidoki_admin_token';
let token = localStorage.getItem(TOKEN_KEY) || '';
let refreshTimer = null;

async function fetchStats(t) {
  return fetch('/admin/stats', {
    headers: { Authorization: 'Bearer ' + t },
  });
}

function showLogin() {
  document.getElementById('login-view').classList.remove('hidden');
  document.getElementById('dashboard-view').classList.add('hidden');
  if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
  setTimeout(() => document.getElementById('token-input').focus(), 50);
}

function showDashboard() {
  document.getElementById('login-view').classList.add('hidden');
  document.getElementById('dashboard-view').classList.remove('hidden');
  refresh();
  if (!refreshTimer) refreshTimer = setInterval(refresh, 5000);
}

async function refresh() {
  try {
    const r = await fetchStats(token);
    if (r.status === 401) {
      // 토큰 만료/무효
      localStorage.removeItem(TOKEN_KEY);
      token = '';
      showLogin();
      document.getElementById('login-err').textContent = '세션이 만료되었습니다. 다시 로그인하세요.';
      return;
    }
    if (!r.ok) {
      document.getElementById('rooms').innerHTML =
        '<div class="empty">서버 응답 ' + r.status + '</div>';
      return;
    }
    render(await r.json());
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

  document.getElementById('last-update').textContent =
    new Date().toLocaleTimeString('ko-KR');
}

document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const v = document.getElementById('token-input').value.trim();
  if (!v) return;
  const errEl = document.getElementById('login-err');
  errEl.textContent = '';
  try {
    const r = await fetchStats(v);
    if (r.ok) {
      token = v;
      localStorage.setItem(TOKEN_KEY, token);
      document.getElementById('token-input').value = '';
      showDashboard();
    } else if (r.status === 401) {
      errEl.textContent = '비밀번호가 틀렸습니다';
    } else {
      errEl.textContent = '서버 응답 ' + r.status;
    }
  } catch (err) {
    errEl.textContent = '서버 응답 없음';
  }
});

document.getElementById('logout-btn').addEventListener('click', () => {
  localStorage.removeItem(TOKEN_KEY);
  token = '';
  showLogin();
});

// 부팅: 저장된 토큰으로 자동 로그인 시도
(async () => {
  if (token) {
    try {
      const r = await fetchStats(token);
      if (r.ok) { showDashboard(); return; }
      localStorage.removeItem(TOKEN_KEY);
      token = '';
    } catch (_) {}
  }
  showLogin();
})();
</script>
</body>
</html>`;
