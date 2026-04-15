// ══════════════════════════════════════════════════════════════════════════════
// main.dart 수정 가이드
// 아래 내용을 기존 main.dart에 적용하세요
// ══════════════════════════════════════════════════════════════════════════════

// ── 1. import 추가 (main.dart 상단) ─────────────────────────────────────────
import 'beacon/beacon_service.dart';
import 'beacon/beacon_pairing_screen.dart';
import 'beacon/beacon_overlay_widget.dart';


// ── 2. main() 수정: 비콘 서비스 초기화 ────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  // ⭐ 아무 추가 init 없음 - BeaconService는 HomeScreen에서 시작
  runApp(/* 기존 코드 유지 */);
}


// ── 3. _HomeScreenState 수정 ──────────────────────────────────────────────────
class _HomeScreenState extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();
    _loadMedicines();
    _cleanupOldRecords();
    // ⭐ 비콘 서비스 시작 (약 로드 후)
    _startBeaconService();
  }

  // ⭐ 추가: 비콘 서비스 시작
  Future<void> _startBeaconService() async {
    // 약 로드가 먼저 완료돼야 하므로 약간 딜레이
    await Future.delayed(const Duration(milliseconds: 500));

    final watchedIds = GlobalMedicineList.medicines
        .where((m) => m.beaconId.isNotEmpty)
        .map((m) => m.beaconId)
        .toSet();

    await BeaconService.instance.start(
      watchedIds: watchedIds,
      onTaken: _onBeaconMedicineTaken, // ⭐ 복용 확정 콜백
    );
  }

  // ⭐ 추가: 비콘으로 복용 확정됐을 때
  Future<void> _onBeaconMedicineTaken(String beaconId) async {
    // beaconId로 약 찾기
    final medicine = GlobalMedicineList.medicines
        .where((m) => m.beaconId == beaconId)
        .firstOrNull;

    if (medicine == null) return;

    // 복약 기록 추가
    final now = DateTime.now();
    GlobalMedicineList.history.add('${medicine.name}|${now.toIso8601String()}');

    // 통계 업데이트
    GlobalMedicineList.todayMedicine++;
    GlobalMedicineList.totalMedicine++;

    // 레벨업 체크
    if (GlobalMedicineList.totalMedicine % 10 == 0) {
      GlobalMedicineList.plantLevel++;
    }

    await GlobalMedicineList.save();

    if (mounted) {
      setState(() {}); // UI 갱신
      print('✅ 비콘 복용 기록: ${medicine.name}');
    }
  }

  @override
  void dispose() {
    BeaconService.instance.stop(); // ⭐ 서비스 중지
    super.dispose();
  }


  // ── build() 안에서 BeaconOverlayWidget 추가 ─────────────────────────────────
  // 기존 build()의 Column children 안, 약 등록 버튼 위에 삽입:

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ... 기존 코드 ...
      body: SingleChildScrollView(
        child: Column(
          children: [

            // ⭐ 비콘 상태 위젯 (여기에 삽입)
            const BeaconOverlayWidget(),

            // ... 기존 화분 카드, 약 목록, 버튼 등 유지 ...

            // ⭐ 비콘 연결 버튼 추가 (약 등록 버튼 아래)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BeaconPairingScreen(),
                    ),
                  );
                  // 페이지 복귀 시 비콘 서비스 재시작 (새 beaconId 반영)
                  BeaconService.instance.stop();
                  _startBeaconService();
                  setState(() {});
                },
                icon: const Icon(Icons.bluetooth, size: 22),
                label: const Text('약통 비콘 연결하기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
// pubspec.yaml 추가 패키지
// ══════════════════════════════════════════════════════════════════════════════
/*
dependencies:
  flutter_blue_plus: ^1.31.0   # BLE 스캔

android/app/src/main/AndroidManifest.xml 에 추가:
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
      android:usesPermissionFlags="neverForLocation" />
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  <uses-permission android:name="android.permission.BLUETOOTH" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

ios/Runner/Info.plist 에 추가:
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>약통 비콘 감지를 위해 블루투스 접근이 필요합니다</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>약통 비콘 감지를 위해 블루투스 접근이 필요합니다</string>
*/