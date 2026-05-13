import 'package:flutter/material.dart';

class CameraSideToolAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;
  final String? secondaryLabel;

  const CameraSideToolAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
    this.secondaryLabel,
  });
}

class CameraSideToolBar extends StatelessWidget {
  final List<CameraSideToolAction> actions;

  const CameraSideToolBar({
    super.key,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            CameraToolButton(action: actions[i]),
            if (i < actions.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class CameraToolButton extends StatelessWidget {
  final CameraSideToolAction action;
  static const double _buttonSize = 38;
  static const double _slotHeight = 52;

  const CameraToolButton({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final activeTint = action.activeColor ?? const Color(0xFFBFDBFE);
    final bg = action.active
        ? activeTint.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.10);
    final borderColor = action.active
        ? activeTint.withValues(alpha: 0.70)
        : Colors.white.withValues(alpha: 0.22);
    final fg = action.active ? Colors.white : Colors.white.withValues(alpha: 0.92);
    final secondaryLabel = action.secondaryLabel;

    return Tooltip(
      message: action.label,
      child: Semantics(
        button: true,
        label: action.label,
        selected: action.active,
        child: SizedBox(
          width: _buttonSize,
          height: _slotHeight,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                clipBehavior: Clip.hardEdge,
                child: InkWell(
                  onTap: action.onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: _buttonSize,
                    height: _buttonSize,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: borderColor,
                        width: action.active ? 1.1 : 0.9,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x100F172A),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(action.icon, size: 20, color: fg),
                  ),
                ),
              ),
              if (secondaryLabel != null)
                Positioned(
                  top: 41,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      secondaryLabel,
                      style: TextStyle(
                        color: fg,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
