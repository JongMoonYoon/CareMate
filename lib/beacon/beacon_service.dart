// lib/beacon/beacon_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum BeaconPhase {
  idle,
  verifying,
  confirmed,
}

class BeaconState {
  final BeaconPhase phase;
  final String? detectedBeaconId;
  final int rssi;
  final double verifyProgress;
  final String? confirmedMedicineId;

  const BeaconState({
    required this.phase,
    this.detectedBeaconId,
    this.rssi = 0,
    this.verifyProgress = 0.0,
    this.confirmedMedicineId,
  });

  static const idle = BeaconState(phase: BeaconPhase.idle);
}

class BeaconService {
  BeaconService._();
  static final BeaconService instance = BeaconService._();

  // ── 설정 값 ──────────────────────────────────────────────────────────────

  // [수정 3] 히스테리시스: 진입과 취소 임계값을 분리
  // 진입: -40 이상일 때만 verifying 시작
  // 취소: -50 미만으로 떨어질 때만 verifying 취소
  // → -40~-50 사이에서 신호가 왔다갔다 해도 verifying이 끊기지 않음
  static const int _rssiEnterThreshold  = -40;  // verifying 진입 기준
  static const int _rssiCancelThreshold = -50;  // verifying 취소 기준

  static const int _verifyDurationMs     = 2000;

  // [수정 3] 스무딩 샘플 수 1 → 4
  // 최근 4개 RSSI 값의 평균을 사용 → 순간적인 노이즈에 덜 흔들림
  // 단점: 처음 감지까지 샘플이 쌓이는 데 약간의 지연이 생길 수 있음
  static const int _rssiSmoothWindow     = 3;

  // [수정 1] 스캔 타임아웃 > 재시작 간격 → 끊김 없이 항상 스캔 중
  static const int _scanTimeoutSec       = 10;
  static const int _scanRestartIntervalMs = 4000;

  // [수정 2] 확정 후 재감지 방지 쿨다운 (30초)
  static const int _cooldownSec = 30;

  // ── 내부 상태 ────────────────────────────────────────────────────────────
  final _stateController = StreamController<BeaconState>.broadcast();
  Stream<BeaconState> get stateStream => _stateController.stream;
  BeaconState _currentState = BeaconState.idle;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _scanRestartTimer;
  Timer? _verifyTimer;
  Timer? _progressTimer;
  DateTime? _verifyStartTime;

  final Map<String, List<int>> _rssiHistory = {};
  final Set<String> _watchedBeaconIds = {};

  // [수정 2] 쿨다운 종료 시각 (비콘 ID별)
  final Map<String, DateTime> _cooldownUntil = {};

  Function(String beaconId)? onMedicineTaken;

  // ── 시작 / 종료 ──────────────────────────────────────────────────────────

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

    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      print('❌ 이 기기는 BLE를 지원하지 않습니다.');
      return;
    }

    print('🔵 비콘 서비스 시작 | 감시 비콘: $_watchedBeaconIds');
    _startScan();
  }

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

  // ── 스캔 관리 ────────────────────────────────────────────────────────────

  void _startScan() {
    _scanSubscription?.cancel();

    // [수정 1] timeout을 10초로 늘려 재시작 간격(4초)보다 항상 길게 유지
    // → 스캔이 끊기는 구간이 생기지 않음
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: _scanTimeoutSec),
      continuousUpdates: true,
      androidUsesFineLocation: true,
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (e) => print('❌ 스캔 에러: $e'),
    );

    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer.periodic(
      const Duration(milliseconds: _scanRestartIntervalMs),
          (_) => _startScan(),
    );
  }

  // ── 스캔 결과 처리 ────────────────────────────────────────────────────────

  void _onScanResults(List<ScanResult> results) {
    for (final result in results) {
      final deviceId = result.device.remoteId.str;
      if (!_watchedBeaconIds.contains(deviceId)) continue;

      if (result.rssi >= -40) {
        _onApproach(deviceId, result.rssi);
        return;
      }

      final smoothedRssi = _smoothRssi(deviceId, result.rssi);
      print('📡 비콘[$deviceId] RSSI: ${result.rssi} → 평균: $smoothedRssi');

      // [수정 3] 히스테리시스: 진입(-40)과 취소(-50) 임계값 분리
      // -40~-50 사이 구간에서 신호가 출렁여도 verifying 유지됨
      if (smoothedRssi >= _rssiEnterThreshold) {
        _onApproach(deviceId, smoothedRssi);
      } else if (smoothedRssi < _rssiCancelThreshold) {
        if (_currentState.detectedBeaconId == deviceId &&
            _currentState.phase == BeaconPhase.verifying) {
          _cancelVerification(reason: '신호 약해짐 ($smoothedRssi dBm)');
        }
      }
    }
  }

  // ── 단계 1: 근접 감지 ────────────────────────────────────────────────────

  void _onApproach(String beaconId, int rssi) {
    // 이미 이 비콘 검증 중이면 무시
    if (_currentState.phase == BeaconPhase.verifying &&
        _currentState.detectedBeaconId == beaconId) return;

    // 다른 비콘 검증 중이면 취소
    if (_currentState.phase == BeaconPhase.verifying) {
      _cancelVerification(reason: '다른 비콘 감지');
    }

    // confirmed 상태면 무시 (UI에 팝업 떠 있는 중)
    if (_currentState.phase == BeaconPhase.confirmed) return;

    // [수정 2] 쿨다운 중이면 재감지 차단
    final cooldown = _cooldownUntil[beaconId];
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      final remaining = cooldown.difference(DateTime.now()).inSeconds;
      print('⏳ 쿨다운 중 [$beaconId] $remaining초 남음 → 재감지 무시');
      return;
    }

    print('🟡 [1단계] 근접 감지! 비콘[$beaconId] RSSI: $rssi dBm → 검증 시작');

    _emitState(BeaconState(
      phase: BeaconPhase.verifying,
      detectedBeaconId: beaconId,
      rssi: rssi,
      verifyProgress: 0.0,
    ));

    _startVerificationTimer(beaconId, rssi);
  }

  // ── 단계 2: 검증 타이머 ──────────────────────────────────────────────────

  void _startVerificationTimer(String beaconId, int rssi) {
    _verifyStartTime = DateTime.now();
    _verifyTimer?.cancel();
    _progressTimer?.cancel();

    _verifyTimer = Timer(
      const Duration(milliseconds: _verifyDurationMs),
          () => _onConfirmed(beaconId),
    );

    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 16),
          (_) {
        if (_verifyStartTime == null) return;
        final elapsed =
            DateTime.now().difference(_verifyStartTime!).inMilliseconds;
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
    HapticFeedback.lightImpact();
  }

  // ── 단계 3: 확정 ─────────────────────────────────────────────────────────

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

    await _successHaptic();
    onMedicineTaken?.call(beaconId);

    // [수정 2] 확정 즉시 쿨다운 시작 → idle 복귀 후에도 30초간 재감지 차단
    _cooldownUntil[beaconId] =
        DateTime.now().add(const Duration(seconds: _cooldownSec));
    print('⏳ 쿨다운 시작 [$beaconId] ${_cooldownSec}초');

    // 3초 후 UI만 idle로 복귀 (쿨다운은 계속 유지)
    Timer(const Duration(seconds: 3), () {
      if (_currentState.phase == BeaconPhase.confirmed) {
        _emitState(BeaconState.idle);
        _rssiHistory.remove(beaconId);
      }
    });
  }

  // ── 햅틱 피드백 ──────────────────────────────────────────────────────────

  Future<void> _successHaptic() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.heavyImpact();
  }

  // ── RSSI 스무딩 ───────────────────────────────────────────────────────────

  int _smoothRssi(String deviceId, int rawRssi) {
    final history = _rssiHistory.putIfAbsent(deviceId, () => []);
    history.add(rawRssi);
    if (history.length > _rssiSmoothWindow) history.removeAt(0);
    return (history.reduce((a, b) => a + b) / history.length).round();
  }

  // ── 상태 emit ────────────────────────────────────────────────────────────

  void _emitState(BeaconState state) {
    _currentState = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}