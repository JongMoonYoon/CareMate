import 'package:flutter/material.dart';
import '../service/ocr_service.dart';
import '../main.dart';

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
    setState(() { _isLoading = true; _loadingMessage = '텍스트 인식 중...'; });
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
        _saveToGlobalContext(result);
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
    setState(() { _isLoading = true; _loadingMessage = '텍스트 인식 중...'; });
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
        _saveToGlobalContext(result);
        _showResultDialog(result);
      } else {
        _showErrorDialog('약품명을 인식하지 못했어요.\n다시 시도해주세요.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) _showErrorDialog('오류가 발생했어요.\n앱을 다시 시작해주세요.');
    }
  }

  void _saveToGlobalContext(Map<String, dynamic> result) {
    GlobalMedicineList.lastScannedMedicines =
    List<String>.from(result['medicines'] ?? []);
    GlobalMedicineList.lastScannedSetName =
        result['setName'] as String? ?? '처방약';
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.beige,
        title: const Text('⚠️ 오류', style: TextStyle(fontSize: 20, color: AppColors.textDark)),
        content: Text(message, style: const TextStyle(fontSize: 16, color: AppColors.textDark)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인', style: TextStyle(fontSize: 16, color: AppColors.deepGreen)),
          )
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

    final allMedicines = <Map<String, dynamic>>[];
    final verifiedNames = verifiedMedicines.map((m) => m['original'] ?? m['name']).toSet();
    for (final m in verifiedMedicines) { allMedicines.add(m); }
    for (final name in medicines) {
      if (!verifiedNames.contains(name)) {
        allMedicines.add({'name': name, 'company': '', 'description': ''});
      }
    }

    final timeStrings = times
        .map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
        .join('  ·  ');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.beige,
        title: const Text('✅ 스캔 결과',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 처방 정보 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.midGreen.withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('💊 $setName',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                          color: AppColors.deepGreen)),
                  const SizedBox(height: 10),
                  _infoRow(icon: '📦', label: '보유량',
                      value: supplyDays != null ? '$supplyDays일치' : '알 수 없음',
                      highlight: supplyDays != null),
                  const SizedBox(height: 6),
                  _infoRow(icon: '🔁', label: '하루 복용', value: '1일 $dailyCount회'),
                  const SizedBox(height: 6),
                  _infoRow(icon: '⏰', label: '복용 시간', value: timeStrings),
                ]),
              ),

              const SizedBox(height: 12),

              // 챗봇 안내 배너
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.deepGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.deepGreen.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.chat_bubble_outline, color: AppColors.deepGreen, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '복약 도우미 탭에서 이 약에 대해 질문해보세요!',
                      style: TextStyle(fontSize: 13, color: AppColors.deepGreen),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 14),

              // 약품 목록
              Row(children: [
                const Text('인식된 약품',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                        color: AppColors.textDark)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.deepGreen,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${allMedicines.length}개',
                      style: const TextStyle(color: AppColors.beigeText,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 8),

              if (allMedicines.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('(약품명을 찾지 못했어요)',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                )
              else
                ...allMedicines.map((med) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(med['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700,
                              fontSize: 15, color: AppColors.textDark)),
                      if ((med['description'] ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(med['description'] ?? '',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ),
                      if ((med['company'] ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(med['company'] ?? '',
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ),
                    ]),
                  ),
                )),

              const SizedBox(height: 10),
              const Text('⚠️ 약 이름과 복용 횟수는 다음 화면에서 수정할 수 있어요.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, info);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('이대로 등록하기',
                style: TextStyle(fontSize: 16, color: AppColors.beigeText)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required String icon, required String label,
    required String value, bool highlight = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$icon ', style: const TextStyle(fontSize: 14)),
      Text('$label: ', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      Expanded(child: Text(value,
          style: TextStyle(fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.normal,
              color: highlight ? AppColors.midGreen : AppColors.textDark))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        title: const Text('약 봉투 스캔'),
        backgroundColor: AppColors.deepGreen,
      ),
      body: Center(
        child: _isLoading
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: AppColors.deepGreen),
          const SizedBox(height: 24),
          Text(_loadingMessage,
              style: const TextStyle(fontSize: 18, color: AppColors.deepGreen,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('AI가 약품명을 분석 중이에요...',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        ])
            : Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.document_scanner, size: 100, color: AppColors.deepGreen),
            const SizedBox(height: 20),
            const Text('약 봉투를 스캔해주세요',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: AppColors.textDark)),
            const SizedBox(height: 8),
            const Text('AI가 약품명을 정확하게 인식해요',
                style: TextStyle(fontSize: 15, color: AppColors.textMuted)),
            const SizedBox(height: 48),

            // 카메라 버튼
            SizedBox(
              width: double.infinity, height: 64,
              child: ElevatedButton.icon(
                onPressed: _scanWithCamera,
                icon: const Icon(Icons.camera_alt, size: 28),
                label: const Text('카메라로 촬영',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepGreen,
                  foregroundColor: AppColors.beigeText,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 갤러리 버튼
            SizedBox(
              width: double.infinity, height: 64,
              child: OutlinedButton.icon(
                onPressed: _scanFromGallery,
                icon: const Icon(Icons.photo_library, size: 28),
                label: const Text('갤러리에서 선택',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.deepGreen,
                  side: const BorderSide(color: AppColors.deepGreen, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}