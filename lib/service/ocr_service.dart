import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

const String _serverUrl = 'https://ornamented-jeramy-achromatically.ngrok-free.app';

class OCRService {
  final ImagePicker _imagePicker = ImagePicker();
  static const String _ocrApiKey = 'K88624131688957';

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 대괄호 카테고리 → 내부 약품 카테고리 매핑
  // 사진에서 발견: [세팔로스포린계 항생제], [H2 차단제], [소화제] 등
  // ────────────────────────────────────────────────────────────────────────────
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

  // ────────────────────────────────────────────────────────────────────────────
  // 제외 키워드
  // ────────────────────────────────────────────────────────────────────────────
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
  ];

  static const List<String> _colorWords = [
    '노랑', '노란', '노란색', '노랑색', '흰색', '백색', '하얀',
    '갈색', '분홍', '파란', '빨간', '주황', '초록', '녹색',
    '주홍', '황색', '연두', '하늘', '연노란', '미황색',
    '장방형', '원형', '타원형', '육각형', '팔각형',
  ];

  // ────────────────────────────────────────────────────────────────────────────
  // 갤러리 스캔
  // ────────────────────────────────────────────────────────────────────────────
  Future<String> scanFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (image == null) return '';
      return await _recognizeText(File(image.path));
    } catch (e) {
      print('❌ 갤러리 OCR 에러: $e');
      return '';
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 카메라 스캔
  // ────────────────────────────────────────────────────────────────────────────
  Future<String> scanFromCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
      if (photo == null) return '';
      return await _recognizeText(File(photo.path));
    } catch (e) {
      print('❌ 카메라 OCR 에러: $e');
      return '';
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // OCR.space API
  // ────────────────────────────────────────────────────────────────────────────
  Future<String> _recognizeText(File imageFile) async {
    try {
      if (!await imageFile.exists()) return '';

      final bytes = imageFile.readAsBytesSync();
      final img64 = base64Encode(bytes);

      final post = await http.post(
        Uri.parse('https://api.ocr.space/parse/image'),
        body: {
          'base64Image': 'data:image/jpg;base64,$img64',
          'language': 'kor',
          'isOverlayRequired': 'false',
          'detectOrientation': 'true',  // ⭐ 세로 사진 자동 보정
          'scale': 'true',              // ⭐ 저해상도 스케일업
          'OCREngine': '2',             // ⭐ 한국어 정확도 높음
          'isTable': 'true',            // ⭐ 표 형식 인식 강화
        },
        headers: {'apikey': _ocrApiKey},
      ).timeout(const Duration(seconds: 30));

      final result = jsonDecode(post.body);
      if (result['IsErroredOnProcessing'] == true) return '';

      final parsedResults = result['ParsedResults'] as List?;
      if (parsedResults == null || parsedResults.isEmpty) return '';

      final fullText = parsedResults[0]['ParsedText'] as String? ?? '';
      print('=== OCR 원문 ===\n$fullText\n===============');
      return fullText;
    } catch (e) {
      print('❌ 텍스트 인식 에러: $e');
      return '';
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 서버 DB 약품명 검색
  // ────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _searchMedicineFromServer(String keyword) async {
    try {
      if (keyword.length < 3) return null;
      final uri = Uri.parse('$_serverUrl/medicine/search')
          .replace(queryParameters: {'keyword': keyword});
      final response = await http.get(
        uri,
        headers: {'ngrok-skip-browser-warning': 'true'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['found'] == true && (data['medicines'] as List).isNotEmpty) {
          print('✅ DB 매칭: "$keyword" → ${data['medicines'][0]['name']}');
          return data['medicines'][0] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      print('⚠️ 서버 검색 실패 ("$keyword"): $e');
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 약 정보 추출 메인 (서버 DB 연동)
  // ────────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> extractMedicineInfoWithServer(String ocrText) async {
    try {
      final cleanedText = _preprocessText(ocrText);

      final supplyDays = _extractSupplyDays(cleanedText);
      final dailyCount = _extractDailyCount(cleanedText);
      final rawNames = _extractMedicineNames(cleanedText);

      // ⭐ 대괄호에서 카테고리 추출
      final bracketCategory = _extractBracketCategory(cleanedText);

      print('💊 OCR 추출 약품명: $rawNames');
      print('🏷️ 대괄호 카테고리: $bracketCategory');

      // 서버 DB 검색
      final verifiedMedicines = <Map<String, dynamic>>[];
      final verifiedNames = <String>[];
      final categoryTally = <String, int>{};

      // 대괄호 카테고리 우선 반영
      if (bracketCategory != null) {
        categoryTally[bracketCategory] = (categoryTally[bracketCategory] ?? 0) + 3;
      }

      for (final name in rawNames) {
        final result = await _searchMedicineFromServer(name);
        if (result != null) {
          verifiedMedicines.add(result);
          verifiedNames.add(result['name'] as String);
          final desc = result['description'] as String? ?? '';
          final category = _extractCategoryFromDesc(desc);
          if (category != null) {
            categoryTally[category] = (categoryTally[category] ?? 0) + 1;
          }
        } else {
          verifiedNames.add(name);
        }
      }

      final setName = _determineSetName(categoryTally, verifiedNames, verifiedMedicines, bracketCategory);
      final recommendedTimes = _buildRecommendedTimes(dailyCount);

      print('💊 최종 setName: $setName');
      print('📦 며칠치: ${supplyDays ?? "미확인"}');
      print('🔁 1일 $dailyCount회');

      return {
        'setName': setName,
        'medicines': verifiedNames,
        'verifiedMedicines': verifiedMedicines,
        'supplyDays': supplyDays,
        'dailyCount': dailyCount,
        'recommendedTimes': recommendedTimes,
        'matchedCategories': categoryTally.keys.toList(),
        'rawText': ocrText,
      };
    } catch (e) {
      print('❌ 정보 추출 에러: $e');
      return extractMedicineInfo(ocrText);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 폴백용 로컬 추출
  // ────────────────────────────────────────────────────────────────────────────
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

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 전처리 강화 (세로 사진, 구겨진 사진 대비)
  // ────────────────────────────────────────────────────────────────────────────
  String _preprocessText(String text) {
    return text
    // OCR 오류 보정
        .replaceAll('l일', '1일')
        .replaceAll('O일', '0일')
        .replaceAll('o일', '0일')
        .replaceAll('ㅇ(', '이(')
        .replaceAll('1회투약량', ' 1회투약량')
        .replaceAll('1일투여횟수', ' 1일투여횟수')
        .replaceAll('총투약일수', ' 총투약일수')
    // N정씩 N회 N일분 패턴 보정
        .replaceAll(RegExp(r'(\d+)정씩'), r'\1정씩 ')
        .replaceAll(RegExp(r'(\d+)캡슐씩'), r'\1캡슐씩 ')
    // 특수문자 정리
        .replaceAll(RegExp(r'[※◆◇▶▷►▸●○■□]'), ' ')
        .replaceAll(RegExp(r'\r\n'), '\n')
        .replaceAll(RegExp(r'\r'), '\n')
    // 연속 공백 정리
        .replaceAll(RegExp(r'[ \t]+'), ' ');
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 대괄호 카테고리 추출 (핵심 개선!)
  // 예) [세팔로스포린계 항생제] → '항생제'
  //     [H2 차단제] → '위장약'
  //     [소화성궤양 치료제] → '위장약'
  // ────────────────────────────────────────────────────────────────────────────
  String? _extractBracketCategory(String text) {
    // 대괄호 패턴 전체 추출
    final bracketPattern = RegExp(r'\[([^\]]{2,20})\]');
    final matches = bracketPattern.allMatches(text);

    final categoryTally = <String, int>{};

    for (final match in matches) {
      final content = match.group(1)!.trim();
      print('🔍 대괄호 내용: $content');

      // 대괄호 내용에서 카테고리 매핑
      for (final entry in _bracketCategoryMap.entries) {
        if (content.contains(entry.key)) {
          categoryTally[entry.value] = (categoryTally[entry.value] ?? 0) + 1;
          print('   → 카테고리: ${entry.value}');
          break;
        }
      }
    }

    if (categoryTally.isEmpty) return null;

    // 가장 많이 나온 카테고리 반환
    final sorted = categoryTally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 약품명 추출 강화
  // ────────────────────────────────────────────────────────────────────────────
  List<String> _extractMedicineNames(String ocrText) {
    final names = <String>[];
    final lines = ocrText.split('\n');

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (_shouldExcludeLine(line)) continue;
      if (RegExp(r'^[\d\s.,/\-]+$').hasMatch(line)) continue;
      if (!RegExp(r'[가-힣a-zA-Z]').hasMatch(line)) continue;

      // ── 우선순위 1: 별표(*) 약품명 ────────────────────────────
      if (line.startsWith('*')) {
        final name = _trimDosage(_cleanMedicineName(line.substring(1)));
        if (_isValidMedicineName(name) && !names.contains(name)) {
          names.add(name);
          print('⭐ 별표 약품명: $name');
          continue;
        }
      }

      // ── 우선순위 2: mg/mcg 포함 + 제형 키워드 ─────────────────
      // 예) "경보세푸록심아세틸정250mg", "엘도투캡슐300mg"
      final mgFormPattern = RegExp(
        r'([가-힣a-zA-Z]+(?:정|캡슐|시럽|액|산|환|연고|크림|겔|서방정|이알서방정|SR|XR|ER))\s*\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml)',
        caseSensitive: false,
      );
      final mgFormMatch = mgFormPattern.firstMatch(line);
      if (mgFormMatch != null) {
        final name = _cleanMedicineName(mgFormMatch.group(1)!);
        if (_isValidMedicineName(name) && !names.contains(name)) {
          names.add(name);
          print('💊 mg+제형 약품명: $name');
          continue;
        }
      }

      // ── 우선순위 3: 제형 키워드만 포함 ───────────────────────
      final formPattern = RegExp(
        r'([가-힣a-zA-Z]{3,}(?:정|캡슐|시럽|액|산|환|연고|크림|겔|서방정|이알서방정))',
        caseSensitive: false,
      );
      final formMatch = formPattern.firstMatch(line);
      if (formMatch != null) {
        final name = _cleanMedicineName(formMatch.group(0)!);
        if (_isValidMedicineName(name) && !names.contains(name)) {
          names.add(name);
          print('💊 제형 패턴: $name');
          continue;
        }
      }

      // ── 우선순위 4: "N정씩 N회 N일분" 앞의 약품명 ─────────────
      // 예) "베아제정제 1정씩 3회 5일분"
      final dosePattern = RegExp(r'^([가-힣a-zA-Z]{3,})\s+\d+[정캡슐ml]');
      final doseMatch = dosePattern.firstMatch(line);
      if (doseMatch != null) {
        final name = _cleanMedicineName(doseMatch.group(1)!);
        if (_isValidMedicineName(name) && !names.contains(name)) {
          names.add(name);
          print('💊 용량앞 약품명: $name');
          continue;
        }
      }
    }

    // 전체 텍스트 보완 스캔
    _extractStarNamesFromFullText(ocrText, names);
    _extractMgNamesFromFullText(ocrText, names);

    return names;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 전체 텍스트 별표 약품명 스캔
  // ────────────────────────────────────────────────────────────────────────────
  void _extractStarNamesFromFullText(String text, List<String> existing) {
    final starPattern = RegExp(
      r'\*([가-힣a-zA-Z][가-힣a-zA-Z\d]+(?:정|캡슐|시럽|액|산|환|연고|크림|겔|서방정)?)',
    );
    for (final match in starPattern.allMatches(text)) {
      final name = _trimDosage(_cleanMedicineName(match.group(1)!));
      if (_isValidMedicineName(name) && !existing.contains(name)) {
        existing.add(name);
        print('🔍 전체텍스트 별표: $name');
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 전체 텍스트에서 "약품명mg" 패턴 추출
  // 예) "프리투스정50mg", "스토맨정", "덱시네정"
  // ────────────────────────────────────────────────────────────────────────────
  void _extractMgNamesFromFullText(String text, List<String> existing) {
    // "약품명 + 숫자 + mg" 패턴
    final mgPattern = RegExp(
      r'([가-힣a-zA-Z]{3,}(?:정|캡슐|시럽|액|산|연고|서방정)?)\s*\d+(?:\.\d+)?\s*(?:mg|mcg|g)',
      caseSensitive: false,
    );
    for (final match in mgPattern.allMatches(text)) {
      final raw = match.group(1) ?? '';
      final name = _cleanMedicineName(raw);
      if (_isValidMedicineName(name) && !existing.contains(name)) {
        existing.add(name);
        print('🔍 mg패턴 약품명: $name');
      }
    }

    // "1회투약량" 앞의 약품명
    final dosePattern = RegExp(
      r'([가-힣a-zA-Z]{3,}(?:정|캡슐|시럽|액|산|연고|서방정)[\d가-힣]*)\s*\d*회투약량',
    );
    for (final match in dosePattern.allMatches(text)) {
      final name = _cleanMedicineName(match.group(1)!);
      if (_isValidMedicineName(name) && !existing.contains(name)) {
        existing.add(name);
        print('🔍 투약량앞 약품명: $name');
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 며칠치 추출 강화
  // 다양한 약봉투 패턴 대응
  // ────────────────────────────────────────────────────────────────────────────
  int? _extractSupplyDays(String text) {
    final patterns = [
      // 표준 패턴
      RegExp(r'총\s*투약\s*일수\s*[:\s]*(\d+)'),
      RegExp(r'총투약일수\s*(\d+)'),
      RegExp(r'(\d+)\s*일분'),
      RegExp(r'(\d+)\s*일치'),
      RegExp(r'투약\s*일수\s*[:\s]\s*(\d+)'),
      RegExp(r'처방\s*일수\s*[:\s]\s*(\d+)'),
      RegExp(r'조제\s*일수\s*[:\s]\s*(\d+)'),
      // ⭐ 추가 패턴 (사진에서 발견)
      RegExp(r'총\s*투약\s*(\d+)'),              // "총투약 5"
      RegExp(r'(\d+)일\s*처방'),                 // "5일 처방"
      RegExp(r'복용\s*기간\s*[:\s]*(\d+)'),      // "복용기간: 5"
      RegExp(r'(\d+)\s*일간'),                   // "5일간"
      // "1정씩 3회 5일분" 에서 일수 추출
      RegExp(r'\d+[정캡슐ml씩]+\s*\d+회\s*(\d+)일분'),
      RegExp(r'\d+[정캡슐ml씩]+\s*\d+[회번]\s*(\d+)일'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final days = int.tryParse(match.group(1)!);
        if (days != null && days > 0 && days <= 365) {
          print('📦 며칠치 발견: $days일 (패턴: ${pattern.pattern})');
          return days;
        }
      }
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // ⭐ 복용 횟수 추출 강화
  // ────────────────────────────────────────────────────────────────────────────
  int _extractDailyCount(String text) {
    final patterns = [
      // 약봉투 실제 패턴
      RegExp(r'1\s*일\s*투여\s*횟수\s*(\d)'),
      RegExp(r'1\s*일\s*투약\s*횟수\s*[:\s]*(\d)'),
      RegExp(r'일\s*투여\s*횟수\s*(\d)'),
      // 일반 패턴
      RegExp(r'1\s*일\s*(\d)\s*회'),
      RegExp(r'하루\s*(\d)\s*[회번]'),
      RegExp(r'(\d)\s*회\s*/\s*일'),
      RegExp(r'(\d)\s*번\s*/\s*일'),
      // ⭐ 추가 패턴 (사진에서 발견)
      RegExp(r'1일\s*(\d)회'),                  // "1일3회"
      RegExp(r'(\d)회\s*복용'),                 // "3회 복용"
      // "아침 점심 저녁" 키워드로 추론
      RegExp(r'아침.*점심.*저녁'),               // 3회
      RegExp(r'아침.*저녁'),                    // 2회
      // "1정씩 3회" 패턴
      RegExp(r'\d+[정캡슐ml씩]+\s*(\d+)\s*[회번]'),
    ];

    // 숫자 추출 패턴
    for (int i = 0; i < patterns.length - 3; i++) {
      final match = patterns[i].firstMatch(text);
      if (match != null) {
        final count = int.tryParse(match.group(1)!);
        if (count != null && count >= 1 && count <= 4) {
          print('🔁 복용횟수: $count회');
          return count;
        }
      }
    }

    // 시간 키워드로 추론
    if (patterns[patterns.length - 3].hasMatch(text)) return 3; // 아침점심저녁
    if (patterns[patterns.length - 2].hasMatch(text)) return 2; // 아침저녁

    // "1정씩 N회" 패턴
    final doseMatch = patterns[patterns.length - 1].firstMatch(text);
    if (doseMatch != null) {
      final count = int.tryParse(doseMatch.group(1)!);
      if (count != null && count >= 1 && count <= 4) return count;
    }

    return 3; // 기본값
  }

  // ────────────────────────────────────────────────────────────────────────────
  // description에서 카테고리 추출
  // ────────────────────────────────────────────────────────────────────────────
  String? _extractCategoryFromDesc(String desc) {
    for (final entry in _bracketCategoryMap.entries) {
      if (desc.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // setName 결정
  // ────────────────────────────────────────────────────────────────────────────
  String _determineSetName(
      Map<String, int> categoryTally,
      List<String> names,
      List<Map<String, dynamic>> verifiedMedicines,
      String? bracketCategory,
      ) {
    // 1. 대괄호 카테고리 최우선
    if (bracketCategory != null) return bracketCategory;

    // 2. DB 카테고리 매칭
    if (categoryTally.isNotEmpty) {
      final sorted = categoryTally.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.length == 1 || sorted[0].value > sorted[1].value) {
        return sorted.first.key;
      }
      return '${sorted[0].key}·${sorted[1].key}';
    }

    // 3. 서버 검증 약품명
    if (verifiedMedicines.isNotEmpty) {
      final firstName = verifiedMedicines[0]['name'] as String? ?? '';
      final simplified = firstName.split(RegExp(r'[\d(]'))[0].trim();
      if (simplified.length >= 3) return simplified;
    }

    // 4. OCR 약품명
    if (names.isNotEmpty) {
      final best = names.firstWhere((n) => n.length >= 4, orElse: () => names.first);
      return best.split(RegExp(r'[\d(]'))[0].trim();
    }

    return '처방약';
  }

  // ────────────────────────────────────────────────────────────────────────────
  // 헬퍼 함수들
  // ────────────────────────────────────────────────────────────────────────────
  bool _shouldExcludeLine(String line) {
    // 대괄호만 있는 라인은 제외 (약품명 아님)
    if (RegExp(r'^\[.*\]$').hasMatch(line)) return true;

    for (final kw in _excludeKeywords) {
      if (line.contains(kw)) return true;
    }
    for (final color in _colorWords) {
      if (line.contains(color)) return true;
    }

    // 복용법만 있는 라인 제외 ("1정씩 3회 5일분")
    if (RegExp(r'^\d+[정캡슐ml씩]+\s*\d+[회번]\s*\d+일').hasMatch(line)) return true;

    return false;
  }

  String _cleanMedicineName(String raw) {
    return raw
        .replaceAll(RegExp(r'[*•\[\]"|!@#%^&]'), '')
        .replaceAll("'", '')
        .replaceAll('_', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _trimDosage(String name) {
    return name
        .replaceAll(
        RegExp(r'\d+(?:\.\d+)?(?:밀리그람|밀리|mg|mcg|g|ml|밀).*$',
            caseSensitive: false),
        '')
        .trim();
  }

  bool _isValidMedicineName(String name) {
    if (name.length < 3 || name.length > 50) return false;
    if (!RegExp(r'[가-힣a-zA-Z]').hasMatch(name)) return false;

    for (final color in _colorWords) {
      if (name.contains(color)) return false;
    }
    for (final kw in _excludeKeywords) {
      if (name.contains(kw)) return false;
    }

    // 숫자만 있거나 특수문자만 있는 경우 제외
    if (RegExp(r'^[\d\s\-.,]+$').hasMatch(name)) return false;

    return true;
  }

  List<TimeOfDay> _buildRecommendedTimes(int count) {
    switch (count) {
      case 1:
        return [const TimeOfDay(hour: 8, minute: 0)];
      case 2:
        return [
          const TimeOfDay(hour: 8, minute: 0),
          const TimeOfDay(hour: 20, minute: 0),
        ];
      case 4:
        return [
          const TimeOfDay(hour: 8, minute: 0),
          const TimeOfDay(hour: 12, minute: 0),
          const TimeOfDay(hour: 18, minute: 0),
          const TimeOfDay(hour: 22, minute: 0),
        ];
      case 3:
      default:
        return [
          const TimeOfDay(hour: 8, minute: 0),
          const TimeOfDay(hour: 13, minute: 0),
          const TimeOfDay(hour: 18, minute: 0),
        ];
    }
  }

  void dispose() {
    print('✅ OCR 리소스 정리 완료');
  }
}
