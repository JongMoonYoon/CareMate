// lib/beacon/background_beacon_service.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 알림 플러그인 (백그라운드 isolate에서도 사용)
// ─────────────────────────────────────────────────────────────────────────────
final _notificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings),
  );
}

/// 화면을 깨우는 Full-screen Intent 알림 발사
Future<void> _showFullScreenNotification(String beaconId) async {
  const androidDetails = AndroidNotificationDetails(
    'beacon_confirm_channel',
    '복약 확인',
    channelDescription: '비콘 감지 시 복약 확인 알림',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true, // ⭐ 핵심: 알림 대신 화면을 즉시 띄우라는 명령
    category: AndroidNotificationCategory.call, // ⭐ 카테고리를 '알람' 대신 '전화'로 변경 (우선순위 상승)
    audioAttributesUsage: AudioAttributesUsage.alarm,

    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        'action_taken',
        '지금 복용 완료',
        showsUserInterface: true, // 누르면 앱이 즉시 실행됨
      ),
    ],
  );

  await _notificationsPlugin.show(
    9001,
    '약 드실 시간이에요!',
    '약통 근처에 계세요. 약을 드셨나요?',
    const NotificationDetails(android: androidDetails),
    payload: 'beacon_confirmed:$beaconId',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 1) Foreground Task Handler (백그라운드 isolate에서 실행)
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_BeaconTaskHandler());
}

class _BeaconTaskHandler extends TaskHandler {
  static const int _rssiEnterThreshold  = -40;
  static const int _rssiCancelThreshold = -50;
  static const int _verifyDurationMs    = 2000;
  static const int _cooldownSec         = 30;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription? _isScanSub;
  Timer? _verifyTimer;
  Timer? _restartTimer;
  DateTime? _lastScanStart;

  String? _verifyingBeaconId;
  Set<String> _watchedIds = {};
  final Map<String, DateTime> _cooldownUntil = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🟢 [BG] 시작');
    await _initNotifications();

    final data = await FlutterForegroundTask.getData<String>(key: 'watchedIds');
    if (data != null && data.isNotEmpty) {
      _watchedIds = data.split(',').toSet();
    }
    print('🔵 [BG] 감시 비콘: $_watchedIds');
    _startScan();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    final scanning = await FlutterBluePlus.isScanning.first;
    if (!scanning) {
      print('🔄 [BG] 스캔 꺼짐 → 재시작');
      _doStartScan();
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is String && data.startsWith('watchedIds:')) {
      final ids = data.replaceFirst('watchedIds:', '');
      _watchedIds = ids.isNotEmpty ? ids.split(',').toSet() : {};
      print('🔄 [BG] watchedIds 업데이트: $_watchedIds');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _scanSub?.cancel();
    _isScanSub?.cancel();
    _verifyTimer?.cancel();
    _restartTimer?.cancel();
    FlutterBluePlus.stopScan();
    print('🔴 [BG] 종료');
  }

  void _startScan() {
    _scanSub?.cancel();
    _isScanSub?.cancel();

    _scanSub = FlutterBluePlus.scanResults.listen(_onResults);

    _isScanSub = FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning) {
        final elapsed = _lastScanStart != null
            ? DateTime.now().difference(_lastScanStart!).inSeconds
            : 15;
        final wait = elapsed < 15 ? 15 - elapsed : 0;
        _restartTimer?.cancel();
        _restartTimer = Timer(Duration(seconds: wait), _doStartScan);
      }
    });

    _doStartScan();
  }

  void _doStartScan() {
    _lastScanStart = DateTime.now();
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      continuousUpdates: true,
      androidUsesFineLocation: true,
    ).catchError((e) => print('❌ [BG] 스캔 에러: $e'));
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final id = r.device.remoteId.str;
      if (!_watchedIds.contains(id)) continue;

      final rssi = r.rssi;
      if (rssi >= _rssiEnterThreshold) {
        _onApproach(id);
      } else if (rssi < _rssiCancelThreshold && _verifyingBeaconId == id) {
        _cancelVerify();
      }
    }
  }

  void _onApproach(String id) {
    if (_verifyingBeaconId == id) return;
    if (_verifyingBeaconId != null) _cancelVerify();

    final cooldown = _cooldownUntil[id];
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return;

    print('🟡 [BG] 검증 시작: $id');
    _verifyingBeaconId = id;

    _verifyTimer = Timer(
      const Duration(milliseconds: _verifyDurationMs),
          () => _onConfirmed(id),
    );
  }

  void _cancelVerify() {
    _verifyTimer?.cancel();
    _verifyingBeaconId = null;
  }

  Future<void> _onConfirmed(String id) async {
    _verifyingBeaconId = null;
    _cooldownUntil[id] = DateTime.now().add(const Duration(seconds: _cooldownSec));
    print('✅ [BG] 복용 확정: $id');

    // ① 화면 켜기 + 잠금화면 위 알림 (삼성 알람과 동일한 방식)
    await _showFullScreenNotification(id);

    // ② 앱이 포그라운드일 때 UI 업데이트용
    FlutterForegroundTask.sendDataToMain({'event': 'confirmed', 'beaconId': id});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2) 메인 isolate에서 호출하는 서비스 관리 클래스
// ─────────────────────────────────────────────────────────────────────────────
class BackgroundBeaconService {
  BackgroundBeaconService._();
  static final BackgroundBeaconService instance = BackgroundBeaconService._();

  Function(String beaconId)? onConfirmed;

  static void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'beacon_bg_channel',
        channelName: '복약 감지 실행 중',
        channelDescription: '약통 근처에 오면 자동으로 복약을 기록해요',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  Future<void> start({
    required Set<String> watchedIds,
    required Function(String beaconId) onTaken,
  }) async {
    onConfirmed = onTaken;

    await FlutterForegroundTask.saveData(
      key: 'watchedIds',
      value: watchedIds.join(','),
    );

    FlutterForegroundTask.addTaskDataCallback(_onDataFromBackground);

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask('watchedIds:${watchedIds.join(',')}');
      return;
    }

    FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: '하루약속 실행 중',
      notificationText: '약통에 가까이 대면 자동으로 복약이 기록돼요',
      callback: startCallback,
    );
  }

  Future<void> stop() async {
    FlutterForegroundTask.removeTaskDataCallback(_onDataFromBackground);
    await FlutterForegroundTask.stopService();
  }

  void _onDataFromBackground(Object data) {
    if (data is Map<String, dynamic>) {
      final event = data['event'] as String?;
      final beaconId = data['beaconId'] as String?;
      if (event == 'confirmed' && beaconId != null) {
        onConfirmed?.call(beaconId);
      }
    }
  }
}