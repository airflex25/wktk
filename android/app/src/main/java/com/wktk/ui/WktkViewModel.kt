package com.wktk.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.wktk.BuildConfig
import com.wktk.audio.AudioRouter
import com.wktk.signaling.SignalingClient
import com.wktk.signaling.SignalingEvent
import com.wktk.webrtc.RtcManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * 단일 ViewModel — UI는 [WktkState] 한 덩어리만 본다.
 * intent → state 전환만 여기서 처리하고, 시그널링/RTC 세부는 위임한다.
 */
class WktkViewModel(app: Application) : AndroidViewModel(app) {

    private val _state = MutableStateFlow(WktkState())
    val state: StateFlow<WktkState> = _state.asStateFlow()

    private val signaling = SignalingClient(BuildConfig.SIGNALING_URL)
    private val rtc = RtcManager(app, signaling)
    private val audio = AudioRouter(app)

    init {
        viewModelScope.launch {
            signaling.events.collect(::onEvent)
        }
        signaling.connect()
        rtc.start()
        audio.enterCallMode(speakerOn = true)
    }

    fun onIntent(i: WktkIntent) = when (i) {
        is WktkIntent.UpdateKeyInput -> _state.update { it.copy(keyInput = i.value) }
        WktkIntent.RequestRandomKey -> { signaling.requestKey(); Unit }
        WktkIntent.JoinKey -> {
            val k = state.value.keyInput
            if (k.length == 6 && k.all(Char::isDigit)) {
                _state.update { it.copy(error = null) }
                signaling.joinKey(k)
            } else {
                _state.update { it.copy(error = "6자리 숫자를 입력하세요") }
            }
        }
        WktkIntent.LeaveKey -> {
            signaling.leaveKey()
            _state.update { WktkState(keyInput = it.keyInput) }
        }
        is WktkIntent.SetMode -> {
            _state.update { it.copy(mode = i.mode) }
            // VOX는 즉시 송신 ON, PTT는 OFF로 시작 (버튼 누르는 동안만 ON).
            rtc.setMicEnabled(i.mode == TalkMode.VOX)
        }
        is WktkIntent.PttPress -> {
            if (state.value.mode == TalkMode.PTT) rtc.setMicEnabled(true)
            _state.update { it.copy(transmitting = true) }
        }
        is WktkIntent.PttRelease -> {
            if (state.value.mode == TalkMode.PTT) rtc.setMicEnabled(false)
            _state.update { it.copy(transmitting = false) }
        }
    }

    private fun onEvent(e: SignalingEvent) {
        when (e) {
            SignalingEvent.Connected ->
                _state.update { it.copy(connected = true) }
            SignalingEvent.Disconnected ->
                _state.update { it.copy(connected = false) }
            is SignalingEvent.KeyAssigned ->
                _state.update { it.copy(keyInput = e.key) }
            is SignalingEvent.KeyJoined -> {
                _state.update { it.copy(joinedKey = e.key, peers = e.peers, error = null) }
                // 신참은 기존 피어들에게 offer를 만든다 (protocol.md 참고).
                if (e.peers.isNotEmpty()) rtc.callPeers(e.peers)
            }
            is SignalingEvent.PeerJoined ->
                _state.update { it.copy(peers = it.peers + e.peerId) }
            is SignalingEvent.PeerLeft -> {
                rtc.removePeer(e.peerId)
                _state.update { it.copy(peers = it.peers - e.peerId) }
            }
            is SignalingEvent.Signal ->
                rtc.onSignal(e.from, e.type, e.payload)
            is SignalingEvent.Error ->
                _state.update { it.copy(error = "${e.code}: ${e.message}") }
        }
    }

    override fun onCleared() {
        super.onCleared()
        rtc.closeAll()
        signaling.disconnect()
        audio.exitCallMode()
    }
}

enum class TalkMode { PTT, VOX }

data class WktkState(
    val connected: Boolean = false,
    val keyInput: String = "",
    val joinedKey: String? = null,
    val peers: List<String> = emptyList(),
    val mode: TalkMode = TalkMode.PTT,
    val transmitting: Boolean = false,
    val error: String? = null,
)

sealed class WktkIntent {
    data class UpdateKeyInput(val value: String) : WktkIntent()
    object RequestRandomKey : WktkIntent()
    object JoinKey : WktkIntent()
    object LeaveKey : WktkIntent()
    data class SetMode(val mode: TalkMode) : WktkIntent()
    object PttPress : WktkIntent()
    object PttRelease : WktkIntent()
}
