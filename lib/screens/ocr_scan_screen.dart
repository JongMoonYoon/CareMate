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
  String _loadingMessage = '텍스트 인식 중...';

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _scanFromGallery() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = '텍스트 인식 중...';
    });
    try {
      final ocrText = await _ocrService.scanFromGallery();
      if (ocrText.isEmpty) {
        setState(() => _isLoading = false);
        _showErrorDialog('텍스트를 인식하지 못했어요.\n다시 시도해주세요.');
        return;
      }
      setState(() => _loadingMessage = 'AI가 약품명 분석 중...');
      final result = await _ocrService.extractMedicineInfoWithServer(ocrText);
      setState(() => _isLoading = false);

      if ((result['medicines'] as List).isNotEmpty) {
        _showResultDialog(result);
      } else {
        _showErrorDialog('약품명을 인식하지 못했어요.\n다시 시도해주세요.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) _showErrorDialog('오류가 발생했어요.\n앱을 다시 시작해주세요.');
    }
  }

  Future<void> _scanWithCamera() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = '텍스트 인식 중...';
    });
    try {
      final ocrText = await _ocrService.scanFromCamera();
      if (ocrText.isEmpty) {
        setState(() => _isLoading = false);
        _showErrorDialog('텍스트를 인식하지 못했어요.\n다시 시도해주세요.');
        return;
      }
      setState(() => _loadingMessage = 'AI가 약품명 분석 중...');
      final result = await _ocrService.extractMedicineInfoWithServer(ocrText);
      setState(() => _isLoading = false);

      if ((result['medicines'] as List).isNotEmpty) {
        _showResultDialog(result);
      } else {
        _showErrorDialog('약품명을 인식하지 못했어요.\n다시 시도해주세요.');
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

  void _showResultDialog(Map<String, dynamic> info) {
    final List<TimeOfDay> times = info['recommendedTimes'] ?? [];
    final int? supplyDays = info['supplyDays'];
    final int dailyCount = info['dailyCount'] ?? 3;
    final String setName = info['setName'] ?? '처방약';
    final List<String> medicines = List<String>.from(info['medicines'] ?? []);
    final List<Map<String, dynamic>> verifiedMedicines =
    List<Map<String, dynamic>>.from(info['verifiedMedicines'] ?? []);

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

              // 핵심 정보
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
                    _infoRow(
                      icon: '📦',
                      label: '보유량',
                      value: supplyDays != null ? '$supplyDays일치' : '알 수 없음',
                      highlight: supplyDays != null,
                    ),
                    const SizedBox(height: 6),
                    _infoRow(icon: '🔁', label: '하루 복용', value: '1일 $dailyCount회'),
                    const SizedBox(height: 6),
                    _infoRow(icon: '⏰', label: '복용 시간', value: timeStrings),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // DB 확인된 약품 전체 목록
              if (verifiedMedicines.isNotEmpty) ...[
                Row(
                  children: [
                    const Text(
                      '✅ 식약처 DB 확인된 약품',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${verifiedMedicines.length}개',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // ⭐ take(6) 제거 → 전체 표시
                ...verifiedMedicines.map((med) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (med['db_matched'] == true)
                          ? Colors.blue.shade50
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (med['db_matched'] == true)
                            ? Colors.blue.shade100
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                med['name'] ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: (med['db_matched'] == true)
                                      ? Colors.blue
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            if (med['db_matched'] == true)
                              const Text('✅', style: TextStyle(fontSize: 11))
                            else
                              const Text('❓', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                        if ((med['description'] ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              med['description'] ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        if ((med['company'] ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              med['company'] ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 8),
              ],

              // 전체 인식 약품 목록
              Text(
                '📋 인식된 약품 (${medicines.length}개)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (medicines.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('(약품명을 찾지 못했어요)',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              else
              // ⭐ take(6) 제거 → 전체 표시
                ...medicines.map((name) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text('• $name', style: const TextStyle(fontSize: 12)),
                )),

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
              Navigator.pop(context);
              Navigator.pop(context, info);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
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
        Text('$label: ', style: const TextStyle(fontSize: 13, color: Colors.black54)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
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
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.green),
            const SizedBox(height: 20),
            Text(_loadingMessage,
                style: const TextStyle(fontSize: 16, color: Colors.green)),
            const SizedBox(height: 8),
            const Text('AI가 약품명을 분석 중이에요...',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        )
            : Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.document_scanner, size: 100, color: Colors.green),
              const SizedBox(height: 20),
              const Text('약 봉투를 스캔해주세요',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'AI가 약품명을 정확하게 인식해요',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
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
                        borderRadius: BorderRadius.circular(15)),
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
                    side: const BorderSide(color: Colors.green, width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
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