import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

const String _serverUrl = 'http://15.164.230.65:8000';

class OCRService {
  final ImagePicker _imagePicker = ImagePicker();

  static const Map<String, String> _bracketCategoryMap = {
    '항생': '항생제', '세팔로스포린': '항생제', '세균감염': '항생제',
    '페니실린': '항생제', '퀴놀론': '항생제', '마크로라이드': '항생제',
    'H2차단': '위장약', 'H2 차단': '위장약', '위산': '위장약',
    '위장운동': '소화제', '소화성궤양': '위장약', '위점막': '위장약',
    '소화': '소화제', '위장': '위장약', '역류': '위장약',
    '소염진통': '소염진통제', '비스테로이드': '소염진통제', 'NSAIDs': '소염진통제',
    '해열': '해열진통제', '진통': '해열진통제',
    '진해거담': '기관지약', '기침': '기관지약', '거담': '기관지약',
    '천식': '천식약', '알레르기': '알레르기약', '항히스타민': '알레르기약',
    '혈압': '혈압약', '고혈압': '혈압약', '칼슘차단': '혈압약',
    '당뇨': '당뇨약', '혈당': '당뇨약', '인슐린': '당뇨약',
    '콜레스테롤': '콜레스테롤약', '고지혈': '콜레스테롤약', '스타틴': '콜레스테롤약',
    '수면': '수면제', '진정': '안정제', '신경안정': '안정제',
    '갑상선': '갑상선약', '비뇨': '전립선약', '전립선': '전립선약',
    '근이완': '근이완제', '관절': '관절약', '골다공증': '골다공증약',
    '비타민': '비타민', '철분': '철분제', '영양': '영양제',
    '항바이러스': '항바이러스제', '바이러스': '항바이러스제',
  };

  static const List<String> _excludeKeywords = [
    '계산서', '영수증', '약국', '약사', '조제일', '복약안내',
    '원장', '조제료', '전화', '팩스', '사업자', '등록번호',
    '병원', '의원', '진료', '보험', '급여', '비급여', '총액',
    '본인부담', '공단부담', '실온보관', '냉장보관', '냉동보관',
    '유효기간', '제조일', '보관방법', '복약지도',
    '기계조작', '녹내장', '전문가에게', '위장장애',
    '항생제와', '병용하기', '내성균', '장기간', '연용하지',
    '황달', '간기능', '이상반응', '부작용', '주의사항',
    '다음내방일', '조제약사', '환자정보', '교부번호', '병원정보',
    '처방전교부번호', '처방전발행기관',
    '본인전액', '전액', '공단', '청구금액', '수납금액',
    '조제수가', '약품비', '처방전', '조제내역',
  ];

  static const List<String> _colorWords = [
    '노랑', '노란', '노란색', '노랑색', '흰색', '백색', '하얀',
    '갈색', '분홍', '파란', '빨간', '주황', '초록', '녹색',
    '주홍', '황색', '연두', '하늘', '연노란', '미황색',
    '장방형', '원형', '타원형', '육각형', '팔각형',
  ];

  Future<String> scanFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 95,
      );
      if (image == null) return '';
      return await _recognizeText(File(image.path));
    } catch (e) {
      print('갤러리 OCR 에러: $e');
      return '';
    }
  }

  Future<String> scanFromCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera, maxWidth: 2048, maxHeight: 2048, imageQuality: 95,
      );
      if (photo == null) return '';
      return await _recognizeText(File(photo.path));
    } catch (e) {
      print('카메라 OCR 에러: $e');
      return '';
    }
  }

  Future<String> _recognizeText(File imageFile) async {
    try {
      if (!await imageFile.exists()) return '';
      final bytes = imageFile.readAsBytesSync();
      final img64 = base64Encode(bytes);
      final response = await http.post(
        Uri.parse('$_serverUrl/ocr/scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': img64}),
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final text = data['text'] as String? ?? '';
        print('=== OCR 원문 ===\n$text\n===============');
        return text;
      }
      return '';
    } catch (e) {
      print('텍스트 인식 에러: $e');
      return '';
    }
  }

  // ── AI 기반 약품명 추출 + 서버 setName 우선 사용 ─────────────────────────
  Future<Map<String, dynamic>> extractMedicineInfoWithServer(String ocrText) async {
    try {
      final cleanedText = _preprocessText(ocrText);
      final supplyDays = _extractSupplyDays(cleanedText);
      final dailyCount = _extractDailyCount(cleanedText);
      final bracketCategory = _extractBracketCategory(cleanedText);

      print('서버 AI로 약품명 추출 중...');

      final extractResponse = await http.post(
        Uri.parse('$_serverUrl/ocr/extract'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ocr_text': ocrText}),
      ).timeout(const Duration(seconds: 60));

      if (extractResponse.statusCode == 200) {
        final data = jsonDecode(utf8.decode(extractResponse.bodyBytes));
        final aiNames = List<String>.from(data['medicines'] ?? []);
        final matched = List<Map<String, dynamic>>.from(data['matched'] ?? []);

        print('AI 추출 약품명: $aiNames');

        final verifiedMedicines = matched.map((m) => {
          'name': m['name'] ?? '',
          'company': m['company'] ?? '',
          'description': m['description'] ?? '',
          'shape': m['shape'] ?? '',
          'color1': m['color1'] ?? '',
          'db_matched': m['db_matched'] ?? false,
          'original': m['original'] ?? m['name'] ?? '',
        }).toList();

        final categoryTally = <String, int>{};
        if (bracketCategory != null) categoryTally[bracketCategory] = 3;
        for (final m in matched) {
          final desc = m['description'] as String? ?? '';
          final cat = _extractCategoryFromDesc(desc);
          if (cat != null) categoryTally[cat] = (categoryTally[cat] ?? 0) + 1;
        }

        // ✅ 서버 setName 우선 사용, 없거나 기본값이면 클라이언트 계산
        final serverSetName = data['setName'] as String?;
        final setName = (serverSetName != null &&
            serverSetName.isNotEmpty &&
            serverSetName != '처방약')
            ? serverSetName
            : _determineSetName(categoryTally, aiNames, verifiedMedicines, bracketCategory);

        print('최종 setName: $setName (서버: $serverSetName)');

        return {
          'setName': setName,
          'medicines': aiNames,
          'verifiedMedicines': verifiedMedicines,
          'supplyDays': supplyDays,
          'dailyCount': dailyCount,
          'recommendedTimes': _buildRecommendedTimes(dailyCount),
          'matchedCategories': categoryTally.keys.toList(),
          'rawText': ocrText,
        };
      }

      print('AI 추출 실패, 정규식으로 대체');
      return await _extractWithRegex(ocrText, cleanedText, supplyDays, dailyCount, bracketCategory);

    } catch (e) {
      print('정보 추출 에러: $e');
      return extractMedicineInfo(ocrText);
    }
  }

  Future<Map<String, dynamic>> _extractWithRegex(
      String ocrText, String cleanedText, int? supplyDays, int dailyCount, String? bracketCategory,
      ) async {
    final rawNames = _extractMedicineNames(cleanedText);
    final verifiedMedicines = <Map<String, dynamic>>[];
    final verifiedNames = <String>[];
    final categoryTally = <String, int>{};

    if (bracketCategory != null) {
      categoryTally[bracketCategory] = (categoryTally[bracketCategory] ?? 0) + 3;
    }

    final results = await Future.wait(rawNames.map((name) => _searchMedicineFromServer(name)));
    for (int i = 0; i < rawNames.length; i++) {
      final result = results[i];
      if (result != null) {
        verifiedMedicines.add(result);
        verifiedNames.add(result['name'] as String);
        final desc = result['description'] as String? ?? '';
        final category = _extractCategoryFromDesc(desc);
        if (category != null) categoryTally[category] = (categoryTally[category] ?? 0) + 1;
      } else {
        verifiedNames.add(rawNames[i]);
      }
    }

    final setName = _determineSetName(categoryTally, verifiedNames, verifiedMedicines, bracketCategory);
    return {
      'setName': setName,
      'medicines': verifiedNames,
      'verifiedMedicines': verifiedMedicines,
      'supplyDays': supplyDays,
      'dailyCount': dailyCount,
      'recommendedTimes': _buildRecommendedTimes(dailyCount),
      'matchedCategories': categoryTally.keys.toList(),
      'rawText': ocrText,
    };
  }

  Future<Map<String, dynamic>?> _searchMedicineFromServer(String keyword) async {
    try {
      if (keyword.length < 3) return null;
      final uri = Uri.parse('$_serverUrl/medicine/search').replace(queryParameters: {'keyword': keyword});
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['found'] == true && (data['medicines'] as List).isNotEmpty) {
          return data['medicines'][0] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      print('서버 검색 실패 ("$keyword"): $e');
    }
    return null;
  }

  Map<String, dynamic> extractMedicineInfo(String ocrText) {
    final cleanedText = _preprocessText(ocrText);
    final supplyDays = _extractSupplyDays(cleanedText);
    final dailyCount = _extractDailyCount(cleanedText);
    final rawNames = _extractMedicineNames(cleanedText);
    final bracketCategory = _extractBracketCategory(cleanedText);
    return {
      'setName': bracketCategory ?? (rawNames.isNotEmpty ? rawNames.first : '처방약'),
      'medicines': rawNames,
      'verifiedMedicines': <Map<String, dynamic>>[],
      'supplyDays': supplyDays,
      'dailyCount': dailyCount,
      'recommendedTimes': _buildRecommendedTimes(dailyCount),
      'matchedCategories': bracketCategory != null ? [bracketCategory] : <String>[],
      'rawText': ocrText,
    };
  }

  String _preprocessText(String text) {
    return text
        .replaceAll('l일', '1일').replaceAll('O일', '0일').replaceAll('o일', '0일')
        .replaceAll('ㅇ(', '이(').replaceAll('1회투약량', ' 1회투약량')
        .replaceAll('1일투여횟수', ' 1일투여횟수').replaceAll('총투약일수', ' 총투약일수')
        .replaceAll(RegExp(r'(\d+)정씩'), r'\1정씩 ')
        .replaceAll(RegExp(r'(\d+)캡슐씩'), r'\1캡슐씩 ')
        .replaceAll(RegExp(r'[※◆◇▶▷►▸●○■□]'), ' ')
        .replaceAll(RegExp(r'\r\n'), '\n').replaceAll(RegExp(r'\r'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ');
  }

  String? _extractBracketCategory(String text) {
    final bracketPattern = RegExp(r'\[([^\]]{2,20})\]');
    final categoryTally = <String, int>{};
    for (final match in bracketPattern.allMatches(text)) {
      final content = match.group(1)!.trim();
      for (final entry in _bracketCategoryMap.entries) {
        if (content.contains(entry.key)) {
          categoryTally[entry.value] = (categoryTally[entry.value] ?? 0) + 1;
          break;
        }
      }
    }
    if (categoryTally.isEmpty) return null;
    final sorted = categoryTally.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  List<String> _extractMedicineNames(String ocrText) {
    final names = <String>[];
    final lines = ocrText.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || _shouldExcludeLine(line)) continue;
      if (RegExp(r'^[\d\s.,/\-]+$').hasMatch(line)) continue;
      if (!RegExp(r'[가-힣a-zA-Z]').hasMatch(line)) continue;

      final bracketNamePattern = RegExp(r'^([가-힣a-zA-Z]{4,})\s*\[');
      final bracketNameMatch = bracketNamePattern.firstMatch(line);
      if (bracketNameMatch != null) {
        final name = _cleanMedicineName(bracketNameMatch.group(1)!);
        if (_isValidMedicineName(name) && !names.contains(name)) {
          names.add(name);
          continue;
        }
      }

      if (line.startsWith('*')) {
        final name = _trimDosage(_cleanMedicineName(line.substring(1)));
        if (_isValidMedicineName(name) && !names.contains(name)) { names.add(name); continue; }
      }

      final mgFormPattern = RegExp(
          r'([가-힣a-zA-Z]+(?:정|캡슐|시럽|액|산|환|연고|크림|겔|서방정|이알서방정|SR|XR|ER))\s*\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml)',
          caseSensitive: false);
      final mgFormMatch = mgFormPattern.firstMatch(line);
      if (mgFormMatch != null) {
        final name = _cleanMedicineName(mgFormMatch.group(1)!);
        if (_isValidMedicineName(name) && !names.contains(name)) { names.add(name); continue; }
      }

      final formPattern = RegExp(
          r'([가-힣a-zA-Z]{3,}(?:정|캡슐|시럽|액|산|환|연고|크림|겔|서방정|이알서방정))', caseSensitive: false);
      final formMatch = formPattern.firstMatch(line);
      if (formMatch != null) {
        final name = _cleanMedicineName(formMatch.group(0)!);
        if (_isValidMedicineName(name) && !names.contains(name)) { names.add(name); continue; }
      }

      final dosePattern = RegExp(r'^([가-힣a-zA-Z]{3,})\s+\d+[정캡슐ml]');
      final doseMatch = dosePattern.firstMatch(line);
      if (doseMatch != null) {
        final name = _cleanMedicineName(doseMatch.group(1)!);
        if (_isValidMedicineName(name) && !names.contains(name)) { names.add(name); continue; }
      }
    }

    _extractBracketNameFromFullText(ocrText, names);
    _extractStarNamesFromFullText(ocrText, names);
    _extractMgNamesFromFullText(ocrText, names);
    return names;
  }

  void _extractBracketNameFromFullText(String text, List<String> existing) {
    final pattern = RegExp(r'([가-힣a-zA-Z]{4,})\s*\[[가-힣a-zA-Z\s]+\]');
    for (final match in pattern.allMatches(text)) {
      final name = _cleanMedicineName(match.group(1)!);
      if (_isValidMedicineName(name) && !existing.contains(name)) {
        existing.add(name);
      }
    }
  }

  void _extractStarNamesFromFullText(String text, List<String> existing) {
    final starPattern = RegExp(r'\*([가-힣a-zA-Z][가-힣a-zA-Z\d]+(?:정|캡슐|시럽|액|산|환|연고|크림|겔|서방정)?)');
    for (final match in starPattern.allMatches(text)) {
      final name = _trimDosage(_cleanMedicineName(match.group(1)!));
      if (_isValidMedicineName(name) && !existing.contains(name)) existing.add(name);
    }
  }

  void _extractMgNamesFromFullText(String text, List<String> existing) {
    final mgPattern = RegExp(
        r'([가-힣a-zA-Z]{3,}(?:정|캡슐|시럽|액|산|연고|서방정)?)\s*\d+(?:\.\d+)?\s*(?:mg|mcg|g)', caseSensitive: false);
    for (final match in mgPattern.allMatches(text)) {
      final name = _cleanMedicineName(match.group(1) ?? '');
      if (_isValidMedicineName(name) && !existing.contains(name)) existing.add(name);
    }
    final dosePattern = RegExp(r'([가-힣a-zA-Z]{3,}(?:정|캡슐|시럽|액|산|연고|서방정)[\d가-힣]*)\s*\d*회투약량');
    for (final match in dosePattern.allMatches(text)) {
      final name = _cleanMedicineName(match.group(1)!);
      if (_isValidMedicineName(name) && !existing.contains(name)) existing.add(name);
    }
  }

  int? _extractSupplyDays(String text) {
    final patterns = [
      RegExp(r'총\s*투약\s*일수\s*[:\s]*(\d+)'), RegExp(r'총투약일수\s*(\d+)'),
      RegExp(r'(\d+)\s*일분'), RegExp(r'(\d+)\s*일치'),
      RegExp(r'투약\s*일수\s*[:\s]\s*(\d+)'), RegExp(r'처방\s*일수\s*[:\s]\s*(\d+)'),
      RegExp(r'조제\s*일수\s*[:\s]\s*(\d+)'), RegExp(r'총\s*투약\s*(\d+)'),
      RegExp(r'(\d+)일\s*처방'), RegExp(r'복용\s*기간\s*[:\s]*(\d+)'),
      RegExp(r'(\d+)\s*일간'), RegExp(r'\d+[정캡슐ml씩]+\s*\d+회\s*(\d+)일분'),
      RegExp(r'\d+[정캡슐ml씩]+\s*\d+[회번]\s*(\d+)일'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final days = int.tryParse(match.group(1)!);
        if (days != null && days > 0 && days <= 365) return days;
      }
    }
    return null;
  }

  int _extractDailyCount(String text) {
    final patterns = [
      RegExp(r'1\s*일\s*투여\s*횟수\s*(\d)'), RegExp(r'1\s*일\s*투약\s*횟수\s*[:\s]*(\d)'),
      RegExp(r'일\s*투여\s*횟수\s*(\d)'), RegExp(r'1\s*일\s*(\d)\s*회'),
      RegExp(r'하루\s*(\d)\s*[회번]'), RegExp(r'(\d)\s*회\s*/\s*일'),
      RegExp(r'(\d)\s*번\s*/\s*일'), RegExp(r'1일\s*(\d)회'),
      RegExp(r'(\d)회\s*복용'), RegExp(r'아침.*점심.*저녁'),
      RegExp(r'아침.*저녁'), RegExp(r'\d+[정캡슐ml씩]+\s*(\d+)\s*[회번]'),
    ];
    for (int i = 0; i < patterns.length - 3; i++) {
      final match = patterns[i].firstMatch(text);
      if (match != null) {
        final count = int.tryParse(match.group(1)!);
        if (count != null && count >= 1 && count <= 4) return count;
      }
    }
    if (patterns[patterns.length - 3].hasMatch(text)) return 3;
    if (patterns[patterns.length - 2].hasMatch(text)) return 2;
    final doseMatch = patterns[patterns.length - 1].firstMatch(text);
    if (doseMatch != null) {
      final count = int.tryParse(doseMatch.group(1)!);
      if (count != null && count >= 1 && count <= 4) return count;
    }
    return 3;
  }

  String? _extractCategoryFromDesc(String desc) {
    for (final entry in _bracketCategoryMap.entries) {
      if (desc.contains(entry.key)) return entry.value;
    }
    return null;
  }

  String _determineSetName(Map<String, int> categoryTally, List<String> names,
      List<Map<String, dynamic>> verifiedMedicines, String? bracketCategory) {
    if (bracketCategory != null) return bracketCategory;
    if (categoryTally.isNotEmpty) {
      final sorted = categoryTally.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.length == 1 || sorted[0].value > sorted[1].value) return sorted.first.key;
      return '${sorted[0].key}·${sorted[1].key}';
    }
    if (verifiedMedicines.isNotEmpty) {
      final firstName = verifiedMedicines[0]['name'] as String? ?? '';
      final simplified = firstName.split(RegExp(r'[\d(]'))[0].trim();
      if (simplified.length >= 3) return simplified;
    }
    if (names.isNotEmpty) {
      final best = names.firstWhere((n) => n.length >= 4, orElse: () => names.first);
      return best.split(RegExp(r'[\d(]'))[0].trim();
    }
    return '처방약';
  }

  bool _shouldExcludeLine(String line) {
    if (RegExp(r'^\[.*\]$').hasMatch(line)) return true;
    for (final kw in _excludeKeywords) { if (line.contains(kw)) return true; }
    for (final color in _colorWords) { if (line.contains(color)) return true; }
    if (RegExp(r'^\d+[정캡슐ml씩]+\s*\d+[회번]\s*\d+일').hasMatch(line)) return true;
    return false;
  }

  String _cleanMedicineName(String raw) {
    return raw.replaceAll(RegExp(r'[*•\[\]"|!@#%^&]'), '').replaceAll("'", '')
        .replaceAll('_', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _trimDosage(String name) {
    return name.replaceAll(
        RegExp(r'\d+(?:\.\d+)?(?:밀리그람|밀리|mg|mcg|g|ml|밀).*$', caseSensitive: false), '').trim();
  }

  bool _isValidMedicineName(String name) {
    if (name.length < 3 || name.length > 50) return false;
    if (!RegExp(r'[가-힣a-zA-Z]').hasMatch(name)) return false;
    for (final color in _colorWords) { if (name.contains(color)) return false; }
    for (final kw in _excludeKeywords) { if (name.contains(kw)) return false; }
    if (RegExp(r'^[\d\s\-.,]+$').hasMatch(name)) return false;
    return true;
  }

  List<TimeOfDay> _buildRecommendedTimes(int count) {
    switch (count) {
      case 1: return [const TimeOfDay(hour: 8, minute: 0)];
      case 2: return [const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 20, minute: 0)];
      case 4: return [const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 12, minute: 0),
        const TimeOfDay(hour: 18, minute: 0), const TimeOfDay(hour: 22, minute: 0)];
      case 3:
      default: return [const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 13, minute: 0),
        const TimeOfDay(hour: 18, minute: 0)];
    }
  }

  void dispose() { print('OCR 리소스 정리 완료'); }
}