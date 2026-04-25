// Socket.IO 시그널링 핸들러.
// 프로토콜 사양은 docs/protocol.md 참고.

import {
  isValidKey,
  generateUnusedKey,
  joinRoom,
  leaveRoom,
  roomOf,
  peersIn,
} from './room.js';

export function attachSignaling(io) {
  io.on('connection', (socket) => {
    const peerId = socket.id;
    console.log(`[wktk] connect ${peerId}`);

    socket.on('key:request', () => {
      const key = generateUnusedKey();
      socket.emit('key:assigned', { key });
    });

    socket.on('key:join', ({ key } = {}) => {
      if (!isValidKey(key)) {
        socket.emit('error', { code: 'INVALID_KEY', message: '6 digits required' });
        return;
      }
      // 이미 다른 룸에 있다면 먼저 나가게 한다.
      const prev = roomOf(peerId);
      if (prev) {
        socket.leave(prev);
        leaveRoom(peerId);
        socket.to(prev).emit('peer:left', { peerId });
      }
      const res = joinRoom(key, peerId);
      if (!res.ok) {
        socket.emit('error', { code: res.code, message: res.code });
        return;
      }
      socket.join(key);
      socket.emit('key:joined', { key, self: peerId, peers: res.peers });
      socket.to(key).emit('peer:joined', { peerId });
    });

    socket.on('key:leave', () => {
      const key = leaveRoom(peerId);
      if (key) {
        socket.leave(key);
        socket.to(key).emit('peer:left', { peerId });
      }
    });

    socket.on('signal', ({ to, type, payload } = {}) => {
      const key = roomOf(peerId);
      if (!key) {
        socket.emit('error', { code: 'NOT_IN_ROOM', message: 'join a key first' });
        return;
      }
      if (!to || !type) {
        socket.emit('error', { code: 'BAD_SIGNAL', message: 'to+type required' });
        return;
      }
      // 같은 룸 안의 대상에게만 전달한다.
      const peers = peersIn(key, peerId);
      if (!peers.includes(to)) {
        socket.emit('error', { code: 'PEER_NOT_FOUND', message: to });
        return;
      }
      io.to(to).emit('signal', { from: peerId, type, payload });
    });

    socket.on('disconnect', () => {
      const key = leaveRoom(peerId);
      if (key) socket.to(key).emit('peer:left', { peerId });
      console.log(`[wktk] disconnect ${peerId}`);
    });
  });
}
