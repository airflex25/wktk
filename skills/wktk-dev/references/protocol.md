# Protocol Quick Reference

`docs/protocol.md` 의 캐시본. 변경 시 양쪽 모두 갱신.

## Client → Server
| event | payload |
|-------|---------|
| `key:request` | `{}` |
| `key:join` | `{ key: "<6digits>" }` |
| `key:leave` | `{}` |
| `signal` | `{ to, type, payload }` |

## Server → Client
| event | payload |
|-------|---------|
| `key:assigned` | `{ key }` |
| `key:joined` | `{ key, self, peers: [] }` |
| `peer:joined` | `{ peerId }` |
| `peer:left` | `{ peerId }` |
| `signal` | `{ from, type, payload }` |
| `error` | `{ code, message }` |

## signal type별 payload
- `offer`/`answer`: `{ type, sdp }`
- `ice`: `{ sdpMid, sdpMLineIndex, candidate }`

## Error codes
`INVALID_KEY`, `ROOM_FULL`, `NOT_IN_ROOM`, `PEER_NOT_FOUND`, `BAD_SIGNAL`

## Glare 방지 규칙
**나중에 들어온 피어가 offer를 만든다.** 입장 시 받은 `peers` 가 비어있지 않으면 그들 모두에게 offer.
