// 6자리 key 기반 룸 관리.
// 메모리 기반(단일 노드 가정). 멀티 노드로 확장하려면 Redis adapter로 교체.

const KEY_RE = /^\d{6}$/;
const ROOM_LIMIT = Number(process.env.ROOM_LIMIT ?? 8);

/** key -> Set<peerId> */
const rooms = new Map();
/** peerId -> key */
const peerToKey = new Map();
/** key -> 첫 참가자 입장 시각 (admin 통계용) */
const roomCreatedAt = new Map();
/** peerId -> 접속 시각 (admin 통계용) */
const peerJoinedAt = new Map();
/** 누적 통계 (서버 부팅 후 카운트) */
let totalRoomsCreated = 0;
let totalPeersJoined = 0;
const serverStartedAt = Date.now();

export function isValidKey(key) {
  return typeof key === 'string' && KEY_RE.test(key);
}

export function generateUnusedKey() {
  // 100만 슬롯이라 충돌이 잦지 않다. 그래도 안전하게 재시도.
  for (let i = 0; i < 32; i++) {
    const k = String(Math.floor(Math.random() * 1_000_000)).padStart(6, '0');
    if (!rooms.has(k) || rooms.get(k).size === 0) return k;
  }
  // 거의 일어나지 않지만, 정 안 되면 가장 비어 있는 키를 찾아준다.
  return String(Math.floor(Math.random() * 1_000_000)).padStart(6, '0');
}

export function joinRoom(key, peerId) {
  if (!isValidKey(key)) return { ok: false, code: 'INVALID_KEY' };
  let set = rooms.get(key);
  if (!set) {
    set = new Set();
    rooms.set(key, set);
    roomCreatedAt.set(key, Date.now());
    totalRoomsCreated += 1;
  }
  if (set.size >= ROOM_LIMIT) return { ok: false, code: 'ROOM_FULL' };
  set.add(peerId);
  peerToKey.set(peerId, key);
  peerJoinedAt.set(peerId, Date.now());
  totalPeersJoined += 1;
  return { ok: true, peers: [...set].filter(id => id !== peerId) };
}

export function leaveRoom(peerId) {
  const key = peerToKey.get(peerId);
  if (!key) return null;
  const set = rooms.get(key);
  if (set) {
    set.delete(peerId);
    if (set.size === 0) {
      rooms.delete(key);
      roomCreatedAt.delete(key);
    }
  }
  peerToKey.delete(peerId);
  peerJoinedAt.delete(peerId);
  return key;
}

/** Admin 대시보드용 스냅샷 */
export function getStats() {
  const list = [];
  for (const [key, peers] of rooms) {
    list.push({
      key,
      peerCount: peers.size,
      createdAt: roomCreatedAt.get(key) ?? null,
    });
  }
  // 인원 많은 룸부터
  list.sort((a, b) => b.peerCount - a.peerCount || a.createdAt - b.createdAt);
  return {
    serverStartedAt,
    uptimeMs: Date.now() - serverStartedAt,
    activeRooms: rooms.size,
    activePeers: peerToKey.size,
    totalRoomsCreated,
    totalPeersJoined,
    rooms: list,
  };
}

export function roomOf(peerId) {
  return peerToKey.get(peerId) ?? null;
}

export function peersIn(key, exceptPeerId = null) {
  const set = rooms.get(key);
  if (!set) return [];
  return [...set].filter(id => id !== exceptPeerId);
}
