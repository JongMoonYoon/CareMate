// lib/screens/beacon_pairing_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../main.dart'; // Medicine, GlobalMedicineList

/// 비콘을 약에 페어링하는 화면
/// - BLE 스캔해서 주변 기기 표시
/// - 가장 강한 신호(RSSI 높은 것)를 자동 추천
/// - 사용자가 약을 선택해서 연결
class BeaconPairingScreen extends StatefulWidget {
  const BeaconPairingScreen({super.key});

  @override
  State<BeaconPairingScreen> createState() => _BeaconPairingScreenState();
}

class _BeaconPairingScreenState extends State<BeaconPairingScreen> {
  StreamSubscription<List<ScanResult>>? _scanSub;
  final Map<String, ScanResult> _found = {}; // deviceId → ScanResult
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

    // 5초 후 자동 중지
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isScanning = false);
      FlutterBluePlus.stopScan();
    });
  }

  // RSSI 기준 정렬
  List<ScanResult> get _sortedResults {
    final list = _found.values.toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi)); // RSSI 강한 순
    return list;
  }

  void _showPairingDialog(ScanResult result) {
    final medicines = GlobalMedicineList.medicines;
    if (medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 약을 등록해주세요!')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PairingBottomSheet(
        scanResult: result,
        medicines: medicines,
        onPaired: (medicine) async {
          // ⭐ beaconId 업데이트 후 저장
          final idx = GlobalMedicineList.medicines.indexOf(medicine);
          if (idx >= 0) {
            GlobalMedicineList.medicines[idx] = Medicine(
              name: medicine.name,
              alarmTime: medicine.alarmTime,
              selectedDays: medicine.selectedDays,
              beaconId: result.device.remoteId.str,
              isTaken: medicine.isTaken,
            );
            await GlobalMedicineList.save();
          }

          if (mounted) {
            Navigator.pop(context); // 바텀시트
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '✅ ${medicine.name}에 비콘이 연결됐어요!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
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
          // 안내 배너
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💡 연결 방법',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  '① 약통에 비콘을 부착하세요.\n'
                      '② 비콘 가까이 가면 목록에 나타나요.\n'
                      '③ 기기를 탭해서 약과 연결하세요.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.blue.shade700),
                ),
              ],
            ),
          ),

          // 스캔 상태
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

          // 기기 목록
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
                    _isScanning
                        ? '기기를 찾고 있어요...'
                        : '주변에 비콘이 없어요',
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
                return _BeaconTile(
                  result: r,
                  isRecommended: i == 0, // RSSI 1위 추천
                  onTap: () => _showPairingDialog(r),
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
  final VoidCallback onTap;

  const _BeaconTile({
    required this.result,
    required this.isRecommended,
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

    // 이미 페어링된 약 있는지 확인
    final pairedMed = GlobalMedicineList.medicines
        .where((m) => m.beaconId == result.device.remoteId.str)
        .firstOrNull;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRecommended ? Colors.green.shade300 : Colors.grey.shade200,
            width: isRecommended ? 1.5 : 1,
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
            // 블루투스 아이콘
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _rssiColor(rssi).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bluetooth,
                  color: _rssiColor(rssi), size: 26),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      if (isRecommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('추천',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.device.remoteId.str,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade400),
                  ),
                  if (pairedMed != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '💊 ${pairedMed.name}에 연결됨',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.green),
                    ),
                  ],
                ],
              ),
            ),

            // RSSI 신호 세기
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SignalBars(bars: _rssiToBars(rssi), color: _rssiColor(rssi)),
                const SizedBox(height: 4),
                Text(
                  '$rssi dBm',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
                Text(
                  _rssiLabel(rssi),
                  style: TextStyle(
                      fontSize: 11, color: _rssiColor(rssi)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 신호 막대 위젯 ────────────────────────────────────────────────────────────
class _SignalBars extends StatelessWidget {
  final int bars; // 1~4
  final Color color;
  const _SignalBars({required this.bars, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          margin: const EdgeInsets.only(left: 2),
          width: 5,
          height: 6.0 + i * 4,
          decoration: BoxDecoration(
            color: active ? color : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ── 페어링 바텀시트 ──────────────────────────────────────────────────────────
class _PairingBottomSheet extends StatelessWidget {
  final ScanResult scanResult;
  final List<Medicine> medicines;
  final Function(Medicine) onPaired;

  const _PairingBottomSheet({
    required this.scanResult,
    required this.medicines,
    required this.onPaired,
  });

  @override
  Widget build(BuildContext context) {
    final deviceName = scanResult.device.platformName.isNotEmpty
        ? scanResult.device.platformName
        : scanResult.device.remoteId.str;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '📲 "$deviceName" 을(를)\n어떤 약에 연결할까요?',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...medicines.map((med) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.medication, color: Colors.green),
            ),
            title: Text(med.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${med.alarmTime.hour.toString().padLeft(2, '0')}:${med.alarmTime.minute.toString().padLeft(2, '0')}  '
                  '${med.beaconId.isNotEmpty ? "· 비콘 연결됨" : "· 비콘 없음"}',
              style: TextStyle(
                fontSize: 12,
                color: med.beaconId.isNotEmpty
                    ? Colors.green
                    : Colors.grey,
              ),
            ),
            trailing: const Icon(Icons.chevron_right,
                color: Colors.green),
            onTap: () {
              Navigator.pop(context);
              onPaired(med);
            },
          )),
        ],
      ),
    );
  }
}