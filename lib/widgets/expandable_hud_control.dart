import 'dart:async';

import 'package:flutter/material.dart';

/// A compact home control that reveals its label before allowing an action.
class ExpandableHudControl extends StatefulWidget {
  const ExpandableHudControl({
    super.key,
    required this.controlId,
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.semanticName,
    this.onPressed,
    this.expandedAction,
  });

  final String controlId;
  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final String semanticName;
  final VoidCallback? onPressed;
  final Widget? expandedAction;

  @override
  State<ExpandableHudControl> createState() => _ExpandableHudControlState();
}

class _ExpandableHudControlState extends State<ExpandableHudControl> {
  static const _autoCollapseDelay = Duration(seconds: 3);
  bool _expanded = false;
  Timer? _collapseTimer;

  void _restartCollapseTimer() {
    _collapseTimer?.cancel();
    if (!_expanded) return;
    _collapseTimer = Timer(_autoCollapseDelay, _collapse);
  }

  void _collapse() {
    _collapseTimer?.cancel();
    if (mounted && _expanded) setState(() => _expanded = false);
  }

  void _activate() {
    if (!_expanded) {
      setState(() => _expanded = true);
      _restartCollapseTimer();
    } else if (widget.onPressed != null) {
      _restartCollapseTimer();
      widget.onPressed!();
    } else {
      _collapse();
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _collapseTimer?.cancel(),
      onPointerUp: (_) => _restartCollapseTimer(),
      onPointerCancel: (_) => _restartCollapseTimer(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Material(
          color: const Color(0xDCE7F5FF),
          elevation: 3,
          shadowColor: const Color(0x33305F76),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xBFFFFFFF)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: _expanded
                        ? widget.detail
                        : '展開${widget.semanticName}：${widget.label}',
                    child: InkWell(
                      key: ValueKey('${widget.controlId}-toggle'),
                      onTap: _activate,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Icon(widget.icon, color: widget.color, size: 23),
                      ),
                    ),
                  ),
                  if (_expanded) ...[
                    Flexible(
                      child: Tooltip(
                        message: widget.detail,
                        child: InkWell(
                          key: ValueKey('${widget.controlId}-action'),
                          onTap: _activate,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                widget.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('${widget.controlId}-collapse'),
                      tooltip: '收合${widget.semanticName}',
                      onPressed: _collapse,
                      icon: Icon(
                        Icons.close_rounded,
                        color: widget.color,
                        size: 18,
                      ),
                    ),
                  ],
                ],
              ),
              if (_expanded && widget.expandedAction != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 8, 4),
                  child: widget.expandedAction!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
