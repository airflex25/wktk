package com.wktk.webrtc

import org.webrtc.DataChannel
import org.webrtc.IceCandidate
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.RtpReceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription

/**
 * WebRTC의 콜백 인터페이스가 워낙 광범위해서 매번 anonymous class로 만들면 보일러플레이트가 많다.
 * 여기서는 빈 구현 + 람다 hook을 가진 어댑터를 제공해, 필요한 콜백만 짧게 오버라이드/주입할 수 있게 한다.
 */
open class SdpObserverAdapter(
    private val onSuccess: ((SessionDescription) -> Unit)? = null,
    private val onSetSuccess: (() -> Unit)? = null,
    private val onFailure: ((String?) -> Unit)? = null,
) : SdpObserver {
    override fun onCreateSuccess(sdp: SessionDescription) { onSuccess?.invoke(sdp) }
    override fun onSetSuccess() { onSetSuccess?.invoke() }
    override fun onCreateFailure(error: String?) { onFailure?.invoke(error) }
    override fun onSetFailure(error: String?) { onFailure?.invoke(error) }
}

open class PeerConnectionObserverAdapter : PeerConnection.Observer {
    override fun onSignalingChange(state: PeerConnection.SignalingState) {}
    override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {}
    override fun onIceConnectionReceivingChange(receiving: Boolean) {}
    override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
    override fun onIceCandidate(candidate: IceCandidate) {}
    override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
    override fun onAddStream(stream: MediaStream) {}
    override fun onRemoveStream(stream: MediaStream) {}
    override fun onDataChannel(channel: DataChannel) {}
    override fun onRenegotiationNeeded() {}
    override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
}
