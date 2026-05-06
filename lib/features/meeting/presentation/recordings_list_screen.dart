import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../data/repositories/recording_repository.dart';

/// Lists recordings for a single meeting, fetched from
/// `GET /api/recording/<meetingCode>`. Wired against the contract
/// in docs/RECORDING_BACKEND.md.
///
/// Each row shows status badge (recording / processing / ready /
/// failed), duration, size, and a play button that opens the signed
/// URL in the device browser. The signed URL has 24h expiry and is
/// re-issued on every list call by the backend, so the button works
/// even on stale list cache.
class RecordingsListScreen extends ConsumerStatefulWidget {
  final String meetingCode;
  const RecordingsListScreen({required this.meetingCode, super.key});

  @override
  ConsumerState<RecordingsListScreen> createState() =>
      _RecordingsListScreenState();
}

class _RecordingsListScreenState extends ConsumerState<RecordingsListScreen> {
  final _repo = RecordingRepository();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getRecordings(widget.meetingCode);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _repo.getRecordings(widget.meetingCode);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : MizdahTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Recordings',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snapshot.data ?? const [];
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.video_library_outlined,
                    size: 64,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No recordings yet',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Start a recording from the Host Controls panel '
                      'during a meeting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = list[i];
                if (r is! Map) return const SizedBox.shrink();
                return _RecordingTile(rec: r);
              },
            );
          },
        ),
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  final Map rec;
  const _RecordingTile({required this.rec});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = (rec['status'] ?? 'unknown').toString();
    final durationSeconds = (rec['durationSeconds'] as num?)?.toInt();
    final sizeBytes = (rec['sizeBytes'] as num?)?.toInt();
    final url = rec['url']?.toString();
    final startedAt = rec['startedAt']?.toString();

    final isReady = status == 'ready' && url != null && url.isNotEmpty;
    final isInFlight = status == 'recording' || status == 'processing';

    Future<void> open() async {
      if (!isReady) return;
      try {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open recording: $e')),
        );
      }
    }

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: isReady ? open : null,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            // Thumbnail / icon
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (isReady
                        ? MizdahTheme.primaryBlue
                        : (isInFlight ? Colors.orange : Colors.grey))
                    .withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isReady
                    ? Icons.play_circle_fill_rounded
                    : (isInFlight
                        ? Icons.fiber_manual_record_rounded
                        : Icons.error_outline_rounded),
                color: isReady
                    ? MizdahTheme.primaryBlue
                    : (isInFlight ? Colors.orange : Colors.redAccent),
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusBadge(status: status),
                      const SizedBox(width: 8),
                      if (durationSeconds != null)
                        Text(
                          _formatDuration(durationSeconds),
                          style: TextStyle(
                            color:
                                isDark ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatStartedAt(startedAt),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (sizeBytes != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatSize(sizeBytes),
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isReady)
              Icon(
                Icons.open_in_new_rounded,
                color: isDark ? Colors.white54 : Colors.black54,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  // ── Formatters ────────────────────────────────────────────────

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static String _formatStartedAt(String? iso) {
    if (iso == null) return 'Unknown date';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final mm = months[dt.month - 1];
      final hh = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$mm ${dt.day}, $hh:${dt.minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return iso;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'recording' => ('● REC', Colors.red),
      'processing' => ('Processing', Colors.orange),
      'ready' => ('Ready', const Color(0xFF22C55E)),
      'failed' => ('Failed', Colors.redAccent),
      _ => (status.toUpperCase(), Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
