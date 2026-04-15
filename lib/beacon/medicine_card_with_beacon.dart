// main.dart의 약 카드 부분 (medicines.map(...) 안) 교체
// 기존 약 카드에 비콘 연결 버튼을 추가한 버전

// ── import 추가 ───────────────────────────────────────────────────────────────
import 'widgets/beacon_quick_pair_sheet.dart';

// ── 약 카드 (기존 코드에서 Container 부분 교체) ───────────────────────────────
...GlobalMedicineList.medicines.map((med) => Container(
  margin: const EdgeInsets.only(bottom: 10),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.green.shade50,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Column(
    children: [
      Row(
        children: [
          const Icon(Icons.medication, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  '${med.alarmTime.hour.toString().padLeft(2, '0')}:'
                  '${med.alarmTime.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // 삭제 버튼 (기존 유지)
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async { /* 기존 삭제 코드 */ },
          ),
        ],
      ),

      // ⭐ 비콘 연결 상태 + 버튼
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () async {
          await BeaconQuickPairSheet.show(
            context,
            medicine: med,
            onPaired: () {
              // 비콘 서비스 재시작 (새 ID 반영)
              BeaconService.instance.stop();
              _startBeaconService();
              setState(() {});
            },
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: med.beaconId.isNotEmpty
                ? Colors.blue.shade50
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: med.beaconId.isNotEmpty
                  ? Colors.blue.shade200
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                med.beaconId.isNotEmpty
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                size: 15,
                color: med.beaconId.isNotEmpty
                    ? Colors.blue
                    : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                med.beaconId.isNotEmpty
                    ? '비콘 연결됨  (탭하면 변경)'
                    : '비콘 연결하기  →',
                style: TextStyle(
                  fontSize: 12,
                  color: med.beaconId.isNotEmpty
                      ? Colors.blue.shade600
                      : Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
)).toList(),