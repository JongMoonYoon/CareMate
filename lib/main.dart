import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'screens/add_medicine_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'service/notification_service.dart';
import 'beacon/beacon_service.dart';
import 'beacon/beacon_overlay_widget.dart';
import 'beacon/beacon_quick_pair_sheet.dart';


const String serverUrl = 'https://ornamented-jeramy-achromatically.ngrok-free.app';
const String userId = 'user_001';

void main() async {
  // 1. Flutter 엔진 초기화 및 알람 서비스 시작
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();

  // ⭐ 블루투스 권한 요청 (Android 12+ 필수)
  await _requestBluetoothPermissions();

  runApp(MaterialApp( // ⭐ const 제거!
    home: const PlantCareApp(),
    debugShowCheckedModeBanner: false,

    theme: ThemeData(
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(fontSize: 18),
        bodyMedium: TextStyle(fontSize: 16),
        labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        ),
      ),
      appBarTheme: const AppBarTheme(
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  ));
}

// ⭐ 블루투스 권한 요청
Future<void> _requestBluetoothPermissions() async {
  // Android 12+ (API 31+)
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
  print('✅ 블루투스 권한 요청 완료');
}

// 전역 약 리스트
class GlobalMedicineList {
  static List<Medicine> medicines = [];
  static List<String> history = [];

  static int plantLevel = 1;
  static int todayMedicine = 0;
  static int totalMedicine = 0;

  // ⭐ 전역 비콘 ID (약통 하나에 하나의 비콘)
  static String pairedBeaconId = '';

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = medicines.map((m) => {
      'name': m.name,
      'hour': m.alarmTime.hour,
      'minute': m.alarmTime.minute,
      'isTaken': m.isTaken,
      'selectedDays': m.selectedDays,
    }).toList();

    await prefs.setString('medicines', jsonEncode(jsonList));
    await prefs.setStringList('medicine_history', history);
    await prefs.setInt('plantLevel', plantLevel);
    await prefs.setInt('todayMedicine', todayMedicine);
    await prefs.setInt('totalMedicine', totalMedicine);
    await prefs.setString('pairedBeaconId', pairedBeaconId); // ⭐
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('medicines');

    if (jsonStr != null) {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      medicines = jsonList.map((json) => Medicine(
        name: json['name'],
        alarmTime: TimeOfDay(
          hour: json['hour'],
          minute: json['minute'],
        ),
        selectedDays: json['selectedDays'] != null
            ? List<int>.from(json['selectedDays'])
            : [0, 1, 2, 3, 4, 5, 6],
        isTaken: json['isTaken'] ?? false,
      )).toList();
    }

    history = prefs.getStringList('medicine_history') ?? [];
    plantLevel = prefs.getInt('plantLevel') ?? 1;
    todayMedicine = prefs.getInt('todayMedicine') ?? 0;
    totalMedicine = prefs.getInt('totalMedicine') ?? 0;
    pairedBeaconId = prefs.getString('pairedBeaconId') ?? ''; // ⭐
  }
}

class MedicationManager extends ChangeNotifier {
  List<Medicine> _medicines = [];

  List<Medicine> get medicines => _medicines;

  void addMedicine(Medicine med) {
    _medicines.add(med);
    notifyListeners();
  }

  void removeMedicine(String name) {
    _medicines.removeWhere((m) => m.name == name);
    notifyListeners();
  }

  void toggleTaken(String name) {
    final med = _medicines.firstWhere((m) => m.name == name);
    med.isTaken = !med.isTaken;
    notifyListeners();
  }
}

class Medicine {
  final String name;
  final TimeOfDay alarmTime;
  final List<int> selectedDays;
  bool isTaken;

  Medicine({
    required this.name,
    required this.alarmTime,
    this.selectedDays = const [0, 1, 2, 3, 4, 5, 6],
    this.isTaken = false,
  });
}

class PlantCareApp extends StatefulWidget {
  const PlantCareApp({super.key});

  @override
  State<PlantCareApp> createState() => _PlantCareAppState();
}

class _PlantCareAppState extends State<PlantCareApp> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ChatScreen(),
    const HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.green,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.eco),
            label: '내 식물',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble),
            label: '대화하기',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: '복약 기록',
          ),
        ],
      ),
    );
  }
}

// 홈 화면
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();
    _loadMedicines();
    _cleanupOldRecords();
    _startBeaconService(); // ⭐ 비콘 서비스 시작
    // NotificationService.cancelAllAlarms();
    // NotificationService.showTestNotification();
  }

  // ⭐ 비콘 서비스 시작 (전역 단일 비콘)
  Future<void> _startBeaconService() async {
    await Future.delayed(const Duration(milliseconds: 500));

    // ⭐ 페어링 화면 거치지 않고 MAC 주소 직접 지정해서 테스트
    const testBeaconMac = '48:87:2D:9D:C2:4F'; // ← 여기에 실제 MAC 주소 입력

    await BeaconService.instance.start(
      watchedIds: {testBeaconMac},
      onTaken: _onBeaconMedicineTaken,
    );
  }

  // ⭐ 현재 시각과 가장 가까운 알람 시간의 약 찾기
  Medicine? _findNearestMedicine() {
    if (GlobalMedicineList.medicines.isEmpty) return null;

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;

    Medicine? nearest;
    int minDiff = 999999;

    for (final med in GlobalMedicineList.medicines) {
      final medMinutes = med.alarmTime.hour * 60 + med.alarmTime.minute;
      int diff = (medMinutes - nowMinutes).abs();
      // 자정 넘어가는 경우 처리 (예: 23:50 ↔ 00:10)
      if (diff > 12 * 60) diff = 24 * 60 - diff;

      if (diff < minDiff) {
        minDiff = diff;
        nearest = med;
      }
    }

    return nearest;
  }

  // ⭐ 비콘 감지 → 가장 가까운 시간의 약 확인 팝업
  Future<void> _onBeaconMedicineTaken(String beaconId) async {
    final medicine = _findNearestMedicine();
    if (medicine == null) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💊', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text(
              medicine.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '약을 드셨나요?',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '복용 시간: ${medicine.alarmTime.hour.toString().padLeft(2, '0')}:${medicine.alarmTime.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '아니요',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              '네, 먹었어요!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final now = DateTime.now();
    setState(() {
      GlobalMedicineList.history.insert(0, '${medicine.name}|${now.toIso8601String()}');
      GlobalMedicineList.todayMedicine++;
      GlobalMedicineList.totalMedicine++;
      GlobalMedicineList.plantLevel = (GlobalMedicineList.totalMedicine ~/ 10) + 1;
      if (GlobalMedicineList.plantLevel > 5) GlobalMedicineList.plantLevel = 5;
    });

    await GlobalMedicineList.save();
    if (mounted) _showGrowthAnimation();
  }

  Future<void> _loadMedicines() async {
    await GlobalMedicineList.load();
    if (mounted) {
      setState(() {});
      // 약 로드 완료 후 비콘 서비스 재시작 (저장된 beaconId 반영)
      BeaconService.instance.stop();
      _startBeaconService();
    }
  }

  Future<void> _cleanupOldRecords() async {
    await GlobalMedicineList.load();

    // 등록된 약 이름 목록
    final registeredMedicines = GlobalMedicineList.medicines
        .map((med) => med.name)
        .toSet();

    // 복약 기록 정리
    final initialCount = GlobalMedicineList.history.length;

    GlobalMedicineList.history.removeWhere((record) {
      final parts = record.split('|');
      final medicineName = parts[0];

      // 등록되지 않은 약이면 제거
      if (!registeredMedicines.contains(medicineName)) {
        print('🗑️ 미등록 약 기록 삭제: $medicineName');
        return true;
      }
      return false;
    });

    final removedCount = initialCount - GlobalMedicineList.history.length;

    if (removedCount > 0) {
      await GlobalMedicineList.save();
      print('✅ 복약 기록 정리 완료! ($removedCount개 삭제)');
    }
  }

  @override
  Widget build(BuildContext context) {
    int plantLevel = GlobalMedicineList.plantLevel;
    int totalMedicine = GlobalMedicineList.totalMedicine;
    int todayMedicine = GlobalMedicineList.todayMedicine;

    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text('하루약속'),
        backgroundColor: Colors.green,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 화분 카드
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade300,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text('🌱 나의 건강나무'),
                  const SizedBox(height: 20),
                  Text(
                    _getPlantEmoji(plantLevel),
                    style: const TextStyle(fontSize: 120),
                  ),
                  const SizedBox(height: 10),
                  Text('레벨 $plantLevel'),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: (totalMedicine % 10) / 10,
                    backgroundColor: Colors.grey.shade200,
                    color: Colors.green,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(height: 10),
                  Text('다음 레벨까지 ${10 - (totalMedicine % 10)}번 남았어요!'),
                ],
              ),
            ),

            // ⭐ 비콘 상태 위젯
            const BeaconOverlayWidget(),

            // ⭐ 비콘 연결 버튼 (나무↔약목록 사이, 한 번만 연결)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: GestureDetector(
                onTap: () async {
                  await BeaconQuickPairSheet.showGlobal(
                    context,
                    onPaired: (beaconId) async {
                      GlobalMedicineList.pairedBeaconId = beaconId;
                      await GlobalMedicineList.save();
                      BeaconService.instance.stop();
                      _startBeaconService();
                      setState(() {});
                    },
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: GlobalMedicineList.pairedBeaconId.isNotEmpty
                        ? Colors.blue.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: GlobalMedicineList.pairedBeaconId.isNotEmpty
                          ? Colors.blue.shade300
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        GlobalMedicineList.pairedBeaconId.isNotEmpty
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: GlobalMedicineList.pairedBeaconId.isNotEmpty
                            ? Colors.blue
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        GlobalMedicineList.pairedBeaconId.isNotEmpty
                            ? '약통 비콘 연결됨  (탭하면 변경)'
                            : '약통 비콘 연결하기  →',
                        style: TextStyle(
                          fontSize: 14,
                          color: GlobalMedicineList.pairedBeaconId.isNotEmpty
                              ? Colors.blue.shade600
                              : Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 등록된 약 목록
            if (GlobalMedicineList.medicines.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade300,
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.medication, color: Colors.green.shade700),
                        const SizedBox(width: 10),
                        const Text('등록된 약'),
                      ],
                    ),
                    const SizedBox(height: 15),
                    ...GlobalMedicineList.medicines.map((med) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.medication, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(med.name),
                                const SizedBox(height: 4),
                                Text(
                                  '${med.alarmTime.hour.toString().padLeft(2, '0')}:${med.alarmTime.minute.toString().padLeft(2, '0')}',
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('약 삭제'),
                                  content: Text('${med.name}을(를) 삭제하시겠습니까?\n복약 기록도 함께 삭제됩니다.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('취소'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('삭제'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                GlobalMedicineList.history.removeWhere((record) {
                                  final parts = record.split('|');
                                  return parts[0] == med.name;
                                });

                                await NotificationService.cancelAlarm(
                                  med.name.hashCode.abs().remainder(10000),
                                );

                                setState(() {
                                  GlobalMedicineList.medicines.remove(med);
                                });

                                await GlobalMedicineList.save();

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${med.name} 삭제 완료!'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    )).toList(),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // 약 등록 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddMedicineScreen(),
                    ),
                  );

                  if (result != null) {
                    // ⭐ List<Medicine> 처리
                    if (result is List<Medicine>) {
                      for (var medicine in result) {
                        setState(() {
                          GlobalMedicineList.medicines.add(medicine);
                        });

                        // 각각 알람 예약
                        try {
                          await NotificationService.scheduleMedicineAlarm(
                            id: medicine.name.hashCode.abs().remainder(10000),
                            medicineName: medicine.name,
                            time: medicine.alarmTime,
                            selectedDays: medicine.selectedDays,
                          );
                        } catch (e) {
                          print('❌ 알람 예약 실패: $e');
                        }
                      }

                      await GlobalMedicineList.save();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ ${result.length}개 약이 등록되었습니다!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                    // ⭐ 단일 Medicine 처리 (하위 호환성)
                    else if (result is Medicine) {
                      setState(() {
                        GlobalMedicineList.medicines.add(result);
                      });
                      await GlobalMedicineList.save();

                      try {
                        await NotificationService.scheduleMedicineAlarm(
                          id: result.name.hashCode.abs().remainder(10000),
                          medicineName: result.name,
                          time: result.alarmTime,
                          selectedDays: result.selectedDays,
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ ${result.name} 알람이 설정되었습니다!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        print('❌ 알람 예약 실패: $e');
                      }
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 24),
                    SizedBox(width: 10),
                    Text('새 약 등록하기'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 약 먹었어요 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _showMedicineDialog(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle, size: 24),
                    SizedBox(width: 10),
                    Text('약 먹었어요!'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  String _getPlantEmoji(int level) {
    switch (level) {
      case 1:
        return '🌱';
      case 2:
        return '🌿';
      case 3:
        return '🪴';
      case 4:
        return '🌳';
      case 5:
        return '🌲';
      default:
        return '🌱';
    }
  }

  Widget _buildStatusCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(value),
          const SizedBox(height: 4),
          Text(title),
        ],
      ),
    );
  }

  void _showMedicineDialog(BuildContext context) {
    // ⭐ 단일 String 대신 선택된 약 이름들을 담을 '리스트'를 선언합니다.
    List<String> selectedMedicineNames = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('어떤 약을 드셨나요? (중복 선택 가능)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (GlobalMedicineList.medicines.isEmpty)
                    const Text('등록된 약이 없습니다.\n먼저 약을 등록해주세요.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: GlobalMedicineList.medicines.map((med) {
                        // ⭐ 현재 약이 선택된 리스트에 포함되어 있는지 확인
                        final isSelected = selectedMedicineNames.contains(med.name);

                        return FilterChip( // ChoiceChip 대신 다중 선택에 적합한 FilterChip 사용
                          label: Text(med.name),
                          selected: isSelected,
                          selectedColor: Colors.green.shade200,
                          checkmarkColor: Colors.green.shade900,
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                // 선택 시 리스트에 추가
                                selectedMedicineNames.add(med.name);
                              } else {
                                // 해제 시 리스트에서 제거
                                selectedMedicineNames.remove(med.name);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  // ⭐ 하나라도 선택되어야 버튼 활성화
                  onPressed: selectedMedicineNames.isEmpty
                      ? null
                      : () async {
                    setState(() {
                      // 1. 선택한 약의 개수만큼 카운트 증가
                      int count = selectedMedicineNames.length;
                      GlobalMedicineList.todayMedicine += count;
                      GlobalMedicineList.totalMedicine += count;

                      String timestamp = DateTime.now().toString();

                      // 2. 선택된 모든 약을 각각 기록에 추가
                      for (String name in selectedMedicineNames) {
                        GlobalMedicineList.history.insert(0, "$name|$timestamp");
                      }

                      // 3. 레벨업 로직 (10번마다 레벨업)
                      GlobalMedicineList.plantLevel = (GlobalMedicineList.totalMedicine ~/ 10) + 1;
                      if (GlobalMedicineList.plantLevel > 5) GlobalMedicineList.plantLevel = 5;
                    });

                    await GlobalMedicineList.save();
                    Navigator.pop(context);
                    _showGrowthAnimation();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: Text('${selectedMedicineNames.length}개 기록하기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    BeaconService.instance.stop(); // ⭐ 비콘 서비스 중지
    super.dispose();
  }

  void _showGrowthAnimation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 20),
            const Text('식물이 쑥쑥 자라고 있어요!'),
            const SizedBox(height: 10),
            const Text('건강 관리 잘하고 계세요!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

// 대화하기 화면 - 서버 연동 버전
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _wordsSpoken = "마이크 버튼을 눌러 말씀해주세요";
  List<ChatMessage> _messages = [];
  bool _isRecording = false;
  bool _isLoading = false; // ⭐ AI 답변 대기 중
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _messages.add(ChatMessage(
      text: "안녕하세요! 저는 새싹이예요 🌱 오늘 기분은 어떠세요?",
      isUser: false,
      time: DateTime.now(),
    ));
  }

  void _initSpeech() async {
    PermissionStatus status = await Permission.microphone.request();
    if (status.isGranted) {
      _speechEnabled = await _speechToText.initialize(
        onError: (error) => print('음성 인식 오류: $error'),
        onStatus: (status) => print('음성 인식 상태: $status'),
      );
      setState(() {});
    }
  }

  void _toggleRecording() async {
    if (!_speechEnabled) {
      print('음성 인식이 활성화되지 않았습니다');
      return;
    }

    if (_isRecording) {
      HapticFeedback.lightImpact();
      await _speechToText.stop();
      setState(() {
        _isRecording = false;
      });

      if (_wordsSpoken.isNotEmpty &&
          _wordsSpoken != "마이크 버튼을 눌러 말씀해주세요") {
        await _sendMessage(_wordsSpoken); // ⭐ await 추가!
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _isRecording = true;
        _wordsSpoken = "";
      });

      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _wordsSpoken = result.recognizedWords;
          });
        },
        localeId: "ko_KR",
        listenMode: ListenMode.confirmation,
      );
    }
  }

  // ⭐⭐⭐ 핵심: 서버 호출로 변경! ⭐⭐⭐
  Future<void> _sendMessage(String text) async {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        time: DateTime.now(),
      ));
      _isLoading = true; // 로딩 시작
      _wordsSpoken = "마이크 버튼을 눌러 말씀해주세요";
    });

    try {
      final response = await http.post(
        Uri.parse('$serverUrl/chat'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'user_id': userId,
          'message': text,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.add(ChatMessage(
            text: data['reply'],
            isUser: false,
            time: DateTime.now(),
          ));
        });
      } else {
        _addErrorMessage();
      }
    } catch (e) {
      print('서버 에러: $e');
      _addErrorMessage();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addErrorMessage() {
    setState(() {
      _messages.add(ChatMessage(
        text: '새싹이가 잠시 자리를 비웠어요. 서버가 켜져 있는지 확인해주세요 🌱',
        isUser: false,
        time: DateTime.now(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text('🌱 새싹이와 대화하기'),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              reverse: true,
              itemCount: _messages.length + (_isLoading ? 1 : 0), // ⭐ 로딩 버블 추가
              itemBuilder: (context, index) {
                if (_isLoading && index == 0) {
                  return _buildLoadingBubble(); // ⭐ 로딩 표시
                }
                final msg = _messages[_messages.length - 1 - (index - (_isLoading ? 1 : 0))];
                return _buildChatBubble(msg);
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade300,
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? Colors.red.shade100
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isRecording
                          ? Colors.red
                          : Colors.grey.shade300,
                      width: 3,
                    ),
                  ),
                  child: Row(
                    children: [
                      _isRecording
                          ? AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return Icon(
                            Icons.graphic_eq,
                            color: Colors.red,
                            size: 24 + (_animationController.value * 8),
                          );
                        },
                      )
                          : Icon(
                        Icons.mic_none,
                        color: Colors.grey.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isRecording
                                  ? "🎤 듣고 있어요..."
                                  : (_isLoading ? "새싹이가 생각 중..." : "준비 완료"), // ⭐ 로딩 상태 표시
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _wordsSpoken.isEmpty
                                  ? "마이크 버튼을 눌러 말씀해주세요"
                                  : _wordsSpoken,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                InkWell(
                  onTap: _isLoading ? null : _toggleRecording, // ⭐ 로딩 중엔 비활성화
                  borderRadius: BorderRadius.circular(50),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isLoading
                            ? [Colors.grey.shade400, Colors.grey.shade600] // ⭐ 로딩 중 회색
                            : _isRecording
                            ? [Colors.red.shade400, Colors.red.shade700]
                            : [Colors.green.shade400, Colors.green.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isRecording
                              ? Colors.red.withOpacity(0.5)
                              : Colors.green.withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: _isRecording ? 15 : 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isLoading
                          ? Icons.hourglass_empty // ⭐ 로딩 아이콘
                          : (_isRecording ? Icons.stop : Icons.mic),
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isLoading
                        ? '🌱 새싹이가 답변 중...'
                        : (_isRecording
                        ? '🛑 버튼을 다시 눌러 녹음 종료'
                        : '🎤 버튼을 눌러 녹음 시작'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.green : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade300,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  // ⭐ 로딩 버블 추가
  Widget _buildLoadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade300,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Text(
          '새싹이가 생각 중... 🌱',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speechToText.stop();
    _animationController.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
  });
}

// 복약 기록 화면
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    // 저장된 기록 가져오기
    final historyData = GlobalMedicineList.history;

    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text('복약 기록'),
        backgroundColor: Colors.green,
      ),
      body: historyData.isEmpty
          ? const Center(child: Text("아직 복약 기록이 없어요. 🌱"))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: historyData.length,
        itemBuilder: (context, index) {
          // 저장된 데이터 파싱 ("약이름|2026-...")
          final parts = historyData[index].split('|');
          final name = parts[0];
          final date = DateTime.parse(parts[1]);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(color: Colors.grey.shade300, blurRadius: 5, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
                  child: const Icon(Icons.medication, color: Colors.green),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text('${date.year}년 ${date.month}월 ${date.day}일 ${date.hour}:${date.minute.toString().padLeft(2, '0')}'),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
              ],
            ),
          );
        },
      ),
    );
  }
}