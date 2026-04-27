import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling.dart';

/// 키 룸 안의 여러 피어와 full-mesh PeerConnection 관리.
///
/// 핵심 규칙 (docs/protocol.md):
///   - 신참(나중에 들어온 사람)이 기존 피어에게 offer.
///   - 송신 토글은 [setMicEnabled]만 호출 (재협상 불필요).
class RtcService {
  final SignalingService signaling;
  final String signalingUrl;
  final _peers = <String, RTCPeerConnection>{};
  MediaStream? _localStream;

  /// 0.0~1.0 범위. 가장 큰 소리 내고 있는 피어의 audioLevel.
  /// UI 파형 애니메이션용.
  final _peerAudioLevel = ValueNotifier<double>(0.0);
  ValueListenable<double> get peerAudioLevel => _peerAudioLevel;
  Timer? _statsTimer;

  /// ICE connected 상태인 peerId 집합. UI에서 "연결 중" / "연결됨" 구분.
  final _connectedPeers = ValueNotifier<Set<String>>(<String>{});
  ValueListenable<Set<String>> get connectedPeers => _connectedPeers;

  RtcService(this.signaling, {required this.signalingUrl});

  // 기본 ICE servers (Google STUN). TURN fetch 실패 시 fallback.
  static const _fallbackIceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  // 서버에서 받은 Cloudflare TURN ice servers. 없으면 fallback.
  List<Map<String, dynamic>> _iceServers = const [];
  Future<void>? _turnFetchInFlight;

  Map<String, dynamic> get _config => {
        'iceServers': _iceServers.isEmpty ? _fallbackIceServers : _iceServers,
        'sdpSemantics': 'unified-plan',
      };

  /// 서버 /turn-credentials 호출. 실패해도 STUN-only로 동작.
  Future<void> _refreshTurnCredentials() async {
    if (_turnFetchInFlight != null) return _turnFetchInFlight;
    final completer = Completer<void>();
    _turnFetchInFlight = completer.future;
    try {
      final uri = Uri.parse('$signalingUrl/turn-credentials');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        debugPrint('[wktk-rtc] TURN cred status ${resp.statusCode}');
      } else {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final ice = data['iceServers'];
        if (ice is Map) {
          _iceServers = [Map<String, dynamic>.from(ice)];
        } else if (ice is List) {
          _iceServers = ice.cast<Map<String, dynamic>>();
        }
        debugPrint('[wktk-rtc] TURN servers loaded (${_iceServers.length})');
      }
    } catch (e) {
      debugPrint('[wktk-rtc] TURN cred fetch failed: $e');
    } finally {
      completer.complete();
      _turnFetchInFlight = null;
    }
  }

  Future<void> start() async {
    if (_localStream != null) return;
    // 백그라운드로 TURN 자격증명 받아오기 (응답 안 와도 STUN으로는 진행 가능).
    unawaited(_refreshTurnCredentials());
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    // iOS: 스피커폰 모드 + 통화용 오디오 세션. 안 하면 수화기 모드라 들리지 않음.
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
    // PTT 기본이라 마이크 OFF로 시작.
    setMicEnabled(false);
    _startStatsPolling();
  }

  // peerId → 직전 inbound-rtp totalAudioEnergy 값.
  // 변화량(power) 으로 현재 음량 추정.
  final _prevEnergy = <String, double>{};
  static const _statsInterval = Duration(milliseconds: 150);
  int _statsTick = 0;

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_statsInterval, (_) async {
      if (_peers.isEmpty) {
        if (_peerAudioLevel.value != 0) _peerAudioLevel.value = 0;
        return;
      }
      double maxLevel = 0;
      double maxDelta = 0;
      double rawEnergy = 0;
      for (final entry in _peers.entries) {
        final peerId = entry.key;
        final pc = entry.value;
        try {
          final reports = await pc.getStats();
          for (final r in reports) {
            if (r.type != 'inbound-rtp') continue;
            if (r.values['kind'] != 'audio') continue;
            final energy = (r.values['totalAudioEnergy'] as num?)?.toDouble();
            if (energy == null) continue;
            if (energy > rawEnergy) rawEnergy = energy;
            final prev = _prevEnergy[peerId];
            _prevEnergy[peerId] = energy;
            if (prev == null) continue;
            final delta = energy - prev;
            if (delta > maxDelta) maxDelta = delta;
            if (delta <= 0) continue;
            final lvl = (math.sqrt(delta * 8)).clamp(0.0, 1.0);
            if (lvl > maxLevel) maxLevel = lvl;
          }
        } catch (_) {}
      }
      _peerAudioLevel.value = maxLevel;
      // ~1.5초마다 한 번 디버그 출력
      if ((_statsTick++ % 10) == 0) {
        debugPrint(
            '[wktk-rtc] energy=${rawEnergy.toStringAsFixed(6)} delta=${maxDelta.toStringAsFixed(6)} lvl=${maxLevel.toStringAsFixed(3)}');
      }
    });
  }

  void setMicEnabled(bool enabled) {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
  }

  Future<void> callPeers(List<String> peerIds) async {
    for (final id in peerIds) {
      final pc = await _ensurePeer(id);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      signaling.sendSignal(id, 'offer', {'type': offer.type, 'sdp': offer.sdp});
    }
  }

  Future<void> onSignal(String from, String type, dynamic payload) async {
    final pc = await _ensurePeer(from);
    if (payload is! Map) return;
    final p = Map<String, dynamic>.from(payload);
    switch (type) {
      case 'offer':
        await pc.setRemoteDescription(
          RTCSessionDescription(p['sdp'] as String?, 'offer'),
        );
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        signaling.sendSignal(
          from,
          'answer',
          {'type': answer.type, 'sdp': answer.sdp},
        );
        break;
      case 'answer':
        await pc.setRemoteDescription(
          RTCSessionDescription(p['sdp'] as String?, 'answer'),
        );
        break;
      case 'ice':
        final candidate = p['candidate'] as String?;
        if (candidate != null && candidate.isNotEmpty) {
          await pc.addCandidate(RTCIceCandidate(
            candidate,
            p['sdpMid'] as String?,
            p['sdpMLineIndex'] as int?,
          ));
        }
        break;
    }
  }

  Future<void> removePeer(String peerId) async {
    final pc = _peers.remove(peerId);
    _prevEnergy.remove(peerId);
    final next = Set<String>.from(_connectedPeers.value)..remove(peerId);
    _connectedPeers.value = next;
    await pc?.close();
  }

  /// 사용자가 명시적으로 재연결 요청. 연결 안 된 모든 피어에게 ICE restart 시도.
  Future<void> retryConnections() async {
    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;
      if (_connectedPeers.value.contains(peerId)) continue;
      try {
        final offer = await pc.createOffer({'iceRestart': true});
        await pc.setLocalDescription(offer);
        signaling.sendSignal(peerId, 'offer', {
          'type': offer.type,
          'sdp': offer.sdp,
        });
      } catch (_) {}
    }
  }

  Future<void> closeAll() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    final tracks = _localStream?.getTracks() ?? const [];
    for (final t in tracks) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
  }

  Future<RTCPeerConnection> _ensurePeer(String peerId) async {
    final existing = _peers[peerId];
    if (existing != null) return existing;
    // TURN 자격증명 fetch가 진행 중이면 잠시 대기 (최대 ~5초).
    // 못 받아도 STUN-only로 진행 (callPeers 가 막히면 안 됨).
    if (_iceServers.isEmpty && _turnFetchInFlight != null) {
      try {
        await _turnFetchInFlight!.timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    final pc = await createPeerConnection(_config);
    pc.onIceCandidate = (candidate) {
      signaling.sendSignal(peerId, 'ice', {
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'candidate': candidate.candidate,
      });
    };
    pc.onIceConnectionState = (state) async {
      // UI에 보여줄 연결 상태 갱신.
      final connected = state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted;
      final next = Set<String>.from(_connectedPeers.value);
      if (connected) {
        next.add(peerId);
      } else {
        next.remove(peerId);
      }
      _connectedPeers.value = next;

      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        try {
          final offer = await pc.createOffer({'iceRestart': true});
          await pc.setLocalDescription(offer);
          signaling.sendSignal(peerId, 'offer', {
            'type': offer.type,
            'sdp': offer.sdp,
          });
        } catch (_) {
          // ignore
        }
      }
    };
    pc.onTrack = (event) {
      // iOS 에선 명시적으로 enable 안 해주면 수신 트랙이 묵음 상태일 수 있음.
      for (final t in event.streams.expand((s) => s.getAudioTracks())) {
        t.enabled = true;
      }
    };
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }
    _peers[peerId] = pc;
    return pc;
  }
}
