import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// 서버 프로토콜 사양: docs/protocol.md
sealed class SignalingEvent {}

class Connected extends SignalingEvent {}

class Disconnected extends SignalingEvent {}

class KeyAssigned extends SignalingEvent {
  final String key;
  KeyAssigned(this.key);
}

class KeyJoined extends SignalingEvent {
  final String key;
  final String self;
  final List<String> peers;
  KeyJoined(this.key, this.self, this.peers);
}

class PeerJoined extends SignalingEvent {
  final String peerId;
  PeerJoined(this.peerId);
}

class PeerLeft extends SignalingEvent {
  final String peerId;
  PeerLeft(this.peerId);
}

class Signal extends SignalingEvent {
  final String from;
  final String type;
  final dynamic payload;
  Signal(this.from, this.type, this.payload);
}

class SignalingErrorEvent extends SignalingEvent {
  final String code;
  final String message;
  SignalingErrorEvent(this.code, this.message);
}

class SignalingService {
  final String url;
  io.Socket? _socket;
  final _controller = StreamController<SignalingEvent>.broadcast();
  Stream<SignalingEvent> get events => _controller.stream;

  SignalingService(this.url);

  void connect() {
    if (_socket?.connected == true) return;
    final socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setTimeout(15000)
          .build(),
    );
    socket.onConnect((_) {
      // ignore: avoid_print
      print('[wktk-sig] CONNECTED');
      _controller.add(Connected());
    });
    socket.onDisconnect((reason) {
      // ignore: avoid_print
      print('[wktk-sig] DISCONNECTED $reason');
      _controller.add(Disconnected());
    });
    socket.onConnectError((e) {
      // ignore: avoid_print
      print('[wktk-sig] connect error: $e');
    });
    socket.onError((e) {
      // ignore: avoid_print
      print('[wktk-sig] socket error: $e');
    });
    socket.on('key:assigned', (data) {
      final key = (data as Map?)?['key'] as String?;
      if (key != null) _controller.add(KeyAssigned(key));
    });
    socket.on('key:joined', (data) {
      final m = data as Map? ?? const {};
      _controller.add(KeyJoined(
        m['key'] as String? ?? '',
        m['self'] as String? ?? '',
        (m['peers'] as List? ?? const []).cast<String>(),
      ));
    });
    socket.on('peer:joined', (data) {
      final id = (data as Map?)?['peerId'] as String?;
      if (id != null) _controller.add(PeerJoined(id));
    });
    socket.on('peer:left', (data) {
      final id = (data as Map?)?['peerId'] as String?;
      if (id != null) _controller.add(PeerLeft(id));
    });
    socket.on('signal', (data) {
      final m = data as Map? ?? const {};
      _controller.add(Signal(
        m['from'] as String? ?? '',
        m['type'] as String? ?? '',
        m['payload'],
      ));
    });
    socket.on('error', (data) {
      final m = data as Map? ?? const {};
      _controller.add(SignalingErrorEvent(
        m['code'] as String? ?? '',
        m['message'] as String? ?? '',
      ));
    });
    socket.connect();
    _socket = socket;
  }

  void requestKey() => _socket?.emit('key:request');
  void joinKey(String key) => _socket?.emit('key:join', {'key': key});
  void leaveKey() => _socket?.emit('key:leave');
  void sendSignal(String to, String type, Object payload) {
    _socket?.emit('signal', {'to': to, 'type': type, 'payload': payload});
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}
