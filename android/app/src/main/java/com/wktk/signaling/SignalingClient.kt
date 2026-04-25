package com.wktk.signaling

import io.socket.client.IO
import io.socket.client.Socket
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import org.json.JSONObject

/**
 * 서버 프로토콜 사양: docs/protocol.md
 *
 * 이 클래스는 raw Socket.IO 이벤트를 [SignalingEvent] sealed class 스트림으로 변환만 한다.
 * WebRTC와의 결합은 [com.wktk.webrtc.RtcManager] 가 담당.
 */
class SignalingClient(private val url: String) {

    private var socket: Socket? = null
    private val channel = Channel<SignalingEvent>(Channel.BUFFERED)
    val events: Flow<SignalingEvent> = channel.receiveAsFlow()

    fun connect() {
        if (socket?.connected() == true) return
        val opts = IO.Options.builder()
            .setReconnection(true)
            .setReconnectionDelay(1_000)
            .build()
        socket = IO.socket(url, opts).apply {
            on(Socket.EVENT_CONNECT) { channel.trySend(SignalingEvent.Connected) }
            on(Socket.EVENT_DISCONNECT) { channel.trySend(SignalingEvent.Disconnected) }

            on("key:assigned") { args ->
                val key = (args.firstOrNull() as? JSONObject)?.optString("key") ?: return@on
                channel.trySend(SignalingEvent.KeyAssigned(key))
            }
            on("key:joined") { args ->
                val o = args.firstOrNull() as? JSONObject ?: return@on
                val peers = o.optJSONArray("peers")
                val list = (0 until (peers?.length() ?: 0)).map { peers!!.getString(it) }
                channel.trySend(
                    SignalingEvent.KeyJoined(
                        key = o.optString("key"),
                        self = o.optString("self"),
                        peers = list,
                    )
                )
            }
            on("peer:joined") { args ->
                val id = (args.firstOrNull() as? JSONObject)?.optString("peerId") ?: return@on
                channel.trySend(SignalingEvent.PeerJoined(id))
            }
            on("peer:left") { args ->
                val id = (args.firstOrNull() as? JSONObject)?.optString("peerId") ?: return@on
                channel.trySend(SignalingEvent.PeerLeft(id))
            }
            on("signal") { args ->
                val o = args.firstOrNull() as? JSONObject ?: return@on
                channel.trySend(
                    SignalingEvent.Signal(
                        from = o.optString("from"),
                        type = o.optString("type"),
                        payload = o.opt("payload"),
                    )
                )
            }
            on("error") { args ->
                val o = args.firstOrNull() as? JSONObject ?: return@on
                channel.trySend(
                    SignalingEvent.Error(
                        code = o.optString("code"),
                        message = o.optString("message"),
                    )
                )
            }
            connect()
        }
    }

    fun requestKey() = socket?.emit("key:request")
    fun joinKey(key: String) = socket?.emit("key:join", JSONObject().put("key", key))
    fun leaveKey() = socket?.emit("key:leave")

    fun sendSignal(to: String, type: String, payload: Any) {
        val o = JSONObject()
            .put("to", to)
            .put("type", type)
            .put("payload", payload)
        socket?.emit("signal", o)
    }

    fun disconnect() {
        socket?.disconnect()
        socket = null
    }
}

sealed class SignalingEvent {
    object Connected : SignalingEvent()
    object Disconnected : SignalingEvent()
    data class KeyAssigned(val key: String) : SignalingEvent()
    data class KeyJoined(val key: String, val self: String, val peers: List<String>) : SignalingEvent()
    data class PeerJoined(val peerId: String) : SignalingEvent()
    data class PeerLeft(val peerId: String) : SignalingEvent()
    data class Signal(val from: String, val type: String, val payload: Any?) : SignalingEvent()
    data class Error(val code: String, val message: String) : SignalingEvent()
}
