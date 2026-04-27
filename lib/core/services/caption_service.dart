import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:speech_to_text/speech_to_text.dart';

/// Per-speaker active caption line. We keep the last text + a name
/// label so the overlay can show "Alice: hello there" with the
/// speaker's display name rather than a raw socket id.
class CaptionLine {
  final String text;
  final String? name;
  const CaptionLine({required this.text, this.name});
}

class CaptionState {
  /// `socketId` -> current line. Empty when nothing is being spoken.
  /// The local user is keyed under `'local'` so we never collide with
  /// a real remote socketId.
  final Map<String, CaptionLine> activeCaptions;
  final bool isEnabled;
  /// Set when the user tapped CC but speech_to_text couldn't init
  /// (no perms / locale unsupported / etc). Lets the UI surface a
  /// brief snackbar instead of silently doing nothing.
  final String? error;

  const CaptionState({
    required this.activeCaptions,
    this.isEnabled = false,
    this.error,
  });

  CaptionState copyWith({
    Map<String, CaptionLine>? activeCaptions,
    bool? isEnabled,
    String? error,
    bool clearError = false,
  }) {
    return CaptionState(
      activeCaptions: activeCaptions ?? this.activeCaptions,
      isEnabled: isEnabled ?? this.isEnabled,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// On-device captions: when the user toggles CC on we boot
/// `speech_to_text`, stream partial transcripts to the local
/// overlay AND emit them on the signaling socket so peers see them
/// too. When the user toggles off we stop listening — we don't want
/// a hot mic on the device permanently.
class CaptionNotifier extends StateNotifier<CaptionState> {
  final socket_io.Socket socket;
  /// Local socketId / display name — set by the meeting provider
  /// once it knows them, so emitted captions can be attributed.
  String? localSocketId;
  String? localName;

  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  Timer? _clearTimer;
  Timer? _restartTimer;

  CaptionNotifier({required this.socket})
      : super(const CaptionState(activeCaptions: {})) {
    _initListeners();
  }

  /// Update the attribution for outgoing caption packets. Called by
  /// the meeting notifier once the socket is connected and we know
  /// the participant name.
  void setLocalIdentity({String? socketId, String? name}) {
    localSocketId = socketId;
    localName = name;
  }

  Future<void> toggleCaptions() async {
    final next = !state.isEnabled;
    state = state.copyWith(isEnabled: next, clearError: true);
    if (next) {
      await _startListening();
    } else {
      await _stopListening();
      // Clear any leftover lines so the overlay disappears.
      state = state.copyWith(activeCaptions: const {});
    }
  }

  // ---------- Speech recognition ----------

  Future<void> _startListening() async {
    try {
      _speechReady = await _speech.initialize(
        onError: (e) {
          // SpeechToText errors are usually transient ("no_match",
          // "speech_timeout"). We restart automatically below; only
          // surface unrecoverable ones in state.error.
          if (e.permanent) {
            state = state.copyWith(
              isEnabled: false,
              error: 'Captions unavailable: ${e.errorMsg}',
            );
            _listening = false;
          }
        },
        onStatus: (status) {
          // 'notListening' fires when the engine times out a turn —
          // restart immediately so we don't drop the next sentence.
          if (status == 'notListening' && state.isEnabled) {
            _scheduleRestart();
          }
        },
        debugLogging: kDebugMode,
      );
      if (!_speechReady) {
        state = state.copyWith(
          isEnabled: false,
          error: 'Microphone unavailable for captions',
        );
        return;
      }
      await _listen();
    } catch (e) {
      state = state.copyWith(
        isEnabled: false,
        error: 'Captions failed to start: $e',
      );
    }
  }

  Future<void> _listen() async {
    if (!_speechReady || _listening) return;
    _listening = true;
    try {
      await _speech.listen(
        onResult: (result) {
          if (!state.isEnabled) return;
          _publishLocalCaption(result.recognizedWords, result.finalResult);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        ),
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
      );
    } catch (e) {
      _listening = false;
    }
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 250), () async {
      _listening = false;
      if (!state.isEnabled) return;
      await _listen();
    });
  }

  Future<void> _stopListening() async {
    _restartTimer?.cancel();
    try {
      await _speech.stop();
    } catch (_) {}
    _listening = false;
  }

  // ---------- Outbound + inbound socket ----------

  void _publishLocalCaption(String text, bool isFinal) {
    if (text.trim().isEmpty) return;
    final key = localSocketId ?? 'local';
    final newCaptions = Map<String, CaptionLine>.from(state.activeCaptions);
    newCaptions[key] = CaptionLine(text: text, name: localName ?? 'You');
    state = state.copyWith(activeCaptions: newCaptions);

    // Cross-side broadcast. The backend uses a single
    // `media-toggle-remote` event for ALL room broadcasts — chat,
    // reactions, mic/camera state — and discriminates by `type`.
    // We piggyback captions on that proven channel so peers see
    // them reliably (the dedicated `caption-send` is a no-op on
    // backends that don't relay it).
    try {
      socket.emit('media-toggle-remote', {
        'type': 'CAPTION',
        'from': key,
        'socketId': key,
        'name': localName ?? 'You',
        'text': text,
        'isFinal': isFinal,
      });
    } catch (_) {}

    if (isFinal) _scheduleClear(key);
  }

  void _ingestIncoming(Map data, {String? fromOverride}) {
    if (!state.isEnabled) return;
    try {
      final socketId = (fromOverride ??
              data['socketId']?.toString() ??
              data['from']?.toString()) ??
          'unknown';
      final text = data['text']?.toString() ?? '';
      final name = data['name']?.toString();
      final isFinal = data['isFinal'] == true;
      if (text.trim().isEmpty) return;
      // Don't echo our own caption back over the wire.
      if (socketId == (localSocketId ?? 'local')) return;

      final newCaptions =
          Map<String, CaptionLine>.from(state.activeCaptions);
      newCaptions[socketId] = CaptionLine(text: text, name: name);
      state = state.copyWith(activeCaptions: newCaptions);

      if (isFinal) _scheduleClear(socketId);
    } catch (_) {
      // Malformed payload — drop silently.
    }
  }

  void _initListeners() {
    // Legacy dedicated channel — kept in case a backend exposes it.
    socket.on('caption-received', (data) {
      if (data is Map) _ingestIncoming(data);
    });

    // Proven channel — the same one chat/reactions/media-state
    // travel on. The MeetingNotifier also listens here for its
    // own types; socket_io allows multiple handlers per event.
    socket.on('media-toggle-remote', (data) {
      if (data is! Map) return;
      final type = data['type']?.toString().toUpperCase() ?? '';
      if (type != 'CAPTION') return;
      final from = data['from']?.toString();
      _ingestIncoming(data, fromOverride: from);
    });
  }

  void _scheduleClear(String key) {
    // Each speaker has its own debounce. Re-arming the timer means a
    // caption stays visible for 5s after the speaker's *last* word,
    // not after their *first*.
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final next = Map<String, CaptionLine>.from(state.activeCaptions);
      next.remove(key);
      state = state.copyWith(activeCaptions: next);
    });
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _restartTimer?.cancel();
    try {
      _speech.cancel();
    } catch (_) {}
    socket.off('caption-received');
    // Note: not removing all media-toggle-remote handlers — the
    // MeetingNotifier owns its own handler on the same event and
    // we'd kill that too. The CaptionNotifier is per-meeting and
    // disposed alongside the meeting socket, so its handler dies
    // with the socket either way.
    super.dispose();
  }
}
