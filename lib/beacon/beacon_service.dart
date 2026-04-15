// lib/service/beacon_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ────────────────────────────────────────────────────────────────────────────
// 비콘 3단계 상태
// ────────────────────────────────────────────────────────────────────────────
enum BeaconPhase {
  idle,        // 대기 중 (비콘 미감지)
  verifying,   // 근접 감지됨 → 2초 유지 검증 중
  confirmed,   // 복용 확정!
}

// ────────────────────────────────────────────────────────────────────────────
// 상태 스냅샷 (UI에 전달)
// ────────────────────────────────────────────────────────────────────────────
class BeaconState {
  final BeaconPhase phase;
  final String? detectedBeaconId;   // 감지된 비콘 ID
  final int rssi;                   // 현재 RSSI
  final double verifyProgress;      // 0.0 ~ 1.0 (2초 진행률)
  final String? confirmedMedicineId; // 복용 확정된 약 beaconId

  const BeaconState({
    required this.phase,
    this.detectedBeaconId,
    this.rssi = 0,
    this.verifyProgress = 0.0,
    this.confirmedMedicineId,
  });

  static const idle = BeaconState(phase: BeaconPhase.idle);
}

// ────────────────────────────────────────────────────────────────────────────
// 비콘 서비스
// ────────────────────────────────────────────────────────────────────────────
class BeaconService {
  BeaconService._();
  static final BeaconService instance = BeaconService._();

  // ── 설정 값 ────────────────────────────────────────────────────────────────
  static const int _rssiThreshold = -45;      // 초밀착 임계값 (dBm)
  static const int _verifyDurationMs = 2000;  // 검증 시간 2초
  static const int _rssiSmoothWindow = 3;     // RSSI 평균 계산 샘플 수
  static const int _scanRestartIntervalMs = 3000; // 스캔 재시작 주기

  // ── 내부 상태 ──────────────────────────────────────────────────────────────
  final _stateController = StreamController<BeaconState>.broadcast();
  Stream<BeaconState> get stateStream => _stateController.stream;
  BeaconState _currentState = BeaconState.idle;

  // BLE 스캔
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _scanRestartTimer;

  // 검증 타이머
  Timer? _verifyTimer;
  Timer? _progressTimer;
  DateTime? _verifyStartTime;

  // RSSI 스무딩 (노이즈 제거)
  final Map<String, List<int>> _rssiHistory = {};

  // 감시할 비콘 ID 목록 (등록된 약의 beaconId)
  final Set<String> _watchedBeaconIds = {};

  // 복용 콜백
  Function(String beaconId)? onMedicineTaken;

  // ── 시작 / 종료 ────────────────────────────────────────────────────────────

  /// 서비스 시작. watchedIds = 감시할 beaconId 목록
  Future<void> start({
    required Set<String> watchedIds,
    required Function(String beaconId) onTaken,
  }) async {
    _watchedBeaconIds
      ..clear()
      ..addAll(watchedIds.where((id) => id.isNotEmpty));

    onMedicineTaken = onTaken;

    if (_watchedBeaconIds.isEmpty) {
      print('⚠️ 감시할 비콘이 없습니다. 비콘을 먼저 약에 등록해주세요.');
      return;
    }

    // BLE 지원 확인
    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      print('❌ 이 기기는 BLE를 지원하지 않습니다.');
      return;
    }

    print('🔵 비콘 서비스 시작 | 감시 비콘: $_watchedBeaconIds');
    _startScan();
  }

  /// 서비스 중지
  void stop() {
    _scanSubscription?.cancel();
    _scanRestartTimer?.cancel();
    _verifyTimer?.cancel();
    _progressTimer?.cancel();
    FlutterBluePlus.stopScan();
    _emitState(BeaconState.idle);
    print('⛔ 비콘 서비스 중지');
  }

  void dispose() {
    stop();
    _stateController.close();
  }

  // ── 스캔 관리 ──────────────────────────────────────────────────────────────

  void _startScan() {
    _scanSubscription?.cancel();

    FlutterBluePlus.startScan(
      // 감시 비콘만 필터 (없으면 전체 스캔)
      // withServices: [],
      timeout: const Duration(seconds: 3),
      continuousUpdates: true,
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen(_onScanResults);

    // 3초마다 재시작하여 연속 스캔 유지
    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer.periodic(
      const Duration(milliseconds: _scanRestartIntervalMs),
      (_) => _startScan(),
    );

    print('🔍 BLE 스캔 시작');
  }

  // ── 스캔 결과 처리 ─────────────────────────────────────────────────────────

  void _onScanResults(List<ScanResult> results) {
    // 감시 대상 비콘만 필터
    for (final result in results) {
      final deviceId = result.device.remoteId.str; // MAC or UUID

      if (!_watchedBeaconIds.contains(deviceId)) continue;

      // RSSI 스무딩 (노이즈 제거)
      final smoothedRssi = _smoothRssi(deviceId, result.rssi);

      print('📡 비콘[$deviceId] RSSI: ${result.rssi} → 평균: $smoothedRssi');

      if (smoothedRssi >= _rssiThreshold) {
        // 임계값 이상 → 근접 감지
        _onApproach(deviceId, smoothedRssi);
      } else {
        // 멀어짐 → 검증 취소
        if (_currentState.detectedBeaconId == deviceId &&
            _currentState.phase == BeaconPhase.verifying) {
          _cancelVerification(reason: '신호 약해짐 ($smoothedRssi dBm)');
        }
      }
    }
  }

  // ── 단계 1: 근접 감지 (Approach) ──────────────────────────────────────────

  void _onApproach(String beaconId, int rssi) {
    // 이미 이 비콘 검증 중이면 무시
    if (_currentState.phase == BeaconPhase.verifying &&
        _currentState.detectedBeaconId == beaconId) return;

    // 다른 비콘 검증 중이면 취소 후 새로 시작
    if (_currentState.phase == BeaconPhase.verifying) {
      _cancelVerification(reason: '다른 비콘 감지');
    }

    // confirmed 상태면 짧은 쿨다운 (중복 방지)
    if (_currentState.phase == BeaconPhase.confirmed) return;

    print('🟡 [1단계] 근접 감지! 비콘[$beaconId] RSSI: $rssi dBm → 검증 시작');

    _emitState(BeaconState(
      phase: BeaconPhase.verifying,
      detectedBeaconId: beaconId,
      rssi: rssi,
      verifyProgress: 0.0,
    ));

    _startVerificationTimer(beaconId, rssi);
  }

  // ── 단계 2: 의도 검증 (Verification) ─────────────────────────────────────

  void _startVerificationTimer(String beaconId, int rssi) {
    _verifyStartTime = DateTime.now();
    _verifyTimer?.cancel();
    _progressTimer?.cancel();

    // 2초 후 확정
    _verifyTimer = Timer(
      const Duration(milliseconds: _verifyDurationMs),
      () => _onConfirmed(beaconId),
    );

    // 16ms마다 progress 업데이트 (60fps)
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (_verifyStartTime == null) return;
        final elapsed = DateTime.now().difference(_verifyStartTime!).inMilliseconds;
        final progress = (elapsed / _verifyDurationMs).clamp(0.0, 1.0);

        _emitState(BeaconState(
          phase: BeaconPhase.verifying,
          detectedBeaconId: beaconId,
          rssi: _currentState.rssi,
          verifyProgress: progress,
        ));
      },
    );
  }

  void _cancelVerification({required String reason}) {
    _verifyTimer?.cancel();
    _progressTimer?.cancel();
    _verifyStartTime = null;
    print('🔴 검증 취소: $reason');
    _emitState(BeaconState.idle);

    // 취소 진동 (짧게 1회)
    HapticFeedback.lightImpact();
  }

  // ── 단계 3: 확정 및 보상 (Confirmation) ───────────────────────────────────

  Future<void> _onConfirmed(String beaconId) async {
    _verifyTimer?.cancel();
    _progressTimer?.cancel();
    _verifyStartTime = null;

    print('✅ [3단계] 복용 확정! 비콘[$beaconId]');

    _emitState(BeaconState(
      phase: BeaconPhase.confirmed,
      detectedBeaconId: beaconId,
      rssi: _currentState.rssi,
      verifyProgress: 1.0,
      confirmedMedicineId: beaconId,
    ));

    // ⭐ 햅틱 피드백: 성공 진동 패턴 (강 → 중 → 강)
    await _successHaptic();

    // 콜백 호출 → main.dart에서 복용 기록
    onMedicineTaken?.call(beaconId);

    // 3초 후 idle 복귀 (연속 중복 감지 방지)
    Timer(const Duration(seconds: 3), () {
      if (_currentState.phase == BeaconPhase.confirmed) {
        _emitState(BeaconState.idle);
        // RSSI 히스토리 초기화 (쿨다운)
        _rssiHistory.remove(beaconId);
      }
    });
  }

  // ── 햅틱 피드백 ────────────────────────────────────────────────────────────

  Future<void> _successHaptic() async {
    // 강 → 0.1초 → 중 → 0.1초 → 강
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.heavyImpact();
  }

  // ── RSSI 스무딩 ────────────────────────────────────────────────────────────

  int _smoothRssi(String deviceId, int rawRssi) {
    final history = _rssiHistory.putIfAbsent(deviceId, () => []);
    history.add(rawRssi);
    if (history.length > _rssiSmoothWindow) {
      history.removeAt(0);
    }
    return (history.reduce((a, b) => a + b) / history.length).round();
  }

  // ── 상태 emit ──────────────────────────────────────────────────────────────

  void _emitState(BeaconState state) {
    _currentState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}