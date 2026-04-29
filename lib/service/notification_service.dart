import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static Future<void> initialize() async {
    print('🔔 Alarm 패키지 초기화 시작');
    await Alarm.init();
    print('✅ Alarm 패키지 초기화 완료\n');
  }

  static Future<void> scheduleMedicineAlarm({
    required int id,
    required String medicineName,
    required TimeOfDay time,
    required List<int> selectedDays,
  }) async {
    print('\n🔔 === 알람 예약 시작 ===');
    print('   약 이름: $medicineName');
    print('   시간: ${time.hour}:${time.minute}');

    final now = DateTime.now();

    for (int dayIndex in selectedDays) {
      DateTime scheduledDate = DateTime(
        now.year, now.month, now.day,
        time.hour, time.minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      while (scheduledDate.weekday != dayIndex + 1) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      int uniqueId = id * 10 + dayIndex;

      try {
        final alarmSettings = AlarmSettings(
          id: uniqueId,
          dateTime: scheduledDate,
          assetAudioPath: 'assets/blank.mp3',
          loopAudio: false,
          vibrate: true,
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
        print('✅ 알람 예약 성공 (ID: $uniqueId)');
      } catch (e) {
        print('❌ 알람 예약 실패: $e');
      }
    }
  }

  static Future<void> cancelAlarm(int id) async {
    for (int i = 0; i < 7; i++) {
      await Alarm.stop(id * 10 + i);
    }
  }

  static Future<void> cancelAllAlarms() async {
    await Alarm.stopAll();
    print('✅ 모든 알람 삭제 완료');
  }
}