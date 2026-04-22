import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

class DrawAction {
  final double x; // NormalizedBox (0.0 to 1.0)
  final double y; // NormalizedBox (0.0 to 1.0)
  final String color;
  final double strokeWidth;
  final String type; // 'start', 'move', 'end'

  DrawAction({
    required this.x,
    required this.y,
    required this.color,
    required this.strokeWidth,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'color': color,
    'width': strokeWidth,
    'type': type,
  };

  factory DrawAction.fromJson(Map<String, dynamic> json) {
    return DrawAction(
      x: json['x'] is int ? (json['x'] as int).toDouble() : json['x'],
      y: json['y'] is int ? (json['y'] as int).toDouble() : json['y'],
      color: json['color'] ?? '#000000',
      strokeWidth: json['width'] is int ? (json['width'] as int).toDouble() : json['width'] ?? 2.0,
      type: json['type'] ?? 'move',
    );
  }
}

class WhiteboardState {
  final List<DrawAction> actions;
  final bool isBoardOpen;

  WhiteboardState({
    required this.actions,
    this.isBoardOpen = false,
  });

  WhiteboardState copyWith({
    List<DrawAction>? actions,
    bool? isBoardOpen,
  }) {
    return WhiteboardState(
      actions: actions ?? this.actions,
      isBoardOpen: isBoardOpen ?? this.isBoardOpen,
    );
  }
}

class WhiteboardNotifier extends StateNotifier<WhiteboardState> {
  final socket_io.Socket socket;

  WhiteboardNotifier({required this.socket}) : super(WhiteboardState(actions: [])) {
    _initListeners();
  }

  void openWhiteboard() {
    socket.emit('whiteboard-toggle', {'isOpen': true});
    state = state.copyWith(isBoardOpen: true);
  }

  void _initListeners() {
    socket.on('draw-move', (data) {
      final newAction = DrawAction.fromJson(data);
      state = state.copyWith(actions: [...state.actions, newAction]);
    });

    socket.on('clear-board', (_) {
      state = state.copyWith(actions: []);
    });

    socket.on('whiteboard-state', (data) {
      final List<dynamic> history = data['history'] ?? [];
      final actionsList = history.map((e) => DrawAction.fromJson(e)).toList();
      state = state.copyWith(actions: actionsList);
    });
  }

  void sendDrawAction(DrawAction action) {
    socket.emit('draw-move', action.toJson());
    state = state.copyWith(actions: [...state.actions, action]);
  }

  void requestHistory() {
    socket.emit('request-whiteboard-state', {});
  }

  void clearBoard() {
    socket.emit('clear-board', {});
    state = state.copyWith(actions: []);
  }
}
