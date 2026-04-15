import 'package:flutter/material.dart';
import '../service/ocr_service.dart';

class OCRScanScreen extends StatefulWidget {
  const OCRScanScreen({super.key});

  @override
  _OCRScanScreenState createState() => _OCRScanScreenState();
}

class _OCRScanScreenState extends State<OCRScanScreen> {
  final OCRService _ocrService = OCRService();
  bool _isLoading = false;

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _scanFromGallery() async {
    setState(() => _isLoading = true);
    try {
      final result = await _ocrService.scanFromGallery();
      setState(() => _isLoading = false);
      if (result.isNotEmpty) {
        _showResultDialog(result);
      } else {
        _showErrorDialog('텍스트를 인식하지 못했어요.\n다시 시도해주세요.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) _showErrorDialog('오류가 발생했어요.\n앱을 다시 시작해주세요.');
    }
  }

  Future<void> _scanWithCamera() async {
    setState(() => _isLoading = true);
    try {
      final result = await _ocrService.scanFromCamera();
      setState(() => _isLoading = false);
      if (result.isNotEmpty) {
        _showResultDialog(result);
      } else {
        _showErrorDialog('텍스트를 인식하지 못했어요.\n다시 시도해주세요.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) _showErrorDialog('오류가 발생했어요.\n앱을 다시 시작해주세요.');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showResultDialog(String text) {
    final info = _ocrService.extractMedicineInfo(text);

    final List<TimeOfDay> times = info['recommendedTimes'] ?? [];
    final int? supplyDays = info['supplyDays'];
    final int dailyCount = info['dailyCount'] ?? 3;
    final String setName = info['setName'] ?? '처방약';
    final List<String> medicines = List<String>.from(info['medicines'] ?? []);

    // 시간 문자열 리스트
    final timeStrings = times
        .map((t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
        .join('  ·  ');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('✅ 스캔 결과'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [

              // ── 약 이름 + 핵심 정보 ────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💊 $setName',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 며칠치
                    _infoRow(
                      icon: '📦',
                      label: '보유량',
                      value: supplyDays != null ? '$supplyDays일치' : '알 수 없음',
                      highlight: supplyDays != null,
                    ),
                    const SizedBox(height: 6),
                    // 1일 복용 횟수
                    _infoRow(
                      icon: '🔁',
                      label: '하루 복용',
                      value: '1일 $dailyCount회',
                    ),
                    const SizedBox(height: 6),
                    // 복용 시간
                    _infoRow(
                      icon: '⏰',
                      label: '복용 시간',
                      value: timeStrings,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── 약품 목록 ─────────────────────────────────────────
              Text(
                '📋 인식된 약품 (${medicines.length}개)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              if (medicines.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    '(약품명을 찾지 못했어요)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              else
                ...medicines.take(6).map((name) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text('• $name',
                      style: const TextStyle(fontSize: 12)),
                )),
              if (medicines.length > 6)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '외 ${medicines.length - 6}개...',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                ),

              const SizedBox(height: 10),
              const Text(
                '⚠️ 약 이름과 복용 횟수는 다음 화면에서 수정할 수 있어요.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);       // 다이얼로그 닫기
              Navigator.pop(context, info); // ⭐ 결과 전달 (add_medicine_screen으로)
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('이대로 등록하기'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required String icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$icon ', style: const TextStyle(fontSize: 14)),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
              highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? Colors.green.shade700 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('약 봉투 스캔'),
        backgroundColor: Colors.green,
      ),
      body: Center(
        child: _isLoading
            ? const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.green),
            SizedBox(height: 20),
            Text('텍스트 인식 중...'),
          ],
        )
            : Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.document_scanner,
                  size: 100, color: Colors.green),
              const SizedBox(height: 20),
              const Text(
                '약 봉투를 스캔해주세요',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '약 이름과 며칠치를 자동으로 인식해요',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _scanWithCamera,
                  icon: const Icon(Icons.camera_alt, size: 28),
                  label: const Text('카메라로 촬영',
                      style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: OutlinedButton.icon(
                  onPressed: _scanFromGallery,
                  icon: const Icon(Icons.photo_library, size: 28),
                  label: const Text('갤러리에서 선택',
                      style: TextStyle(fontSize: 18)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(
                        color: Colors.green, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
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