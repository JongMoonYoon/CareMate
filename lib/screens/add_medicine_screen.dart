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
  final _supplyDaysController = TextEditingController();

  int _dailyCount = 1;
  List<TimeOfDay> _selectedTimes = [const TimeOfDay(hour: 8, minute: 0)];
  List<bool> _selectedDays = List.filled(7, true);

  static const List<List<TimeOfDay>> _defaultTimes = [
    [TimeOfDay(hour: 8, minute: 0)],
    [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
    [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 13, minute: 0), TimeOfDay(hour: 18, minute: 0)],
  ];

  void _onDailyCountChanged(int count) {
    setState(() {
      _dailyCount = count;
      final defaults = _defaultTimes[count - 1];
      _selectedTimes = List.generate(
        count,
            (i) => i < _selectedTimes.length ? _selectedTimes[i] : defaults[i],
      );
    });
  }

  Future<void> _selectTime(int index) async {
    int hour = _selectedTimes[index].hour;
    int minute = _selectedTimes[index].minute;

    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.beige,
            title: const Text('복용 시간 설정',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                    color: AppColors.textDark)),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 시간
                _timeColumn(
                  label: '시',
                  value: hour,
                  onInc: () => setDialogState(() => hour = (hour + 1) % 24),
                  onDec: () => setDialogState(() => hour = (hour - 1 + 24) % 24),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(':', style: TextStyle(fontSize: 40,
                      fontWeight: FontWeight.w700, color: AppColors.textDark)),
                ),
                // 분
                _timeColumn(
                  label: '분',
                  value: minute,
                  onInc: () => setDialogState(() => minute = (minute + 5) % 60),
                  onDec: () => setDialogState(() => minute = (minute - 5 + 60) % 60),
                  display: minute.toString().padLeft(2, '0'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소', style: TextStyle(fontSize: 18, color: AppColors.textMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, TimeOfDay(hour: hour, minute: minute)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.deepGreen),
                child: const Text('확인', style: TextStyle(fontSize: 18, color: AppColors.beigeText)),
              ),
            ],
          );
        });
      },
    );
    if (picked != null) setState(() => _selectedTimes[index] = picked);
  }

  Widget _timeColumn({
    required String label,
    required int value,
    required VoidCallback onInc,
    required VoidCallback onDec,
    String? display,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, color: AppColors.textMuted,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        IconButton(
          onPressed: onInc,
          icon: const Icon(Icons.keyboard_arrow_up_rounded,
              size: 44, color: AppColors.deepGreen),
          padding: EdgeInsets.zero,
        ),
        Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.deepGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            display ?? value.toString().padLeft(2, '0'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700,
                color: AppColors.beigeText),
          ),
        ),
        IconButton(
          onPressed: onDec,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 44, color: AppColors.deepGreen),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = ['월', '화', '수', '목', '금', '토', '일'];

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        title: const Text('약 등록하기'),
        backgroundColor: AppColors.deepGreen,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // OCR 스캔 버튼
            SizedBox(
              width: double.infinity,
              height: 62,
              child: ElevatedButton.icon(
                onPressed: _scanMedicineBag,
                icon: const Icon(Icons.document_scanner, size: 26),
                label: const Text('약 봉투 스캔하기',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepGreen,
                  foregroundColor: AppColors.beigeText,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // 약 이름
            _sectionTitle('💊 약 이름'),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 18, color: AppColors.textDark),
              decoration: InputDecoration(
                hintText: '예) 혈압약, 비타민',
                hintStyle: const TextStyle(fontSize: 16, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.cardWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              ),
            ),

            const SizedBox(height: 28),

            // 하루 복용 횟수
            _sectionTitle('🔁 하루 복용 횟수'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                    blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [1, 2, 3].map((count) {
                  final selected = _dailyCount == count;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onDailyCountChanged(count),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.deepGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(children: [
                          Text('$count회',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: selected ? AppColors.beigeText : AppColors.textMuted,
                              )),
                          const SizedBox(height: 3),
                          Text(
                            count == 1 ? '하루 한 번' : count == 2 ? '아침·저녁' : '아침·점심·저녁',
                            style: TextStyle(
                              fontSize: 13,
                              color: selected ? Colors.white70 : AppColors.textMuted,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 28),

            // 복용 시간
            _sectionTitle('⏰ 복용 시간'),
            const SizedBox(height: 10),
            ...List.generate(_dailyCount, (index) {
              final label = _getTimeLabel(_selectedTimes[index]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => _selectTime(index),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                          blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.lightGreen,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(label,
                            style: const TextStyle(fontSize: 15, color: AppColors.deepGreen,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${_selectedTimes[index].hour.toString().padLeft(2, '0')}:${_selectedTimes[index].minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
                            color: AppColors.deepGreen),
                      ),
                      const Spacer(),
                      const Icon(Icons.access_time, color: AppColors.deepGreen, size: 24),
                    ]),
                  ),
                ),
              );
            }),

            const SizedBox(height: 28),

            // 약 보유량
            _sectionTitle('📦 약 보유량'),
            const SizedBox(height: 6),
            const Text('비워두면 잔량 추적 없이 무한으로 복용 가능해요.',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            TextField(
              controller: _supplyDaysController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 18, color: AppColors.textDark),
              decoration: InputDecoration(
                hintText: '예) 30',
                hintStyle: const TextStyle(fontSize: 16, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.cardWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                suffixText: '일치',
                suffixStyle: const TextStyle(fontSize: 16, color: AppColors.deepGreen,
                    fontWeight: FontWeight.w700),
              ),
            ),

            const SizedBox(height: 28),

            // 반복 요일
            _sectionTitle('📅 반복 요일'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (index) {
                return FilterChip(
                  label: Text(days[index],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _selectedDays[index] ? AppColors.beigeText : AppColors.textMuted,
                      )),
                  selected: _selectedDays[index],
                  selectedColor: AppColors.deepGreen,
                  backgroundColor: AppColors.cardWhite,
                  checkmarkColor: AppColors.beigeText,
                  onSelected: (v) => setState(() => _selectedDays[index] = v),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                );
              }),
            ),

            const SizedBox(height: 50),

            // 저장 버튼
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: _saveMedicine,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepGreen,
                  foregroundColor: AppColors.beigeText,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('약 등록하기',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark));
  }

  Future<void> _scanMedicineBag() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (context) => const OCRScanScreen()));
    if (result != null) {
      final List<TimeOfDay> times =
          result['recommendedTimes'] ?? [const TimeOfDay(hour: 8, minute: 0)];
      final String setName = result['setName'] ?? '처방약';
      final int dailyCount = (result['dailyCount'] ?? times.length).clamp(1, 3);
      final int? supplyDays = result['supplyDays'];
      setState(() {
        _nameController.text = setName;
        _dailyCount = dailyCount;
        _selectedTimes = times.take(3).toList();
        if (supplyDays != null) _supplyDaysController.text = supplyDays.toString();
      });
    }
  }

  Future<void> _saveMedicine() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('약 이름을 입력해주세요')));
      return;
    }
    final selectedDayIndices = [for (int i = 0; i < 7; i++) if (_selectedDays[i]) i];
    if (selectedDayIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복용 요일을 하나 이상 선택해주세요')));
      return;
    }
    final baseName = _nameController.text;
    final supplyDays = _supplyDaysController.text.isNotEmpty
        ? int.tryParse(_supplyDaysController.text)
        : null;

    final medicines = List.generate(_dailyCount, (i) {
      final name = _dailyCount == 1 ? baseName : '$baseName ${_getTimeLabel(_selectedTimes[i])}';
      return Medicine(
        name: name,
        alarmTime: _selectedTimes[i],
        selectedDays: selectedDayIndices,
        supplyDays: supplyDays,
        dailyCount: 1,
        takenCount: 0,
      );
    });

    if (!mounted) return;
    Navigator.pop(context, medicines);
  }

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