import 'package:flutter/material.dart';

class CameraSideToolAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  const CameraSideToolAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });
}

class CameraSideToolBar extends StatelessWidget {
  final List<CameraSideToolAction> actions;
  final double topInset;
  final double horizontalInset;
  final bool alignLeft;

  const CameraSideToolBar({
    super.key,
    required this.actions,
    this.topInset = 140,
    this.horizontalInset = 10,
    this.alignLeft = false,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: Align(
        alignment: alignLeft ? Alignment.topLeft : Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(
            top: topInset,
            left: alignLeft ? horizontalInset : 0,
            right: alignLeft ? 0 : horizontalInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                _ToolButton(action: actions[i]),
                if (i < actions.length - 1) const SizedBox(height: 5),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final CameraSideToolAction action;

  const _ToolButton({required this.action});

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10367D);
    final bg = action.active
        ? const Color(0xFFBFDBFE).withValues(alpha: 0.88)
        : const Color(0xFFBFDBFE).withValues(alpha: 0.18);
    final fg = action.active
        ? const Color(0xFF10367D)
        : Colors.white.withValues(alpha: 0.88);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 46,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: action.active
                  ? const Color(0xFF93C5FD)
                  : const Color(0xFFBFDBFE).withValues(alpha: 0.22),
              width: action.active ? 0.9 : 0.7,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 15, color: fg),
              const SizedBox(height: 2),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
