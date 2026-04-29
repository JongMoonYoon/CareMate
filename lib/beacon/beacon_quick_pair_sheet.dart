// lib/beacon/beacon_quick_pair_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../main.dart';

/// 사용 방법:
/// BeaconQuickPairSheet.showGlobal(context, onPaired: (id) { ... });
class BeaconQuickPairSheet extends StatefulWidget {
  final Function(String beaconId)? onPairedGlobal;

  const BeaconQuickPairSheet({
    super.key,
    this.onPairedGlobal,
  });

  /// ⭐ 전역 비콘 연결 (약통 하나)
  static Future<void> showGlobal(
      BuildContext context, {
        required Function(String beaconId) onPaired,
      }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BeaconQuickPairSheet(
        onPairedGlobal: onPaired,
      ),
    );
  }

  @override
  State<BeaconQuickPairSheet> createState() => _BeaconQuickPairSheetState();
}

class _BeaconQuickPairSheetState extends State<BeaconQuickPairSheet>
    with SingleTickerProviderStateMixin {

  // ── 상태 ──────────────────────────────────────────────────────────────────
  _PairStep _step = _PairStep.scanning;   // 현재 단계
  ScanResult? _candidate;                  // 감지된 후보 기기
  String _candidateName = '';
  int _candidateRssi = -999;

  // ── BLE ───────────────────────────────────────────────────────────────────
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _debounceTimer;                   // 신호 안정화 대기
  final Map<String, List<int>> _rssiHistory = {};

  // ── 애니메이션 (펄스 링) ──────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _debounceTimer?.cancel();
    _pulseCtrl.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // ── BLE 스캔 시작 ─────────────────────────────────────────────────────────

  void _startScan() {
    FlutterBluePlus.startScan(continuousUpdates: true);

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (_step != _PairStep.scanning) return;
      if (results.isEmpty) return;

      // RSSI 스무딩 후 가장 강한 기기 선택
      ScanResult? strongest;
      int maxSmoothed = -999;

      for (final r in results) {
        final id = r.device.remoteId.str;
        final history = _rssiHistory.putIfAbsent(id, () => []);
        history.add(r.rssi);
        if (history.length > 4) history.removeAt(0);
        final avg = history.reduce((a, b) => a + b) ~/ history.length;

        if (avg > maxSmoothed) {
          maxSmoothed = avg;
          strongest = r;
        }
      }

      // -55dBm 이상(충분히 가까움)일 때만 후보로 올림
      if (strongest != null && maxSmoothed >= -55) {
        _onCandidateFound(strongest, maxSmoothed);
      }
    });
  }

  // ── 후보 기기 감지됨 ──────────────────────────────────────────────────────

  void _onCandidateFound(ScanResult result, int smoothedRssi) {
    // 0.8초 동안 같은 기기가 계속 잡혀야 확정 (튐 방지)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final name = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : '비콘 (${result.device.remoteId.str.substring(0, 8)}...)';

      setState(() {
        _step = _PairStep.found;
        _candidate = result;
        _candidateName = name;
        _candidateRssi = smoothedRssi;
      });

      HapticFeedback.mediumImpact(); // 감지 진동
      FlutterBluePlus.stopScan();
    });
  }

  // ── 연결 확정 ─────────────────────────────────────────────────────────────

  Future<void> _confirmPair() async {
    if (_candidate == null) return;

    setState(() => _step = _PairStep.pairing);

    final beaconId = _candidate!.device.remoteId.str;

    await Future.delayed(const Duration(milliseconds: 600));

    setState(() => _step = _PairStep.done);
    HapticFeedback.heavyImpact();

    // 1.5초 후 자동 닫기
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      Navigator.pop(context);
      widget.onPairedGlobal?.call(beaconId); // ⭐ beaconId 전달
    }
  }

  // ── 다시 스캔 ─────────────────────────────────────────────────────────────

  void _retry() {
    setState(() {
      _step = _PairStep.scanning;
      _candidate = null;
      _rssiHistory.clear();
    });
    _startScan();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 손잡이
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // 약 이름 태그
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Text(
              '💊 약통 비콘 연결',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 단계별 본문
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStepContent(),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _PairStep.scanning:
        return _ScanningView(pulseAnim: _pulseAnim);

      case _PairStep.found:
        return _FoundView(
          deviceName: _candidateName,
          rssi: _candidateRssi,
          onConfirm: _confirmPair,
          onRetry: _retry,
        );

      case _PairStep.pairing:
        return const _PairingView();

      case _PairStep.done:
        return const _DoneView();
    }
  }
}

// ── 단계 열거형 ───────────────────────────────────────────────────────────────
enum _PairStep { scanning, found, pairing, done }

// ── 스캔 중 화면 ──────────────────────────────────────────────────────────────
class _ScanningView extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _ScanningView({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('scanning'),
      children: [
        const Text(
          '비콘을 가까이 대주세요',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '약통 비콘을 스마트폰에 가까이 가져오면\n자동으로 감지돼요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 36),

        // 펄스 애니메이션
        AnimatedBuilder(
          animation: pulseAnim,
          builder: (_, __) => Stack(
            alignment: Alignment.center,
            children: [
              // 바깥 링 3개
              for (int i = 0; i < 3; i++)
                Transform.scale(
                  scale: pulseAnim.value - i * 0.12,
                  child: Container(
                    width: 120 + i * 40.0,
                    height: 120 + i * 40.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.15 - i * 0.04),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              // 중앙 아이콘
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.bluetooth_searching,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue.shade400,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '스캔 중...',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

// ── 기기 감지됨 화면 ──────────────────────────────────────────────────────────
class _FoundView extends StatelessWidget {
  final String deviceName;
  final int rssi;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;

  const _FoundView({
    required this.deviceName,
    required this.rssi,
    required this.onConfirm,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('found'),
      children: [
        const Text(
          '비콘을 찾았어요! 🎉',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '이 기기를 약통 비콘으로 연결할까요?',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 28),

        // 감지된 기기 카드
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.blue.shade200, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 56, height: 56,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bluetooth_connected,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '신호 세기: $rssi dBm  (${_proximity(rssi)})',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // 신호 막대
              _SignalBars(rssi: rssi),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 연결 버튼
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              '연결하기',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 다시 스캔
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('다른 기기 찾기'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
        ),
      ],
    );
  }

  String _proximity(int rssi) {
    if (rssi >= -45) return '아주 가까움';
    if (rssi >= -55) return '가까움';
    return '보통';
  }
}

// ── 연결 중 화면 ──────────────────────────────────────────────────────────────
class _PairingView extends StatelessWidget {
  const _PairingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('pairing'),
      children: [
        const SizedBox(height: 20),
        const CircularProgressIndicator(color: Colors.blue),
        const SizedBox(height: 20),
        const Text(
          '연결 중...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 60),
      ],
    );
  }
}

// ── 완료 화면 ─────────────────────────────────────────────────────────────────
class _DoneView extends StatelessWidget {
  const _DoneView();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('done'),
      children: [
        const SizedBox(height: 10),
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green, width: 2),
          ),
          child: const Icon(Icons.check_rounded, color: Colors.green, size: 48),
        ),
        const SizedBox(height: 16),
        const Text(
          '연결 완료!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '이제 약통에 가까이 대면 자동으로\n복용이 기록돼요 🌱',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── 신호 막대 ─────────────────────────────────────────────────────────────────
class _SignalBars extends StatelessWidget {
  final int rssi;
  const _SignalBars({required this.rssi});

  int get _bars {
    if (rssi >= -45) return 4;
    if (rssi >= -55) return 3;
    if (rssi >= -65) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        return Container(
          margin: const EdgeInsets.only(left: 3),
          width: 5,
          height: 8.0 + i * 5,
          decoration: BoxDecoration(
            color: i < _bars ? Colors.blue : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}