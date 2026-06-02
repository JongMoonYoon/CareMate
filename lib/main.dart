import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'screens/add_medicine_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'service/notification_service.dart';
import 'beacon/beacon_service.dart';
import 'beacon/beacon_overlay_widget.dart';
import 'beacon/beacon_quick_pair_sheet.dart';
import 'beacon/background_beacon_service.dart'; // ✅ 팀원 추가

const String serverUrl = 'http://15.164.230.65:8000';

const String userId = 'user_001';

// ── 색상 테마 ─────────────────────────────────────────────────────────────────
class AppColors {
  static const deepGreen   = Color(0xFF1C4232);
  static const midGreen    = Color(0xFF2D6A4F);
  static const lightGreen  = Color(0xFFE8F5EE);
  static const accentGreen = Color(0xFF7EC8A0);
  static const beige       = Color(0xFFF8F4EE);
  static const beigeText   = Color(0xFFE8E0D0);
  static const cardWhite   = Color(0xFFFFFFFF);
  static const border      = Color(0xFFDDD8CF);
  static const textDark    = Color(0xFF1C3A2A);
  static const textMuted   = Color(0xFF7A8F84);
  static const warnBg      = Color(0xFFFFF8EC);
  static const warnBorder  = Color(0xFFE8A020);
  static const warnText    = Color(0xFF7A5010);
  static const depletedBg  = Color(0xFFFFEEEE);
  static const btnRed      = Color(0xFF8B1A1A);  // 어두운 빨강
  static const btnBlue     = Color(0xFF1A3A6B);  // 어두운 파랑
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundBeaconService.initialize(); // ✅ 팀원 추가
  await NotificationService.initialize();
  await _requestBluetoothPermissions();
  runApp(MaterialApp(
    home: const PlantCareApp(),
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: AppColors.beige,
      colorScheme: const ColorScheme.light(primary: AppColors.deepGreen),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepGreen,
        titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.beigeText),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.deepGreen,
          foregroundColor: AppColors.beigeText,
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
  ));
}

Future<void> _requestBluetoothPermissions() async {
  await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
}

class GlobalMedicineList {
  static List<Medicine> medicines = [];
  static List<String> history = [];
  static int plantLevel = 1;
  static int todayMedicine = 0;
  static int totalMedicine = 0;
  static String pairedBeaconId = '';
  static List<String> lastScannedMedicines = [];
  static String lastScannedSetName = '';

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = medicines.map((m) => {
      'name': m.name, 'hour': m.alarmTime.hour, 'minute': m.alarmTime.minute,
      'isTaken': m.isTaken, 'selectedDays': m.selectedDays,
      'supplyDays': m.supplyDays, 'dailyCount': m.dailyCount, 'takenCount': m.takenCount,
    }).toList();
    await prefs.setString('medicines', jsonEncode(jsonList));
    await prefs.setStringList('medicine_history', history);
    await prefs.setInt('plantLevel', plantLevel);
    await prefs.setInt('todayMedicine', todayMedicine);
    await prefs.setInt('totalMedicine', totalMedicine);
    await prefs.setString('pairedBeaconId', pairedBeaconId);
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('medicines');
    if (jsonStr != null) {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      medicines = jsonList.map((json) => Medicine(
        name: json['name'],
        alarmTime: TimeOfDay(hour: json['hour'], minute: json['minute']),
        selectedDays: json['selectedDays'] != null ? List<int>.from(json['selectedDays']) : [0,1,2,3,4,5,6],
        isTaken: json['isTaken'] ?? false,
        supplyDays: json['supplyDays'],
        dailyCount: json['dailyCount'] ?? 3,
        takenCount: json['takenCount'] ?? 0,
      )).toList();
    }
    history = prefs.getStringList('medicine_history') ?? [];
    plantLevel = prefs.getInt('plantLevel') ?? 1;
    todayMedicine = prefs.getInt('todayMedicine') ?? 0;
    totalMedicine = prefs.getInt('totalMedicine') ?? 0;
    pairedBeaconId = prefs.getString('pairedBeaconId') ?? '';
  }
}

class Medicine {
  final String name;
  final TimeOfDay alarmTime;
  final List<int> selectedDays;
  bool isTaken;
  final int? supplyDays;
  final int dailyCount;
  int takenCount;

  Medicine({required this.name, required this.alarmTime,
    this.selectedDays = const [0,1,2,3,4,5,6],
    this.isTaken = false, this.supplyDays, this.dailyCount = 3, this.takenCount = 0});

  int? get totalDoses => supplyDays != null ? supplyDays! * dailyCount : null;
  int? get remainingDoses => totalDoses != null ? (totalDoses! - takenCount).clamp(0, totalDoses!) : null;
  double? get remainingDays => remainingDoses != null ? remainingDoses! / dailyCount : null;
  bool get isDepleted => totalDoses != null && takenCount >= totalDoses!;
  bool get isLowSupply => remainingDays != null && remainingDays! <= 2 && !isDepleted;
}

class PlantCareApp extends StatefulWidget {
  const PlantCareApp({super.key});
  @override
  State<PlantCareApp> createState() => _PlantCareAppState();
}

class _PlantCareAppState extends State<PlantCareApp> {
  int _currentIndex = 0;
  final List<Widget> _screens = [const HomeScreen(), const ChatScreen(), const HistoryScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: AppColors.cardWhite,
        selectedItemColor: AppColors.deepGreen,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 15),
        elevation: 8,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.eco, size: 32), label: '내 식물'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline, size: 32), label: '복약 도우미'),
          BottomNavigationBarItem(icon: Icon(Icons.history, size: 32), label: '복약 기록'),
        ],
      ),
    );
  }
}

// ── 홈 화면 ───────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// ✅ 팀원 추가: WidgetsBindingObserver로 포그라운드/백그라운드 감지
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {

  // ✅ 팀원 추가: 백그라운드 비콘 감지 시 팝업
  void _showMedicinePopup(String beaconId) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.beige,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(children: [
          Text('복약 확인',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        ]),
        content: const Text(
          '약통 근처에 계신 것이 감지되었습니다.\n지금 약을 복용하셨나요?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: AppColors.textDark),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('아니요', style: TextStyle(color: AppColors.textMuted, fontSize: 18)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _onBeaconMedicineTaken(beaconId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('네, 먹었어요!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.beigeText)),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cleanupOldRecords();

    // 약 로드 완료 후 비콘 서비스 시작 (순차 실행 → 충돌 방지)
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    //final prefs = await SharedPreferences.getInstance();
    //await prefs.remove('pairedBeaconId');
    //GlobalMedicineList.pairedBeaconId = '';


    await GlobalMedicineList.load();
    if (mounted) setState(() {});
    _startBeaconService();
  }

  // 포그라운드/백그라운드 전환 시 비콘 서비스 전환
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final watchedIds = _buildWatchedIds();
    if (state == AppLifecycleState.paused) {
      BeaconService.instance.stop();
      if (watchedIds.isNotEmpty) {
        BackgroundBeaconService.instance.start(
          watchedIds: watchedIds,
          onTaken: (beaconId) {
            if (mounted) _showMedicinePopup(beaconId);
          },
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      BackgroundBeaconService.instance.stop();
      if (watchedIds.isNotEmpty) {
        BeaconService.instance.start(
          watchedIds: watchedIds,
          onTaken: _onBeaconMedicineTaken,
        );
      }
    }
  }

  /// 등록된 비콘 ID 목록 반환.
  /// SharedPreferences에 저장된 pairedBeaconId를 사용하며,
  /// 비어 있으면 빈 Set을 반환해 서비스 시작을 막는다.
  Set<String> _buildWatchedIds() {
    final id = GlobalMedicineList.pairedBeaconId.trim();
    return id.isNotEmpty ? {id} : {};
  }

  Future<void> _startBeaconService() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final watchedIds = _buildWatchedIds();
    if (watchedIds.isEmpty) {
      print('⚠️ pairedBeaconId가 없어 비콘 서비스를 시작하지 않습니다.');
      return;
    }
    await BeaconService.instance.start(
      watchedIds: watchedIds,
      onTaken: _onBeaconMedicineTaken,
    );
  }

  Medicine? _findNearestMedicine() {
    final available = GlobalMedicineList.medicines.where((m) => !m.isDepleted).toList();
    if (available.isEmpty) return null;
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    Medicine? nearest; int minDiff = 999999;
    for (final med in available) {
      final medMin = med.alarmTime.hour * 60 + med.alarmTime.minute;
      int diff = (medMin - nowMin).abs();
      if (diff > 720) diff = 1440 - diff;
      if (diff < minDiff) { minDiff = diff; nearest = med; }
    }
    return nearest;
  }

  Future<void> _onBeaconMedicineTaken(String beaconId) async {
    final medicine = _findNearestMedicine();
    if (medicine == null || !mounted) return;
    if (medicine.isDepleted) { _showDepletedDialog(medicine); return; }
    final confirmed = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.beige,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Text(medicine.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text('약을 드셨나요?', style: TextStyle(fontSize: 20, color: AppColors.textMuted)),
          if (medicine.remainingDoses != null)
            Padding(padding: const EdgeInsets.only(top: 10),
                child: Text('남은 복용: ${medicine.remainingDoses}회',
                    style: TextStyle(fontSize: 18,
                        color: medicine.isLowSupply ? AppColors.warnBorder : AppColors.textMuted))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('아니요', style: TextStyle(fontSize: 20, color: AppColors.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('네, 먹었어요!', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _recordMedicineTaken(medicine.name);
  }

  Future<void> _recordMedicineTaken(String medicineName) async {
    final now = DateTime.now();
    setState(() {
      final med = GlobalMedicineList.medicines.firstWhere((m) => m.name == medicineName);
      med.takenCount++;
      GlobalMedicineList.history.insert(0, '$medicineName|${now.toIso8601String()}');
      GlobalMedicineList.todayMedicine++;
      GlobalMedicineList.totalMedicine++;
      GlobalMedicineList.plantLevel = (GlobalMedicineList.totalMedicine ~/ 10) + 1;
      if (GlobalMedicineList.plantLevel > 5) GlobalMedicineList.plantLevel = 5;
    });
    await GlobalMedicineList.save();
    final med = GlobalMedicineList.medicines.firstWhere((m) => m.name == medicineName);
    if (!mounted) return;
    if (med.isDepleted) _showDepletedDialog(med);
    else if (med.isLowSupply) _showLowSupplyDialog(med);
    else _showGrowthAnimation();
  }

  void _showDepletedDialog(Medicine med) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: AppColors.beige,
      title: const Text('약이 다 떨어졌어요', style: TextStyle(fontSize: 22, color: AppColors.textDark)),
      content: Text('${med.name}의 처방 분량을 모두 복용했어요.\n새로 처방받으세요!',
          style: const TextStyle(fontSize: 18, color: AppColors.textDark)),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('확인', style: TextStyle(fontSize: 18)))],
    ));
  }

  void _showLowSupplyDialog(Medicine med) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: AppColors.beige,
      title: const Text('약 잔량 부족', style: TextStyle(fontSize: 22, color: AppColors.textDark)),
      content: Text('${med.name}이(가) 약 ${med.remainingDays?.toStringAsFixed(1)}일치 남았어요.\n곧 처방이 필요해요!',
          style: const TextStyle(fontSize: 18, color: AppColors.textDark)),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('확인', style: TextStyle(fontSize: 18)))],
    ));
  }

  Future<void> _loadMedicines() async {
    await GlobalMedicineList.load();
    if (mounted) setState(() {});
  }

  Future<void> _cleanupOldRecords() async {
    await GlobalMedicineList.load();
    final registered = GlobalMedicineList.medicines.map((m) => m.name).toSet();
    GlobalMedicineList.history.removeWhere((r) => !registered.contains(r.split('|')[0]));
    await GlobalMedicineList.save();
  }

  @override
  Widget build(BuildContext context) {
    final lowMeds = GlobalMedicineList.medicines.where((m) => m.isLowSupply).toList();
    final depletedMeds = GlobalMedicineList.medicines.where((m) => m.isDepleted).toList();

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(title: const Text('하루약속')),
      body: SingleChildScrollView(
        child: Column(children: [

          if (depletedMeds.isNotEmpty)
            _alertBanner(
                '${depletedMeds.map((m) => m.name).join(', ')} 약이 다 떨어졌어요!',
                AppColors.depletedBg, Colors.red.shade300, Colors.red.shade800),

          if (lowMeds.isNotEmpty)
            _alertBanner(
                '${lowMeds.map((m) => '${m.name} (${m.remainingDays?.toStringAsFixed(0)}일 남음)').join(', ')} 잔량이 부족해요!',
                AppColors.warnBg, AppColors.warnBorder, AppColors.warnText),

          // 식물 카드
          Container(
            width: double.infinity, margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.midGreen,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.midGreen.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              Text(_getPlantEmoji(GlobalMedicineList.plantLevel), style: const TextStyle(fontSize: 120)),
              const SizedBox(height: 10),
              Text('레벨 ${GlobalMedicineList.plantLevel}',
                  style: const TextStyle(fontSize: 24, color: AppColors.accentGreen, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: (GlobalMedicineList.totalMedicine % 10) / 10,
                  backgroundColor: Colors.white24, color: AppColors.accentGreen, minHeight: 10,
                ),
              ),
              const SizedBox(height: 10),
              Text('다음 레벨까지 ${10 - (GlobalMedicineList.totalMedicine % 10)}번 남았어요!',
                  style: const TextStyle(fontSize: 18, color: AppColors.beigeText)),
            ]),
          ),

          const BeaconOverlayWidget(),

          // 비콘 연결
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: GestureDetector(
              onTap: () async {
                await BeaconQuickPairSheet.showGlobal(context, onPaired: (beaconId) async {
                  GlobalMedicineList.pairedBeaconId = beaconId;
                  await GlobalMedicineList.save();
                  BeaconService.instance.stop(); _startBeaconService(); setState(() {});
                });
              },
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: GlobalMedicineList.pairedBeaconId.isNotEmpty ? Colors.blue.shade50 : AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GlobalMedicineList.pairedBeaconId.isNotEmpty ? Colors.blue.shade300 : AppColors.border),
                ),
                child: Row(children: [
                  Icon(GlobalMedicineList.pairedBeaconId.isNotEmpty ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: GlobalMedicineList.pairedBeaconId.isNotEmpty ? Colors.blue : AppColors.textMuted, size: 26),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    GlobalMedicineList.pairedBeaconId.isNotEmpty ? '약통 비콘 연결됨 (탭하면 변경)' : '약통 비콘 연결하기',
                    style: TextStyle(fontSize: 18,
                        color: GlobalMedicineList.pairedBeaconId.isNotEmpty ? Colors.blue.shade600 : AppColors.textMuted,
                        fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ),
          ),

          // 등록된 약 목록
          if (GlobalMedicineList.medicines.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.medication, color: AppColors.deepGreen, size: 28),
                  const SizedBox(width: 10),
                  const Text('등록된 약',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                ]),
                const SizedBox(height: 14),
                ...GlobalMedicineList.medicines.map((med) {
                  final isDepleted = med.isDepleted;
                  final isLow = med.isLowSupply;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDepleted ? AppColors.depletedBg : isLow ? AppColors.warnBg : AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(14),
                      border: Border(left: BorderSide(
                        color: isDepleted ? Colors.red.shade300 : isLow ? AppColors.warnBorder : AppColors.midGreen,
                        width: 4,
                      )),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.medication,
                          color: isDepleted ? Colors.red : isLow ? AppColors.warnBorder : AppColors.midGreen,
                          size: 28),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text(med.name,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                                    color: isDepleted ? Colors.red.shade700 : AppColors.textDark)),
                            if (isDepleted) _tag('소진', Colors.red, Colors.white)
                            else if (isLow) _tag('부족', AppColors.warnBorder, Colors.white),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${med.alarmTime.hour.toString().padLeft(2,'0')}:${med.alarmTime.minute.toString().padLeft(2,'0')}',
                            style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                        if (med.supplyDays != null) ...[
                          const SizedBox(height: 4),
                          Text(
                              isDepleted ? '약이 다 떨어졌어요'
                                  : '잔량: ${med.remainingDays?.toStringAsFixed(1)}일 (${med.remainingDoses}회)',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                  color: isDepleted ? Colors.red : isLow ? AppColors.warnText : AppColors.midGreen)),
                          const SizedBox(height: 5),
                          if (!isDepleted && med.totalDoses != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: med.remainingDoses! / med.totalDoses!,
                                backgroundColor: Colors.white38,
                                color: isLow ? AppColors.warnBorder : AppColors.midGreen,
                                minHeight: 6,
                              ),
                            ),
                        ],
                      ])),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 26),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: AppColors.beige,
                                title: const Text('약 삭제', style: TextStyle(fontSize: 22, color: AppColors.textDark)),
                                content: Text('${med.name}을(를) 삭제하시겠습니까?',
                                    style: const TextStyle(fontSize: 18, color: AppColors.textDark)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false),
                                      child: const Text('취소', style: TextStyle(fontSize: 18))),
                                  TextButton(onPressed: () => Navigator.pop(context, true),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('삭제', style: TextStyle(fontSize: 18))),
                                ],
                              ));
                          if (confirm == true) {
                            GlobalMedicineList.history.removeWhere((r) => r.split('|')[0] == med.name);
                            await NotificationService.cancelAlarm(med.name.hashCode.abs().remainder(10000));
                            setState(() { GlobalMedicineList.medicines.remove(med); });
                            await GlobalMedicineList.save();
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${med.name} 삭제 완료!'), backgroundColor: Colors.red));
                          }
                        },
                      ),
                    ]),
                  );
                }).toList(),
              ]),
            ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ElevatedButton.icon(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                BeaconService.instance.stop();  // ← push 전에 추가
                final result = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddMedicineScreen()));
                _startBeaconService();  // ← push 후에 추가 (돌아오면 재시작)
                if (result != null) {
                  if (result is List<Medicine>) {
                    for (var m in result) {
                      setState(() { GlobalMedicineList.medicines.add(m); });
                      try { await NotificationService.scheduleMedicineAlarm(
                          id: m.name.hashCode.abs().remainder(10000),
                          medicineName: m.name, time: m.alarmTime, selectedDays: m.selectedDays);
                      } catch (e) { print('알람 예약 실패: $e'); }
                    }
                    await GlobalMedicineList.save();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${result.length}개 약이 등록되었습니다!'),
                            backgroundColor: AppColors.deepGreen));
                  } else if (result is Medicine) {
                    setState(() { GlobalMedicineList.medicines.add(result); });
                    await GlobalMedicineList.save();
                    try { await NotificationService.scheduleMedicineAlarm(
                        id: result.name.hashCode.abs().remainder(10000),
                        medicineName: result.name, time: result.alarmTime,
                        selectedDays: result.selectedDays);
                    } catch (e) { print('알람 예약 실패: $e'); }
                  }
                }
              },
              label: const Text('💊  새 약 등록하기'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 64),
                backgroundColor: AppColors.btnRed,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ElevatedButton.icon(
              onPressed: () { HapticFeedback.mediumImpact(); _showMedicineDialog(context); },
              label: const Text('✅  약 먹었어요!'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 64),
                backgroundColor: AppColors.btnBlue,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _alertBanner(String text, Color bg, Color borderColor, Color textColor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor)),
      child: Text(text, style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w700),
          softWrap: true),
    );
  }

  Widget _tag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }

  String _getPlantEmoji(int level) {
    switch (level) {
      case 1: return '🌱'; case 2: return '🌿'; case 3: return '🪴';
      case 4: return '🌳'; case 5: return '🌲'; default: return '🌱';
    }
  }

  void _showMedicineDialog(BuildContext context) {
    List<String> selected = [];
    showDialog(context: context, builder: (context) {
      return StatefulBuilder(builder: (context, setDialogState) {
        final available = GlobalMedicineList.medicines.where((m) => !m.isDepleted).toList();
        return AlertDialog(
          backgroundColor: AppColors.beige,
          title: const Text('어떤 약을 드셨나요?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          content: available.isEmpty
              ? const Text('모든 약의 처방 분량을 다 복용했어요!', style: TextStyle(fontSize: 18))
              : Wrap(spacing: 8, runSpacing: 8, children: available.map((med) {
            final isSel = selected.contains(med.name);
            return FilterChip(
              label: Text(med.isLowSupply ? '${med.name} (부족)' : med.name,
                  style: const TextStyle(fontSize: 18)),
              selected: isSel,
              selectedColor: AppColors.lightGreen,
              checkmarkColor: AppColors.deepGreen,
              onSelected: (v) => setDialogState(() {
                if (v) selected.add(med.name); else selected.remove(med.name);
              }),
            );
          }).toList()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('취소', style: TextStyle(fontSize: 18))),
            ElevatedButton(
              onPressed: selected.isEmpty ? null : () async {
                Navigator.pop(context);
                for (final name in selected) await _recordMedicineTaken(name);
              },
              child: Text('${selected.length}개 기록하기', style: const TextStyle(fontSize: 18)),
            ),
          ],
        );
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ 팀원 추가
    BeaconService.instance.stop();
    super.dispose();
  }

  void _showGrowthAnimation() {
    showDialog(context: context, barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.beige,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            const Text('식물이 쑥쑥 자라고 있어요!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark),
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text('건강 관리 잘하고 계세요!',
                style: TextStyle(fontSize: 18, color: AppColors.textMuted),
                textAlign: TextAlign.center),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('확인', style: TextStyle(fontSize: 18)))],
        ));
  }
}

// ── 챗봇 화면 ─────────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _wordsSpoken = "";
  List<ChatMessage> _messages = [];
  bool _isRecording = false;
  bool _isLoading = false;
  late AnimationController _animationController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> _speakText(String text) async {
    try {
      final response = await http.post(Uri.parse('$serverUrl/tts'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'text': text, 'voice': 'ko-KR-SunHiNeural'}));
      if (response.statusCode == 200) {
        await _audioPlayer.stop();
        await _audioPlayer.play(BytesSource(response.bodyBytes));
      }
    } catch (e) { print('TTS 에러: $e'); }
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this)..repeat(reverse: true);
    _messages.add(ChatMessage(
        text: '안녕하세요! 복약에 대해 궁금한 것이 있으면 말씀해 주세요.',
        isUser: false, time: DateTime.now()));
  }

  void _initSpeech() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      _speechEnabled = await _speechToText.initialize(
        onError: (e) => print('음성 인식 오류: $e'),
        onStatus: (s) => print('음성 인식 상태: $s'),
      );
      setState(() {});
    }
  }

  void _toggleRecording() async {
    if (!_speechEnabled) return;
    if (_isRecording) {
      HapticFeedback.lightImpact();
      await _speechToText.stop();
      setState(() => _isRecording = false);
      if (_wordsSpoken.isNotEmpty) await _sendMessage(_wordsSpoken);
    } else {
      HapticFeedback.heavyImpact();
      setState(() { _isRecording = true; _wordsSpoken = ''; });
      await _speechToText.listen(
        onResult: (r) => setState(() => _wordsSpoken = r.recognizedWords),
        localeId: 'ko_KR', listenMode: ListenMode.confirmation,
      );
    }
  }

  String _buildMedicineContext(String userMessage) {
    final registered = GlobalMedicineList.medicines.map((m) => m.name).toList();
    final scanned = GlobalMedicineList.lastScannedMedicines;
    if (registered.isEmpty && scanned.isEmpty) return userMessage;
    final buf = StringBuffer();
    buf.writeln('[사용자 약 정보]');
    if (registered.isNotEmpty) {
      buf.writeln('현재 등록된 약: ${registered.join(', ')}');
      for (final med in GlobalMedicineList.medicines) {
        if (med.supplyDays != null) {
          buf.writeln('  - ${med.name}: ${med.isDepleted ? '소진됨' : '잔량 ${med.remainingDays?.toStringAsFixed(1)}일'}');
        }
      }
    }
    if (scanned.isNotEmpty) {
      buf.writeln('최근 스캔한 처방약 (${GlobalMedicineList.lastScannedSetName}): ${scanned.join(', ')}');
    }
    buf.writeln();
    buf.writeln('[사용자 질문]');
    buf.writeln(userMessage);
    return buf.toString();
  }

  Future<void> _sendMessage(String text) async {
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, time: DateTime.now()));
      _isLoading = true;
      _wordsSpoken = '';
    });
    try {
      final msg = _buildMedicineContext(text);
      final response = await http.post(Uri.parse('$serverUrl/chat'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'user_id': userId, 'message': msg}))
          .timeout(const Duration(seconds: 90));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['reply'];
        if (!mounted) return;
        setState(() => _messages.add(ChatMessage(text: reply, isUser: false, time: DateTime.now())));
        if (reply != null && reply.isNotEmpty) _speakText(reply);
      } else { _addErrorMessage(); }
    } catch (e) {
      print('서버 에러: $e');
      if (!mounted) return;
      _addErrorMessage();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addErrorMessage() {
    if (!mounted) return;
    setState(() => _messages.add(ChatMessage(
        text: '서버에 연결할 수 없어요. 서버가 켜져 있는지 확인해주세요.',
        isUser: false, time: DateTime.now())));
  }

  @override
  Widget build(BuildContext context) {
    final hasRegistered = GlobalMedicineList.medicines.isNotEmpty;
    final hasScanned = GlobalMedicineList.lastScannedMedicines.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(title: const Text('AI 복약 도우미')),
      body: Column(children: [

        if (hasRegistered || hasScanned)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.lightGreen,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (hasRegistered)
                Row(children: [
                  const Icon(Icons.medication, color: AppColors.deepGreen, size: 22),
                  const SizedBox(width: 8),
                  Flexible(child: Text(
                    '등록된 약: ${GlobalMedicineList.medicines.map((m) => m.name).join(', ')}',
                    style: const TextStyle(fontSize: 16, color: AppColors.deepGreen, fontWeight: FontWeight.w700),
                  )),
                ]),
              if (hasScanned) ...[
                if (hasRegistered) const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.document_scanner, color: AppColors.deepGreen, size: 22),
                  const SizedBox(width: 8),
                  Flexible(child: Text(
                    '스캔된 처방약: ${GlobalMedicineList.lastScannedMedicines.join(', ')}',
                    style: const TextStyle(fontSize: 16, color: AppColors.deepGreen, fontWeight: FontWeight.w700),
                  )),
                  GestureDetector(
                    onTap: () => setState(() {
                      GlobalMedicineList.lastScannedMedicines = [];
                      GlobalMedicineList.lastScannedSetName = '';
                    }),
                    child: const Icon(Icons.close, color: AppColors.deepGreen, size: 22),
                  ),
                ]),
              ],
            ]),
          ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16), reverse: true,
            itemCount: _messages.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (_isLoading && index == 0) return _buildLoadingBubble();
              final msg = _messages[_messages.length - 1 - (index - (_isLoading ? 1 : 0))];
              return _buildChatBubble(msg);
            },
          ),
        ),

        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: AppColors.beige,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(children: [
            if (_isRecording || _wordsSpoken.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _isRecording ? (_wordsSpoken.isEmpty ? '듣고 있어요...' : _wordsSpoken) : _wordsSpoken,
                  style: const TextStyle(fontSize: 20, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
              ),

            GestureDetector(
              onTap: _isLoading ? null : _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLoading ? AppColors.textMuted
                      : _isRecording ? Colors.red.shade700
                      : AppColors.deepGreen,
                  boxShadow: [BoxShadow(
                    color: (_isRecording ? Colors.red : AppColors.deepGreen).withOpacity(0.4),
                    blurRadius: _isRecording ? 24 : 12,
                    spreadRadius: _isRecording ? 6 : 2,
                  )],
                ),
                child: Icon(
                  _isLoading ? Icons.hourglass_empty : (_isRecording ? Icons.stop : Icons.mic),
                  color: AppColors.beigeText, size: 52,
                ),
              ),
            ),

            const SizedBox(height: 14),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.deepGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isLoading ? '답변을 준비하고 있어요...'
                    : (_isRecording ? '버튼을 다시 눌러 완료하세요' : '버튼을 눌러 말씀해 주세요'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, color: AppColors.beigeText, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: message.isUser ? AppColors.deepGreen : AppColors.cardWhite,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
            bottomLeft: message.isUser ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight: message.isUser ? const Radius.circular(4) : const Radius.circular(18),
          ),
          border: message.isUser ? null : Border.all(color: AppColors.border),
        ),
        child: Text(message.text,
            style: TextStyle(fontSize: 18,
                color: message.isUser ? AppColors.beigeText : AppColors.textDark,
                height: 1.5)),
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(color: AppColors.cardWhite, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border)),
        child: const Text('답변을 준비하고 있어요...',
            style: TextStyle(fontSize: 18, color: AppColors.textMuted)),
      ),
    );
  }

  @override
  void dispose() {
    _speechToText.stop();
    _animationController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  ChatMessage({required this.text, required this.isUser, required this.time});
}

// ── 복약 기록 화면 ────────────────────────────────────────────────────────────

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = GlobalMedicineList.history;
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(title: const Text('복약 기록')),
      body: history.isEmpty
          ? const Center(child: Text('아직 복약 기록이 없어요.',
          style: TextStyle(fontSize: 20, color: AppColors.textMuted)))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: history.length,
        itemBuilder: (context, index) {
          final parts = history[index].split('|');
          final name = parts[0];
          final date = DateTime.parse(parts[1]);
          return Container(
            margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardWhite, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: AppColors.lightGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.medication, color: AppColors.deepGreen, size: 28)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20,
                    color: AppColors.textDark)),
                const SizedBox(height: 4),
                Text('${date.year}년 ${date.month}월 ${date.day}일  '
                    '${date.hour}:${date.minute.toString().padLeft(2,'0')}',
                    style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
              ])),
              const Icon(Icons.check_circle, color: AppColors.midGreen, size: 30),
            ]),
          );
        },
      ),
    );
  }
}