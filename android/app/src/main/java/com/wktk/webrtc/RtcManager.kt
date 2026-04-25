package com.wktk.webrtc

import android.content.Context
import com.wktk.signaling.SignalingClient
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.SessionDescription
import org.json.JSONObject

/**
 * 키 룸 안의 여러 피어와 full-mesh PeerConnection을 관리한다.
 *
 * 핵심 규칙 (docs/protocol.md):
 *   - 신참(나중에 들어온 사람)이 기존 피어에게 offer를 만든다.
 *   - 같은 키 룸의 모든 메시지는 SignalingClient를 통해 to=peerId로 라우팅.
 *   - 송신 토글은 [setMicEnabled]만 호출 (재협상 불필요).
 */
class RtcManager(
    private val context: Context,
    private val signaling: SignalingClient,
) {

    private var factory: PeerConnectionFactory? = null

    private fun getFactory(): PeerConnectionFactory {
        return factory ?: run {
            PeerConnectionFactory.initialize(
                PeerConnectionFactory.InitializationOptions.builder(context)
                    .createInitializationOptions()
            )
            PeerConnectionFactory.builder()
                .createPeerConnectionFactory()
                .also { factory = it }
        }
    }

    private val iceServers = listOf(
        // 공개 STUN. 운영용으로는 자체 TURN 추가를 권장.
        PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
        PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer(),
    )

    private val audioConstraints = MediaConstraints().apply {
        mandatory.add(MediaConstraints.KeyValuePair("googEchoCancellation", "true"))
        mandatory.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "true"))
        mandatory.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
        mandatory.add(MediaConstraints.KeyValuePair("googHighpassFilter", "true"))
    }

    private var audioSource: AudioSource? = null
    private var localAudioTrack: AudioTrack? = null

    private val peers = mutableMapOf<String, PeerConnection>()

    fun start() {
        if (localAudioTrack != null) return
        val f = getFactory()
        audioSource = f.createAudioSource(audioConstraints)
        localAudioTrack = f.createAudioTrack("audio0", audioSource).apply {
            // 기본은 PTT이므로 송신 OFF로 시작.
            setEnabled(false)
        }
    }

    fun setMicEnabled(enabled: Boolean) {
        localAudioTrack?.setEnabled(enabled)
    }

    /** 신참이 호출. 기존 피어 각각에 offer를 만들어 보낸다. */
    fun callPeers(peerIds: List<String>) {
        peerIds.forEach { id ->
            val pc = ensurePeer(id)
            pc.createOffer(SdpObserverAdapter(
                onSuccess = { sdp ->
                    pc.setLocalDescription(SdpObserverAdapter(), sdp)
                    signaling.sendSignal(id, "offer", JSONObject()
                        .put("type", sdp.type.canonicalForm())
                        .put("sdp", sdp.description))
                }
            ), MediaConstraints())
        }
    }

    fun onSignal(from: String, type: String, payload: Any?) {
        val pc = ensurePeer(from)
        when (type) {
            "offer" -> {
                val o = payload as? JSONObject ?: return
                val sdp = SessionDescription(SessionDescription.Type.OFFER, o.getString("sdp"))
                pc.setRemoteDescription(SdpObserverAdapter(
                    onSetSuccess = {
                        pc.createAnswer(SdpObserverAdapter(
                            onSuccess = { ans ->
                                pc.setLocalDescription(SdpObserverAdapter(), ans)
                                signaling.sendSignal(from, "answer", JSONObject()
                                    .put("type", ans.type.canonicalForm())
                                    .put("sdp", ans.description))
                            }
                        ), MediaConstraints())
                    }
                ), sdp)
            }
            "answer" -> {
                val o = payload as? JSONObject ?: return
                val sdp = SessionDescription(SessionDescription.Type.ANSWER, o.getString("sdp"))
                pc.setRemoteDescription(SdpObserverAdapter(), sdp)
            }
            "ice" -> {
                val o = payload as? JSONObject ?: return
                val candidate = o.optString("candidate")
                if (candidate.isNotEmpty()) {
                    pc.addIceCandidate(
                        IceCandidate(
                            o.optString("sdpMid"),
                            o.optInt("sdpMLineIndex"),
                            candidate,
                        )
                    )
                }
            }
        }
    }

    fun removePeer(peerId: String) {
        peers.remove(peerId)?.dispose()
    }

    fun closeAll() {
        peers.values.forEach { it.dispose() }
        peers.clear()
        localAudioTrack?.dispose()
        localAudioTrack = null
        audioSource?.dispose()
        audioSource = null
        factory?.dispose()
        factory = null
    }

    private fun ensurePeer(peerId: String): PeerConnection {
        peers[peerId]?.let { return it }
        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
        }
        val observer = object : PeerConnectionObserverAdapter() {
            override fun onIceCandidate(candidate: IceCandidate) {
                signaling.sendSignal(peerId, "ice", JSONObject()
                    .put("sdpMid", candidate.sdpMid)
                    .put("sdpMLineIndex", candidate.sdpMLineIndex)
                    .put("candidate", candidate.sdp))
            }

            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {
                // 원격 오디오 트랙은 WebRTC 가 자동으로 AudioManager 를 통해 재생하므로
                // 별도 처리 없이 enabled = true 만 확인한다.
                receiver.track()?.setEnabled(true)
            }

            override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState) {
                if (newState == PeerConnection.IceConnectionState.FAILED) {
                    // ICE 재시도: restart offer 를 만들어 보낸다.
                    peers[peerId]?.let { pc ->
                        val mc = MediaConstraints().apply {
                            mandatory.add(MediaConstraints.KeyValuePair("IceRestart", "true"))
                        }
                        pc.createOffer(SdpObserverAdapter(
                            onSuccess = { sdp ->
                                pc.setLocalDescription(SdpObserverAdapter(), sdp)
                                signaling.sendSignal(peerId, "offer", JSONObject()
                                    .put("type", sdp.type.canonicalForm())
                                    .put("sdp", sdp.description))
                            }
                        ), mc)
                    }
                }
            }
        }
        val pc = getFactory().createPeerConnection(rtcConfig, observer)
            ?: error("PeerConnection 생성 실패: $peerId")
        localAudioTrack?.let { pc.addTrack(it, listOf("stream0")) }
        peers[peerId] = pc
        return pc
    }
}
