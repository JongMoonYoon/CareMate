// lib/beacon/beacon_pairing_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../main.dart';

class BeaconPairingScreen extends StatefulWidget {
  const BeaconPairingScreen({super.key});

  @override
  State<BeaconPairingScreen> createState() => _BeaconPairingScreenState();
}

class _BeaconPairingScreenState extends State<BeaconPairingScreen> {
  StreamSubscription<List<ScanResult>>? _scanSub;
  final Map<String, ScanResult> _found = {};
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _found.clear();
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        for (final r in results) {
          _found[r.device.remoteId.str] = r;
        }
      });
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isScanning = false);
      FlutterBluePlus.stopScan();
    });
  }

  List<ScanResult> get _sortedResults {
    final list = _found.values.toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  // ⭐ 비콘 탭 → 전역 pairedBeaconId에 저장
  Future<void> _onBeaconTapped(ScanResult result) async {
    final beaconId = result.device.remoteId.str;
    final deviceName = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : beaconId;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('비콘 연결'),
        content: Text('"$deviceName"\n을(를) 약통 비콘으로 연결할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('연결'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // ⭐ 전역 비콘 ID 저장
    GlobalMedicineList.pairedBeaconId = beaconId;
    await GlobalMedicineList.save();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 약통 비콘이 연결됐어요!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _sortedResults;

    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text('비콘 연결하기'),
        backgroundColor: Colors.green,
        actions: [
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '다시 스캔',
              onPressed: _startScan,
            ),
        ],
      ),
      body: Column(
        children: [
          // 현재 연결 상태 배너
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GlobalMedicineList.pairedBeaconId.isNotEmpty
                  ? Colors.green.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: GlobalMedicineList.pairedBeaconId.isNotEmpty
                    ? Colors.green.shade200
                    : Colors.blue.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GlobalMedicineList.pairedBeaconId.isNotEmpty
                      ? '✅ 현재 연결된 비콘'
                      : '💡 연결 방법',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  GlobalMedicineList.pairedBeaconId.isNotEmpty
                      ? GlobalMedicineList.pairedBeaconId
                      : '비콘을 가까이 가져오면 목록에 나타나요.\n탭하면 약통 비콘으로 연결됩니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: GlobalMedicineList.pairedBeaconId.isNotEmpty
                        ? Colors.green.shade700
                        : Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),

          if (_isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.green),
                  ),
                  const SizedBox(width: 10),
                  Text('주변 비콘 스캔 중...',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),

          Expanded(
            child: results.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_disabled,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    _isScanning ? '기기를 찾고 있어요...' : '주변에 비콘이 없어요',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: results.length,
              itemBuilder: (context, i) {
                final r = results[i];
                final isPaired = GlobalMedicineList.pairedBeaconId ==
                    r.device.remoteId.str;
                return _BeaconTile(
                  result: r,
                  isRecommended: i == 0,
                  isPaired: isPaired,
                  onTap: () => _onBeaconTapped(r),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── 비콘 리스트 타일 ─────────────────────────────────────────────────────────
class _BeaconTile extends StatelessWidget {
  final ScanResult result;
  final bool isRecommended;
  final bool isPaired;
  final VoidCallback onTap;

  const _BeaconTile({
    required this.result,
    required this.isRecommended,
    required this.isPaired,
    required this.onTap,
  });

  Color _rssiColor(int rssi) {
    if (rssi >= -45) return Colors.green;
    if (rssi >= -65) return Colors.orange;
    return Colors.red;
  }

  String _rssiLabel(int rssi) {
    if (rssi >= -45) return '아주 가까움';
    if (rssi >= -65) return '보통';
    return '멀리 있음';
  }

  int _rssiToBars(int rssi) {
    if (rssi >= -45) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -75) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final rssi = result.rssi;
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.device.remoteId.str;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isPaired ? Colors.green.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPaired
                ? Colors.green.shade400
                : isRecommended
                ? Colors.blue.shade300
                : Colors.grey.shade200,
            width: isPaired || isRecommended ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _rssiColor(rssi).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPaired ? Icons.bluetooth_connected : Icons.bluetooth,
                color: isPaired ? Colors.green : _rssiColor(rssi),
                size: 26,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      const SizedBox(width: 6),
                      if (isPaired)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('연결됨',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        )
                      else if (isRecommended)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('추천',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.device.remoteId.str,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SignalBars(
                    bars: _rssiToBars(rssi), color: _rssiColor(rssi)),
                const SizedBox(height: 4),
                Text('$rssi dBm',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                Text(_rssiLabel(rssi),
                    style: TextStyle(
                        fontSize: 11, color: _rssiColor(rssi))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 신호 막대 ─────────────────────────────────────────────────────────────────
class _SignalBars extends StatelessWidget {
  final int bars;
  final Color color;
  const _SignalBars({required this.bars, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        return Container(
          margin: const EdgeInsets.only(left: 2),
          width: 5,
          height: 6.0 + i * 4,
          decoration: BoxDecoration(
            color: i < bars ? color : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}