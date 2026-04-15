import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

class NotificationService {
  /// 알림 초기화
  static Future<void> initialize() async {
    print('🔔 Alarm 패키지 초기화 시작');
    await Alarm.init();
    print('✅ Alarm 패키지 초기화 완료\n');
  }

  /// 약 알람 예약
  static Future<void> scheduleMedicineAlarm({
    required int id,
    required String medicineName,
    required TimeOfDay time,
    required List<int> selectedDays,
  }) async {
    print('\n🔔 === 알람 예약 시작 (Alarm 패키지) ===');
    print('   ID: $id');
    print('   약 이름: $medicineName');
    print('   시간: ${time.hour}:${time.minute}');
    print('   요일: $selectedDays');

    final now = DateTime.now();
    print('   현재 시간: ${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}');

    for (int dayIndex in selectedDays) {
      print('\n   📅 요일 $dayIndex 처리 중...');

      // 다음 해당 요일 계산
      DateTime scheduledDate = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      // 오늘이고 이미 지났으면 내일
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(Duration(days: 1));
      }

      // 해당 요일 찾기
      while (scheduledDate.weekday != dayIndex + 1) {
        scheduledDate = scheduledDate.add(Duration(days: 1));
      }

      int uniqueId = id * 10 + dayIndex;

      print('      - 예약 시간: ${scheduledDate.year}-${scheduledDate.month}-${scheduledDate.day} ${scheduledDate.hour}:${scheduledDate.minute}');
      print('      - 고유 ID: $uniqueId');

      try {
        final alarmSettings = AlarmSettings(
          id: uniqueId,
          dateTime: scheduledDate,
          assetAudioPath: 'assets/blank.mp3',  // ⚠️ 무음 파일 필요
          loopAudio: false,
          vibrate: true,  // 진동 끄기
          volumeSettings: const VolumeSettings.fixed(
            volume: 0.0,
            volumeEnforced: true,
          ),
          notificationSettings: NotificationSettings(
            title: '💊 약 먹을 시간이에요!',
            body: '$medicineName을(를) 복용하세요',
            stopButton: '확인',
          ),
        );

        await Alarm.set(alarmSettings: alarmSettings);
        print('      ✅ 알람 예약 성공 (ID: $uniqueId)');
      } catch (e) {
        print('      ❌ 알람 예약 실패: $e');
      }
    }

    print('🔔 === 알람 예약 완료 ===\n');
  }

  /// 테스트: 30초 후 알람
  static Future<void> test30SecondsAlarm() async {
    print('\n⏰ === 30초 후 알람 테스트 (Alarm 패키지) ===');

    final scheduledDate = DateTime.now().add(Duration(seconds: 30));
    print('현재: ${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}');
    print('예약: ${scheduledDate.hour}:${scheduledDate.minute}:${scheduledDate.second}');

    try {
      final alarmSettings = AlarmSettings(
        id: 99999,
        dateTime: scheduledDate,
        assetAudioPath: 'assets/blank.mp3',
        loopAudio: true,
        vibrate: false,
        volumeSettings: VolumeSettings.fixed(
          volume: 0.0,
          volumeEnforced: true,
        ),
        notificationSettings: NotificationSettings(
          title: '🎉 30초 테스트',
          body: 'Alarm 패키지 테스트 성공!',
          stopButton: '확인',
        ),
      );

      await Alarm.set(alarmSettings: alarmSettings);
      print('✅ 30초 후 알람 예약 완료!');
      print('💡 앱을 닫아도 됩니다!\n');
    } catch (e) {
      print('❌ 예약 실패: $e\n');
    }
  }

  /// 알람 취소
  static Future<void> cancelAlarm(int id) async {
    for (int i = 0; i < 7; i++) {
      await Alarm.stop(id * 10 + i);
    }
  }

  /// 모든 알람 삭제
  static Future<void> cancelAllAlarms() async {
    print('\n🗑️ === 모든 알람 삭제 ===');
    await Alarm.stopAll();
    print('✅ 모든 알람 삭제 완료\n');
  }
}
