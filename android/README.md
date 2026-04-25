# wktk-android

Kotlin + Jetpack Compose. 단일 액티비티, 단일 ViewModel.

## 모듈 구성

```
app/src/main/java/com/wktk/
├── MainActivity.kt          # 권한 요청 + Compose 진입
├── ui/
│   ├── WktkApp.kt           # KeyEntryScreen + RoomScreen + PttButton
│   └── WktkViewModel.kt     # 단일 state + intent 처리
├── signaling/
│   └── SignalingClient.kt   # Socket.IO 래퍼 → SignalingEvent flow
├── webrtc/
│   ├── RtcManager.kt        # PeerConnection 풀 관리
│   └── Adapters.kt          # SDP/PC observer 보일러플레이트 제거
└── audio/
    └── AudioRouter.kt       # AudioManager 모드/스피커 토글
```

## 시그널링 서버 주소

`app/build.gradle.kts` 의 `SIGNALING_URL` BuildConfig 필드를 바꾸세요.
디버그 기본값은 에뮬레이터에서 호스트 머신에 도달할 수 있는 `http://10.0.2.2:3000`.

## 권한

- `RECORD_AUDIO` — 시작 시 한 번 요청
- `INTERNET`, `ACCESS_NETWORK_STATE` — Socket.IO + WebRTC

백그라운드에서 계속 통신하고 싶다면 `FOREGROUND_SERVICE_MICROPHONE` 권한을 활용한 포그라운드 서비스를 추가하세요. (현재 스켈레톤은 포그라운드 화면 기준)

## PTT vs VOX 동작

핵심은 `RtcManager.setMicEnabled(true/false)` 한 줄입니다.
PeerConnection은 그대로 두고 로컬 오디오 트랙만 켜고 끄기 때문에 재협상이 없어 가볍습니다.
