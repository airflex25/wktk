# Android Patterns

자주 쓰는 안드로이드 측 변경 템플릿. 필요할 때만 읽는다.

## 새 Intent / State 필드 추가

1. `WktkState` 에 필드 추가 (디폴트값 포함)
2. `WktkIntent` 에 sealed case 추가
3. `WktkViewModel.onIntent` 의 `when` 에 분기 추가 — `_state.update { it.copy(...) }` 가 표준 패턴
4. `WktkApp.kt` 의 해당 화면에서 새 필드를 표시하거나 새 intent 를 디스패치

UI는 항상 `state` 한 덩어리만 받는다. ViewModel을 직접 import 하지 마라.

## 새 시그널링 이벤트 처리

`SignalingClient.kt`:
```kotlin
on("peer:mute") { args ->
    val o = args.firstOrNull() as? JSONObject ?: return@on
    channel.trySend(SignalingEvent.PeerMute(o.optString("peerId"), o.optBoolean("muted")))
}
```

- `SignalingEvent` sealed class에 새 case
- `WktkViewModel.onEvent` 의 `when` 에 분기
- 필요하면 `WktkState` 에 반영

## PeerConnection 재협상이 필요한 경우

송수신 토글은 `setEnabled` 만으로 충분. 그러나 다음은 재협상 필요:
- 비디오 트랙 추가
- 데이터 채널 추가
- 코덱 변경

이 경우 `RtcManager` 에 `renegotiate(peerId)` 메서드를 추가하고:
1. 새 트랙/채널을 PeerConnection에 add
2. `createOffer` → setLocalDescription → `signaling.sendSignal(peerId, "offer", ...)`
3. 상대는 평소처럼 answer 응답

기존 RtcManager의 `callPeers` 와 거의 같은 흐름이지만, 룸 입장이 아니라 사용자 액션이 트리거.

## 백그라운드 통화 (ForegroundService)

```kotlin
class WktkService : Service() {
    override fun onStartCommand(...): Int {
        startForeground(1, buildNotification())
        // SignalingClient + RtcManager 를 여기로 이동
        return START_STICKY
    }
}
```

`AndroidManifest.xml`:
```xml
<service
    android:name=".WktkService"
    android:foregroundServiceType="microphone"
    android:exported="false" />
```

ViewModel에서 직접 RTC를 관리하던 코드는 Service 측 매니저로 옮기고,
ViewModel 은 ServiceConnection 으로 상태만 구독한다.

처음부터 이걸 하지는 말고, 포그라운드 한정 동작이 안정된 다음에 분리해라.

## 하드웨어/외부 PTT 버튼

- 블루투스 헤드셋의 미디어 버튼: `MediaSessionCompat` 으로 캐치.
- 단순 키 이벤트(예: 볼륨 다운):
  ```kotlin
  override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
      if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
          vm.onIntent(WktkIntent.PttPress); return true
      }
      return super.onKeyDown(keyCode, event)
  }
  ```
- 시스템 볼륨 조작과 충돌하지 않게 사용자가 옵션으로 켜도록 노출하는 것을 권장.

## 오디오 라우팅 디테일

`AudioRouter.enterCallMode(speakerOn = true)` 가 호출된 뒤엔
시스템 볼륨 슬라이더가 `STREAM_VOICE_CALL` 을 따른다.
사용자 혼란을 줄이려면 룸 화면에서만 `enterCallMode`, 키 입력 화면에선 `exitCallMode`.
