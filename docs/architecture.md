# Architecture

## 전체 흐름

```
[Android A]                [Signaling Server]                [Android B]
    |                              |                              |
    |--- join { key:"482910" } -->|                              |
    |                              |<-- join { key:"482910" } ----|
    |<-- peers [B]   ------------|--- peers [A] -------------->|
    |                              |                              |
    |--- offer (SDP) ------------>|--- offer ------------------->|
    |<-- answer (SDP) ------------|<-- answer -------------------|
    |--- ice candidates --------->|--- ice candidates ---------->|
    |<-- ice candidates -----------|<-- ice candidates -----------|
    |                              |                              |
    |================ P2P 음성 (WebRTC, SRTP) ===================|
```

서버는 시그널링이 끝나면 음성 트래픽을 거의 보지 않는다.
NAT 뚫기에 실패하면 TURN 서버를 통해 릴레이된다 (선택).

## 컴포넌트별 책임

### Server (`server/`)
- 키 룸 매칭: 같은 6자리 키를 입력한 클라이언트들을 같은 Socket.IO room에 모은다.
- 시그널링 중계: `offer`, `answer`, `ice-candidate` 메시지를 다른 피어에게 전달.
- 키 발급: 클라이언트가 요청하면 사용 중이지 않은 랜덤 6자리 키를 응답.
- **음성 데이터 자체는 절대 통과시키지 않는다.**

### Android (`android/`)
- UI 레이어 (Jetpack Compose): 키 입력 → 룸 화면 (PTT 버튼, VOX 토글, 피어 목록).
- WebRTC 레이어: PeerConnection 생성/관리, 오디오 트랙 송수신, 마이크 ON/OFF 제어.
- Signaling 레이어: Socket.IO 클라이언트, 서버와 메시지 교환.
- Audio 레이어: AudioManager 모드 전환, 권한 처리.

## PTT vs VOX 구현

대화 모드는 송신 측 오디오 트랙의 enabled 플래그로만 제어한다.

```
PTT 버튼 누름  → localAudioTrack.setEnabled(true)
PTT 버튼 뗌    → localAudioTrack.setEnabled(false)

VOX ON         → localAudioTrack.setEnabled(true)  (계속 켜둠)
VOX OFF        → localAudioTrack.setEnabled(false)
```

PeerConnection을 매번 재협상할 필요가 없어 매우 가볍다.
수신은 항상 켜져 있다 (`remoteAudioTrack.setEnabled(true)`).

## 멀티피어

같은 키 룸에 N명이 들어오면 N×(N-1)/2개의 PeerConnection이 만들어진다 (full-mesh).
실용적인 권장 인원은 4명 이하. 그 이상은 SFU(예: mediasoup) 도입을 검토.
