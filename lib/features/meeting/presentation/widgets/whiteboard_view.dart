import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/whiteboard_service.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../providers/meeting_services_provider.dart';

class WhiteboardView extends ConsumerStatefulWidget {
  final String meetingId;
  const WhiteboardView({super.key, required this.meetingId});

  @override
  ConsumerState<WhiteboardView> createState() => _WhiteboardViewState();
}

class _WhiteboardViewState extends ConsumerState<WhiteboardView> {
  Color _currentColor = Colors.red;
  final double _currentStrokeWidth = 3.0;
  DrawAction? _currentAction;

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    final x = details.localPosition.dx / constraints.maxWidth;
    final y = details.localPosition.dy / constraints.maxHeight;

    final action = DrawAction(
      x: x,
      y: y,
      color: '#${_currentColor.r.toInt().toRadixString(16).padLeft(2, '0')}${_currentColor.g.toInt().toRadixString(16).padLeft(2, '0')}${_currentColor.b.toInt().toRadixString(16).padLeft(2, '0')}',
      strokeWidth: _currentStrokeWidth,
      type: 'start',
    );
    _currentAction = action;
    ref.read(whiteboardServiceProvider(widget.meetingId).notifier).sendDrawAction(action);
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final x = details.localPosition.dx / constraints.maxWidth;
    final y = details.localPosition.dy / constraints.maxHeight;

    final action = DrawAction(
      x: x,
      y: y,
      color: '#${(_currentColor.r * 255).toInt().toRadixString(16).padLeft(2, '0')}${(_currentColor.g * 255).toInt().toRadixString(16).padLeft(2, '0')}${(_currentColor.b * 255).toInt().toRadixString(16).padLeft(2, '0')}',
      strokeWidth: _currentStrokeWidth,
      type: 'move',
    );
    ref.read(whiteboardServiceProvider(widget.meetingId).notifier).sendDrawAction(action);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentAction != null) {
      final endAction = DrawAction(
        x: _currentAction!.x,
        y: _currentAction!.y,
        color: _currentAction!.color,
        strokeWidth: _currentAction!.strokeWidth,
        type: 'end',
      );
      ref.read(whiteboardServiceProvider(widget.meetingId).notifier).sendDrawAction(endAction);
      _currentAction = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardServiceProvider(widget.meetingId));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[900],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _colorOption(Colors.red),
                  _colorOption(MizdahTheme.primaryBlue),
                  _colorOption(Colors.black),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.white),
                onPressed: () => ref.read(whiteboardServiceProvider(widget.meetingId).notifier).clearBoard(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (details) => _onPanStart(details, constraints),
                  onPanUpdate: (details) => _onPanUpdate(details, constraints),
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _WhiteboardPainter(actions: state.actions),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _colorOption(Color color) {
    return GestureDetector(
      onTap: () => setState(() => _currentColor = color),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: _currentColor == color ? Border.all(color: Colors.white, width: 2) : null,
        ),
      ),
    );
  }
}

class _WhiteboardPainter extends CustomPainter {
  final List<DrawAction> actions;

  _WhiteboardPainter({required this.actions});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < actions.length - 1; i++) {
      final current = actions[i];
      final next = actions[i + 1];

      if (next.type != 'start' && current.type != 'end') {
        final paint = Paint()
          ..color = _colorFromHex(current.color)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = current.strokeWidth;
        
        final p1 = Offset(current.x * size.width, current.y * size.height);
        final p2 = Offset(next.x * size.width, next.y * size.height);

        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) {
    return oldDelegate.actions.length != actions.length;
  }

  Color _colorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }
    return Color(int.parse(hexColor, radix: 16));
  }
}
