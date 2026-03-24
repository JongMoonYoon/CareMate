import 'package:flutter/material.dart';
import '../main.dart';
import '../service/notification_service.dart';  // ⭐ Medicine 클래스 가져오기

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _nameController = TextEditingController();
  TimeOfDay _selectedTime = TimeOfDay.now();
  List<bool> _selectedDays = List.filled(7, true);

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true, // ⭐ 24시간제!
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.green,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedTime = picked);
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
            // 약 이름
            const Text(
              '💊 약 이름',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
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

            const SizedBox(height: 30),

            // 복용 시간
            const Text(
              '⏰ 복용 시간',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _selectTime,
              child: Container(
                padding: const EdgeInsets.all(20),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const Icon(Icons.access_time, color: Colors.green),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // 반복 요일
            const Text(
              '📅 반복 요일',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
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

            // 저장 버튼
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // add_medicine_screen.dart 파일의 _saveMedicine 수정

  Future<void> _saveMedicine() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약 이름을 입력해주세요')),
      );
      return;
    }

    // ⭐ 선택된 요일 추출
    List<int> selectedDayIndices = [];
    for (int i = 0; i < 7; i++) {
      if (_selectedDays[i]) {
        selectedDayIndices.add(i);
      }
    }

    // ⭐ Medicine 객체 생성
    final medicine = Medicine(
      name: _nameController.text,
      alarmTime: _selectedTime,
      selectedDays: selectedDayIndices,
    );

    // ⭐ 화면 닫고 데이터 전달 (알람은 main.dart에서 예약!)
    if (!mounted) return;
    Navigator.pop(context, medicine);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}