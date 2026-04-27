import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'rtc.dart';
import 'signaling.dart';

const _signalingUrl = 'https://wktk-signaling.onrender.com';

const _bg = Color(0xFFF6F7F9);
const _surface = Colors.white;
const _ink = Color(0xFF1B2330);
const _muted = Color(0xFF8A92A6);
const _accent = Color(0xFF1F5F70);
const _hot = Color(0xFFE94E3D);

void main() {
  runApp(const OkidokiApp());
}

class OkidokiApp extends StatelessWidget {
  const OkidokiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오키도키',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          surface: _surface,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(color: _ink, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: _ink),
          labelLarge: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum TalkMode { ptt, vox }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SignalingService? _signaling;
  RtcService? _rtc;
  StreamSubscription? _sub;
  final _keyController = TextEditingController();

  bool _connected = false;
  String? _joinedKey;
  List<String> _peers = const [];
  TalkMode _mode = TalkMode.ptt;
  bool _transmitting = false;
  String? _error;
  // 15초 후 ICE 연결 안 됐으면 재연결 버튼 표시.
  Timer? _retryTimer;
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _error = '마이크 권한이 필요합니다');
      return;
    }
    final signaling = SignalingService(_signalingUrl);
    final rtc = RtcService(signaling, signalingUrl: _signalingUrl);
    await rtc.start();
    _sub = signaling.events.listen(_onEvent);
    signaling.connect();
    if (!mounted) return;
    setState(() {
      _signaling = signaling;
      _rtc = rtc;
    });
  }

  void _onEvent(SignalingEvent e) {
    if (!mounted) return;
    switch (e) {
      case Connected():
        setState(() => _connected = true);
      case Disconnected():
        setState(() => _connected = false);
      case KeyAssigned():
        setState(() => _keyController.text = e.key);
      case KeyJoined():
        setState(() {
          _joinedKey = e.key;
          _peers = e.peers;
          _error = null;
          _showRetry = false;
        });
        if (e.peers.isNotEmpty) _rtc?.callPeers(e.peers);
        _scheduleRetryCheck();
      case PeerJoined():
        setState(() => _peers = [..._peers, e.peerId]);
      case PeerLeft():
        _rtc?.removePeer(e.peerId);
        setState(() => _peers = _peers.where((p) => p != e.peerId).toList());
      case Signal():
        _rtc?.onSignal(e.from, e.type, e.payload);
      case SignalingErrorEvent():
        setState(() => _error = '${e.code}: ${e.message}');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retryTimer?.cancel();
    _rtc?.closeAll();
    _signaling?.disconnect();
    _keyController.dispose();
    super.dispose();
  }

  void _join() {
    final k = _keyController.text;
    if (RegExp(r'^\d{6}$').hasMatch(k)) {
      setState(() => _error = null);
      _signaling?.joinKey(k);
    } else {
      setState(() => _error = '6자리 숫자를 입력하세요');
    }
  }

  void _leave() {
    _signaling?.leaveKey();
    _retryTimer?.cancel();
    _retryTimer = null;
    setState(() {
      _joinedKey = null;
      _peers = const [];
      _keyController.clear();
      _showRetry = false;
    });
  }

  void _scheduleRetryCheck() {
    _retryTimer?.cancel();
    // 15초 후 ICE 연결 안 된 피어 있으면 재시도 버튼 노출.
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      final connected = _rtc?.connectedPeers.value ?? const <String>{};
      if (_peers.any((p) => !connected.contains(p))) {
        setState(() => _showRetry = true);
      }
    });
  }

  Future<void> _retryConnection() async {
    setState(() => _showRetry = false);
    await _rtc?.retryConnections();
    _scheduleRetryCheck();
  }

  void _setMode(TalkMode m) {
    if (_mode == m) return;
    setState(() {
      _mode = m;
      // 모드 전환 시 송신 상태도 초기화: VOX 는 항상 송신, PTT 는 OFF로 시작.
      _transmitting = m == TalkMode.vox;
    });
    _rtc?.setMicEnabled(m == TalkMode.vox);
  }

  void _pttDown() {
    if (_mode != TalkMode.ptt) return;
    _rtc?.setMicEnabled(true);
    setState(() => _transmitting = true);
  }

  void _pttUp() {
    if (_mode != TalkMode.ptt) return;
    _rtc?.setMicEnabled(false);
    setState(() => _transmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(connected: _connected),
              const SizedBox(height: 24),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _joinedKey == null
                      ? _Lobby(
                          key: const ValueKey('lobby'),
                          controller: _keyController,
                          onRequestKey: () => _signaling?.requestKey(),
                          onJoin: _join,
                          error: _error,
                        )
                      : _Room(
                          key: const ValueKey('room'),
                          joinedKey: _joinedKey!,
                          peers: _peers,
                          connectedPeers: _rtc?.connectedPeers,
                          mode: _mode,
                          transmitting: _transmitting,
                          peerAudioLevel: _rtc?.peerAudioLevel,
                          showRetry: _showRetry,
                          onSetMode: _setMode,
                          onPttDown: _pttDown,
                          onPttUp: _pttUp,
                          onLeave: _leave,
                          onRetry: _retryConnection,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool connected;
  const _Header({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          '오키도키',
          style: TextStyle(
            color: _ink,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: connected ? const Color(0xFFE6F4EA) : const Color(0xFFF1F2F4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: connected ? const Color(0xFF34A853) : _muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                connected ? '연결됨' : '연결 중',
                style: TextStyle(
                  color: connected ? const Color(0xFF1E7E34) : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Lobby extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onRequestKey;
  final VoidCallback onJoin;
  final String? error;

  const _Lobby({
    super.key,
    required this.controller,
    required this.onRequestKey,
    required this.onJoin,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Text(
          '6자리 키로\n친구와 연결하세요',
          style: TextStyle(
            color: _ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              TextField(
                controller: controller,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  letterSpacing: 12,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
                maxLength: 6,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(
                    color: Color(0xFFD0D5DD),
                    letterSpacing: 12,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onRequestKey,
                      style: TextButton.styleFrom(
                        foregroundColor: _accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E5EA)),
                        ),
                      ),
                      child: const Text(
                        '새 키 받기',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onJoin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '입장',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _hot, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _Room extends StatelessWidget {
  final String joinedKey;
  final List<String> peers;
  final ValueListenable<Set<String>>? connectedPeers;
  final TalkMode mode;
  final bool transmitting;
  final ValueListenable<double>? peerAudioLevel;
  final bool showRetry;
  final ValueChanged<TalkMode> onSetMode;
  final VoidCallback onPttDown;
  final VoidCallback onPttUp;
  final VoidCallback onLeave;
  final VoidCallback onRetry;

  const _Room({
    super.key,
    required this.joinedKey,
    required this.peers,
    required this.connectedPeers,
    required this.mode,
    required this.transmitting,
    required this.peerAudioLevel,
    required this.showRetry,
    required this.onSetMode,
    required this.onPttDown,
    required this.onPttUp,
    required this.onLeave,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final connectedListen = connectedPeers ?? ValueNotifier<Set<String>>(<String>{});
    return ValueListenableBuilder<Set<String>>(
      valueListenable: connectedListen,
      builder: (context, connected, _) {
        final connectedCount = peers.where(connected.contains).length;
        final pendingCount = peers.length - connectedCount;
        final hasPeer = peers.isNotEmpty;
        final allReady = hasPeer && pendingCount == 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text('주파수', style: TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    joinedKey,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 36,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _peerStatusLine(
                    total: peers.length,
                    connected: connectedCount,
                    pending: pendingCount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 70,
                    child: _Waveform(
                      active: allReady,
                      transmitting: transmitting,
                      peerAudioLevel: peerAudioLevel,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (showRetry && pendingCount > 0)
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('재연결'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _hot,
                        side: const BorderSide(color: _hot),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                  const SizedBox(height: 16),
                  _TalkButton(
                    mode: mode,
                    transmitting: transmitting,
                    enabled: allReady,
                    onDown: onPttDown,
                    onUp: onPttUp,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _modeChip(
                  label: 'PTT',
                  selected: mode == TalkMode.ptt,
                  onTap: () => onSetMode(TalkMode.ptt),
                ),
                const SizedBox(width: 8),
                _modeChip(
                  label: '항상 켜기',
                  selected: mode == TalkMode.vox,
                  onTap: () => onSetMode(TalkMode.vox),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onLeave,
                  style: TextButton.styleFrom(foregroundColor: _muted),
                  child: const Text('나가기', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _peerStatusLine({required int total, required int connected, required int pending}) {
    if (total == 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.people_outline, size: 14, color: _muted),
          SizedBox(width: 4),
          Text('상대방을 기다리는 중...', style: TextStyle(color: _muted, fontSize: 12)),
        ],
      );
    }
    if (pending > 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: _accent),
          ),
          const SizedBox(width: 6),
          Text(
            '연결 중... ($connected/$total)',
            style: const TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.people_outline, size: 14, color: Color(0xFF1E7E34)),
        const SizedBox(width: 4),
        Text(
          '연결됨 · $connected명',
          style: const TextStyle(color: Color(0xFF1E7E34), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _modeChip({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accent : _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _accent : const Color(0xFFE2E5EA)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TalkButton extends StatelessWidget {
  final TalkMode mode;
  final bool transmitting;
  final bool enabled;
  final VoidCallback onDown;
  final VoidCallback onUp;

  const _TalkButton({
    required this.mode,
    required this.transmitting,
    required this.enabled,
    required this.onDown,
    required this.onUp,
  });

  @override
  Widget build(BuildContext context) {
    final isVox = mode == TalkMode.vox;
    final hot = enabled && (transmitting || isVox);
    final label = !enabled
        ? '연결 대기'
        : isVox
            ? '항상 켜짐'
            : (transmitting ? 'TALKING' : 'PUSH TO TALK');
    final colors = !enabled
        ? const [Color(0xFFB0B5BC), Color(0xFF8A92A6)]
        : hot
            ? const [Color(0xFFFF6B5C), Color(0xFFE94E3D)]
            : const [Color(0xFF2A6B7C), Color(0xFF1F5F70)];
    return GestureDetector(
      onTapDown: (!enabled || isVox) ? null : (_) => onDown(),
      onTapUp: (!enabled || isVox) ? null : (_) => onUp(),
      onTapCancel: (!enabled || isVox) ? null : onUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: (hot ? _hot : _accent).withValues(alpha: 0.32),
                    blurRadius: hot ? 30 : 18,
                    spreadRadius: hot ? 4 : 0,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              !enabled ? Icons.mic_off : (hot ? Icons.mic : Icons.mic_none),
              color: Colors.white,
              size: 38,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 음성 파동 바 애니메이션.
/// - `active=false`: 거의 정지 (얇은 점선)
/// - `transmitting=true`: 빨간 강한 진폭
/// - 그 외: 파란색, 피어 audioLevel 따라 진폭
class _Waveform extends StatefulWidget {
  final bool active;
  final bool transmitting;
  final ValueListenable<double>? peerAudioLevel;
  const _Waveform({
    required this.active,
    required this.transmitting,
    required this.peerAudioLevel,
  });

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final levelListen = widget.peerAudioLevel ?? ValueNotifier<double>(0);
    return ValueListenableBuilder<double>(
      valueListenable: levelListen,
      builder: (context, level, _) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomPaint(
              size: const Size.fromHeight(70),
              painter: _WavePainter(
                phase: _ctrl.value,
                active: widget.active,
                transmitting: widget.transmitting,
                peerLevel: level,
              ),
            );
          },
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase;
  final bool active;
  final bool transmitting;
  final double peerLevel;
  _WavePainter({
    required this.phase,
    required this.active,
    required this.transmitting,
    required this.peerLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 21;
    final barWidth = size.width / (barCount * 1.6);
    final gap = barWidth * 0.6;
    final totalWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = (size.width - totalWidth) / 2;
    final cy = size.height / 2;

    // 진폭 결정. 살아있다는 신호로 항상 어느 정도 움직임 유지.
    double amp;
    Color color;
    if (transmitting) {
      amp = size.height * 0.45;
      color = _hot;
    } else if (active) {
      // peer가 말하면 큰 진폭, 조용해도 idle 펄스 유지.
      amp = size.height * (0.18 + peerLevel.clamp(0.0, 1.0) * 0.32);
      color = _accent;
    } else {
      // 룸 밖에서도 살아있다는 표시로 부드러운 펄스.
      amp = size.height * 0.10;
      color = _muted;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      // 사인파 + 위치 오프셋 + 가운데가 더 크게 보이는 가중치.
      final t = phase * 2 * math.pi + i * 0.45;
      final centerWeight = 1.0 - (((i - barCount / 2).abs()) / (barCount / 2)) * 0.5;
      final s = (math.sin(t) * 0.5 + 0.5) * amp * centerWeight;
      final h = math.max(s * 2, 4.0);
      final x = startX + i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, cy - h / 2, barWidth, h),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
