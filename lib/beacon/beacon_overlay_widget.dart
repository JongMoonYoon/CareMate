// lib/widgets/beacon_overlay_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import './beacon_service.dart';

/// 홈화면 등 어디서든 삽입 가능한 비콘 상태 위젯
class BeaconOverlayWidget extends StatelessWidget {
  const BeaconOverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BeaconState>(
      stream: BeaconService.instance.stateStream,
      initialData: BeaconState.idle,
      builder: (context, snapshot) {
        final state = snapshot.data ?? BeaconState.idle;

        // idle 상태는 숨김 (화면 공간 낭비 없이)
        if (state.phase == BeaconPhase.idle) {
          return _IdleHint();
        }

        if (state.phase == BeaconPhase.verifying) {
          return _VerifyingCard(state: state);
        }

        return _ConfirmedCard(state: state);
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// idle: 작은 힌트 텍스트
// ────────────────────────────────────────────────────────────────────────────
class _IdleHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth_searching,
              color: Colors.grey.shade400, size: 22),
          const SizedBox(width: 10),
          Text(
            '약통에 휴대폰을 가까이 대면 자동으로 복용 기록돼요',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// verifying: 원형 프로그레스 + 애니메이션
// ────────────────────────────────────────────────────────────────────────────
class _VerifyingCard extends StatelessWidget {
  final BeaconState state;
  const _VerifyingCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 원형 프로그레스
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 배경 원
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 6,
                    color: Colors.blue.shade100,
                  ),
                ),
                // 진행 원
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: state.verifyProgress,
                    strokeWidth: 6,
                    color: Colors.blue,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                // 아이콘
                Icon(
                  Icons.bluetooth_connected,
                  color: Colors.blue.shade600,
                  size: 28,
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📲 약통 근처에 있어요!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '조금만 더 가까이 유지해주세요...',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade400,
                  ),
                ),
                const SizedBox(height: 8),
                // 선형 프로그레스 바
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: state.verifyProgress,
                    minHeight: 6,
                    backgroundColor: Colors.blue.shade100,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${((1 - state.verifyProgress) * 2).toStringAsFixed(1)}초 남음',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade300,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// confirmed: 성공 카드
// ────────────────────────────────────────────────────────────────────────────
class _ConfirmedCard extends StatelessWidget {
  final BeaconState state;
  const _ConfirmedCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // 체크 아이콘 (펄스 애니메이션 적용)
          _PulseIcon(),

          const SizedBox(width: 16),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✅ 복용 확인!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '약을 먹은 것으로 기록됐어요 🌱',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }
}