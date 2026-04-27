import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/whiteboard_service.dart';
import '../../providers/meeting_services_provider.dart';

/// Brush kinds the toolbar surfaces. Eraser is implemented as a fat
/// background-coloured stroke, so it travels through the existing
/// `draw-move` payload without any backend changes.
enum _Tool { pencil, eraser, blur }

/// Hex of the canvas background — eraser strokes paint this colour
/// over existing ink.
const String _kCanvasHex = '#FFFFFF';

class WhiteboardView extends ConsumerStatefulWidget {
  final String meetingId;
  const WhiteboardView({super.key, required this.meetingId});

  @override
  ConsumerState<WhiteboardView> createState() => _WhiteboardViewState();
}

class _WhiteboardViewState extends ConsumerState<WhiteboardView> {
  Color _currentColor = Colors.red;
  double _currentStrokeWidth = 4.0;
  _Tool _currentTool = _Tool.pencil;
  DrawAction? _currentAction;

  /// Full palette shown inline. Tap "more" to open the extended sheet.
  static const List<Color> _palette = [
    Colors.black,
    Colors.white, // doubles as a "white pencil" (rare but useful)
    Colors.red,
    Color(0xFFEF6C00), // orange
    Colors.amber,
    Color(0xFFFBC02D), // yellow
    Color(0xFF43A047), // green
    Color(0xFF00ACC1), // cyan
    Color(0xFF1E88E5), // blue
    Color(0xFF5E35B1), // deep purple
    Color(0xFFD81B60), // pink
    Color(0xFF6D4C41), // brown
  ];

  // ---------- Helpers ----------

  String _hexFor(Color c) {
    String h(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${h(c.r)}${h(c.g)}${h(c.b)}';
  }

  /// What we actually emit on each gesture. Eraser overrides the
  /// colour to canvas-white and fattens the stroke; blur tags the
  /// `tool` field so the painter switches to a blur mask filter.
  ({String color, double width, String tool}) _resolveBrush() {
    switch (_currentTool) {
      case _Tool.eraser:
        // Eraser: minimum 14 so it actually wipes thin strokes,
        // but respects user-picked width above that.
        final w = _currentStrokeWidth < 14 ? 14.0 : _currentStrokeWidth;
        return (color: _kCanvasHex, width: w, tool: 'eraser');
      case _Tool.blur:
        return (
          color: _hexFor(_currentColor),
          width: _currentStrokeWidth,
          tool: 'blur',
        );
      case _Tool.pencil:
        return (
          color: _hexFor(_currentColor),
          width: _currentStrokeWidth,
          tool: 'pencil',
        );
    }
  }

  // ---------- Drag handlers ----------

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    final brush = _resolveBrush();
    final action = DrawAction(
      x: details.localPosition.dx / constraints.maxWidth,
      y: details.localPosition.dy / constraints.maxHeight,
      color: brush.color,
      strokeWidth: brush.width,
      type: 'start',
      tool: brush.tool,
    );
    _currentAction = action;
    ref
        .read(whiteboardServiceProvider(widget.meetingId).notifier)
        .sendDrawAction(action);
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final brush = _resolveBrush();
    final action = DrawAction(
      x: details.localPosition.dx / constraints.maxWidth,
      y: details.localPosition.dy / constraints.maxHeight,
      color: brush.color,
      strokeWidth: brush.width,
      type: 'move',
      tool: brush.tool,
    );
    ref
        .read(whiteboardServiceProvider(widget.meetingId).notifier)
        .sendDrawAction(action);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentAction != null) {
      final endAction = DrawAction(
        x: _currentAction!.x,
        y: _currentAction!.y,
        color: _currentAction!.color,
        strokeWidth: _currentAction!.strokeWidth,
        type: 'end',
        tool: _currentAction!.tool,
      );
      ref
          .read(whiteboardServiceProvider(widget.meetingId).notifier)
          .sendDrawAction(endAction);
      _currentAction = null;
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardServiceProvider(widget.meetingId));

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: Container(
            color: Colors.white,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (d) => _onPanStart(d, constraints),
                  onPanUpdate: (d) => _onPanUpdate(d, constraints),
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

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      color: Colors.grey[900],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: tools + stroke slider + clear
          Row(
            children: [
              _toolButton(_Tool.pencil, Icons.edit, 'Pencil'),
              _toolButton(_Tool.eraser, Icons.cleaning_services, 'Eraser'),
              _toolButton(_Tool.blur, Icons.blur_on, 'Blur'),
              const SizedBox(width: 8),
              const VerticalDivider(width: 1, color: Colors.white24),
              const SizedBox(width: 4),
              _strokeStepper(),
              const Spacer(),
              IconButton(
                tooltip: 'Clear board',
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                onPressed: () => ref
                    .read(whiteboardServiceProvider(widget.meetingId).notifier)
                    .clearBoard(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: full palette (scrollable) + "more colours" sheet
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _palette.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => _colorOption(_palette[i]),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'More colours',
                  icon: const Icon(Icons.color_lens_outlined,
                      color: Colors.white, size: 22),
                  onPressed: _openColorSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(_Tool tool, IconData icon, String tooltip) {
    final selected = _currentTool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            icon,
            color: selected ? const Color(0xFF8AB4F8) : Colors.white,
            size: 22,
          ),
          onPressed: () => setState(() => _currentTool = tool),
        ),
      ),
    );
  }

  /// Compact "− N +" stepper for fine control. Doubles as a slider
  /// on long-press (opens a bottom sheet) for big jumps.
  Widget _strokeStepper() {
    return GestureDetector(
      onLongPress: _openWidthSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() {
                _currentStrokeWidth =
                    (_currentStrokeWidth - 1).clamp(1.0, 40.0);
              }),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.remove, color: Colors.white, size: 18),
              ),
            ),
            // Live preview dot — width scales with stroke
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              child: Container(
                width: _currentStrokeWidth.clamp(2.0, 22.0),
                height: _currentStrokeWidth.clamp(2.0, 22.0),
                decoration: BoxDecoration(
                  color: _currentTool == _Tool.eraser
                      ? Colors.white
                      : _currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() {
                _currentStrokeWidth =
                    (_currentStrokeWidth + 1).clamp(1.0, 40.0);
              }),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.add, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openWidthSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stroke width',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.white, size: 4),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: 40,
                        divisions: 39,
                        value: _currentStrokeWidth,
                        label: _currentStrokeWidth.toStringAsFixed(0),
                        activeColor: const Color(0xFF8AB4F8),
                        onChanged: (v) {
                          setSheetState(() {});
                          setState(() => _currentStrokeWidth = v);
                        },
                      ),
                    ),
                    const Icon(Icons.circle, color: Colors.white, size: 22),
                  ],
                ),
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: _currentStrokeWidth * 2,
                    height: _currentStrokeWidth * 2,
                    decoration: BoxDecoration(
                      color: _currentTool == _Tool.eraser
                          ? Colors.white
                          : _currentColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Material full-spectrum picker grid in a bottom sheet.
  void _openColorSheet() {
    // Pull every primary swatch + a few greys for completeness.
    const swatches = <MaterialColor>[
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
    ];
    const shades = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900];
    final colors = <Color>[
      Colors.black,
      Colors.white,
      ...swatches.expand((s) => shades.map((sh) => s[sh]!)),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'All colours',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: colors.length,
                    itemBuilder: (_, i) {
                      final c = colors[i];
                      final selected = _currentColor.toARGB32() == c.toARGB32();
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentColor = c;
                            // Picking a colour implicitly switches
                            // back to pencil — eraser ignores colour.
                            if (_currentTool == _Tool.eraser) {
                              _currentTool = _Tool.pencil;
                            }
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF8AB4F8)
                                  : Colors.white12,
                              width: selected ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorOption(Color color) {
    final selected = _currentColor.toARGB32() == color.toARGB32() &&
        _currentTool != _Tool.eraser;
    return GestureDetector(
      onTap: () => setState(() {
        _currentColor = color;
        if (_currentTool == _Tool.eraser) _currentTool = _Tool.pencil;
      }),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFF8AB4F8) : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
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

      // Don't connect across stroke boundaries.
      if (next.type == 'start' || current.type == 'end') continue;
      // Different tools mid-stroke means we crossed a boundary.
      if (current.tool != next.tool) continue;

      final paint = Paint()
        ..color = _colorFromHex(current.color)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = current.strokeWidth
        ..style = PaintingStyle.stroke;

      // Blur tool: soft edges via mask filter. Sigma scales with
      // stroke so a thin blur is still subtle and a fat blur is
      // visibly hazy.
      if (current.tool == 'blur') {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          (current.strokeWidth / 2).clamp(2.0, 16.0),
        );
      }

      final p1 = Offset(current.x * size.width, current.y * size.height);
      final p2 = Offset(next.x * size.width, next.y * size.height);

      canvas.drawLine(p1, p2, paint);
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
