import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../service/notification_service.dart';
import 'ocr_scan_screen.dart';

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _nameController = TextEditingController();
  final _supplyDaysController = TextEditingController(); // ⭐ 며칠치 입력

  // ⭐ 하루 복용 횟수 (1, 2, 3)
  int _dailyCount = 1;

  // ⭐ 복용 횟수만큼 시간 리스트로 관리
  List<TimeOfDay> _selectedTimes = [const TimeOfDay(hour: 8, minute: 0)];

  List<bool> _selectedDays = List.filled(7, true);

  // 횟수별 기본 시간 세트
  static const List<List<TimeOfDay>> _defaultTimes = [
    [TimeOfDay(hour: 8, minute: 0)],
    [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
    [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 13, minute: 0), TimeOfDay(hour: 18, minute: 0)],
  ];

  // ⭐ 횟수 변경 시 시간 리스트 갱신
  void _onDailyCountChanged(int count) {
    setState(() {
      _dailyCount = count;
      // 기존 시간은 유지하고, 부족한 슬롯만 기본값으로 채움
      final defaults = _defaultTimes[count - 1];
      _selectedTimes = List.generate(
        count,
            (i) => i < _selectedTimes.length ? _selectedTimes[i] : defaults[i],
      );
    });
  }

  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimes[index],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Colors.green),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTimes[index] = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = ['월', '화', '수', '목', '금', '토', '일'];

    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text('약 등록하기'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── OCR 스캔 버튼 ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _scanMedicineBag,
                icon: const Icon(Icons.document_scanner, size: 24),
                label: const Text(
                  '약 봉투 스캔하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── 약 이름 ───────────────────────────────────────────────
            const Text('💊 약 이름',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '예) 혈압약, 비타민',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.medication, color: Colors.green),
              ),
            ),

            const SizedBox(height: 28),

            // ── 하루 복용 횟수 ─────────────────────────────────────────
            const Text('🔁 하루 복용 횟수',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade300,
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [1, 2, 3].map((count) {
                  final selected = _dailyCount == count;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onDailyCountChanged(count),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: selected ? Colors.green : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$count회',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: selected ? Colors.white : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              count == 1 ? '하루 한 번' : count == 2 ? '아침 · 저녁' : '아침 · 점심 · 저녁',
                              style: TextStyle(
                                fontSize: 11,
                                color: selected ? Colors.white70 : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 28),

            // ── 복용 시간 (횟수만큼 표시) ──────────────────────────────
            const Text('⏰ 복용 시간',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...List.generate(_dailyCount, (index) {
              final label = _getTimeLabel(_selectedTimes[index]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => _selectTime(index),
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade300,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // 라벨 뱃지
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          '${_selectedTimes[index].hour.toString().padLeft(2, '0')}:${_selectedTimes[index].minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.access_time, color: Colors.green),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 28),

            // ── 며칠치 약 ─────────────────────────────────────────────
            const Text('📦 약 보유량',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _supplyDaysController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: '예) 30  (비워두면 무한)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.inventory_2, color: Colors.green),
                suffixText: '일치',
                suffixStyle: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── 반복 요일 ─────────────────────────────────────────────
            const Text('📅 반복 요일',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: List.generate(7, (index) {
                return FilterChip(
                  label: Text(
                    days[index],
                    style: TextStyle(
                      color: _selectedDays[index] ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  selected: _selectedDays[index],
                  selectedColor: Colors.green,
                  backgroundColor: Colors.white,
                  onSelected: (selected) {
                    setState(() => _selectedDays[index] = selected);
                  },
                  checkmarkColor: Colors.white,
                );
              }),
            ),

            const SizedBox(height: 50),

            // ── 저장 버튼 ─────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 65,
              child: ElevatedButton(
                onPressed: _saveMedicine,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  '약 등록하기',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── OCR 스캔 ────────────────────────────────────────────────────────────

  Future<void> _scanMedicineBag() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OCRScanScreen()),
    );

    if (result != null) {
      final List<TimeOfDay> times =
          result['recommendedTimes'] ?? [const TimeOfDay(hour: 8, minute: 0)];
      final String setName = result['setName'] ?? '처방약';
      final int dailyCount = (result['dailyCount'] ?? times.length).clamp(1, 3);
      final int? supplyDays = result['supplyDays'];

      // ⭐ OCR 결과로 폼 전체 자동 채우기
      setState(() {
        _nameController.text = setName;
        _dailyCount = dailyCount;
        _selectedTimes = times.take(3).toList();
        if (supplyDays != null) {
          _supplyDaysController.text = supplyDays.toString();
        }
      });
    }
  }

  // ── 저장 ────────────────────────────────────────────────────────────────

  Future<void> _saveMedicine() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약 이름을 입력해주세요')),
      );
      return;
    }

    final selectedDayIndices = [
      for (int i = 0; i < 7; i++)
        if (_selectedDays[i]) i
    ];

    if (selectedDayIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복용 요일을 하나 이상 선택해주세요')),
      );
      return;
    }

    final baseName = _nameController.text;

    // ⭐ 복용 횟수만큼 Medicine 생성 → List<Medicine>으로 반환
    final medicines = List.generate(_dailyCount, (i) {
      final name = _dailyCount == 1
          ? baseName
          : '$baseName ${_getTimeLabel(_selectedTimes[i])}'; // 예) 혈압약 아침

      return Medicine(
        name: name,
        alarmTime: _selectedTimes[i],
        selectedDays: selectedDayIndices,
      );
    });

    if (!mounted) return;
    Navigator.pop(context, medicines); // ⭐ List<Medicine> 반환 (main.dart 호환)
  }

  // ── 헬퍼 ────────────────────────────────────────────────────────────────

  String _getTimeLabel(TimeOfDay time) {
    if (time.hour >= 5 && time.hour < 11) return '아침';
    if (time.hour >= 11 && time.hour < 16) return '점심';
    if (time.hour >= 16 && time.hour < 21) return '저녁';
    return '야간';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _supplyDaysController.dispose();
    super.dispose();
  }
}