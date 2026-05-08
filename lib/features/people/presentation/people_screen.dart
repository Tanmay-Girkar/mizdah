// ════════════════════════════════════════════════════════════════════
//  People — premium directory of recent participants
//  ────────────────────────────────────────────────────────────────────
//  We don't have a dedicated `peopleProvider` yet, so this view derives
//  the directory from `callHistoryProvider` — everyone you've met
//  with recently shows up here, with a search bar that filters by
//  name. Tapping a row jumps you into a redial pre-join with their
//  most-recent meeting code, which is the most useful behaviour we
//  can offer until the backend grows a contacts endpoint.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../../core/utils/meeting_utils.dart';
import '../../../data/models/models.dart';
import '../../home/presentation/home_screen.dart' show callHistoryProvider;

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Collapse the call-history list into one row per distinct title,
  /// keeping the most-recent timestamp for each.
  List<_Person> _derivePeople(List<CallHistory> history) {
    final byKey = <String, _Person>{};
    for (final c in history) {
      final key = c.title.trim().toLowerCase();
      if (key.isEmpty) continue;
      final existing = byKey[key];
      if (existing == null || c.timestamp.isAfter(existing.lastSeen)) {
        byKey[key] = _Person(
          name: c.title.trim(),
          lastSeen: c.timestamp,
          lastMeetingCode: c.meetingCode,
          meetCount: (existing?.meetCount ?? 0) + 1,
        );
      } else {
        byKey[key] = existing.copyWith(
          meetCount: existing.meetCount + 1,
        );
      }
    }
    final list = byKey.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(callHistoryProvider);

    return MizdahTabScaffold(
      activeIndex: 3,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.0,
              child: const MizdahPageHeader(
                leading: 'Your',
                accent: 'people',
                subtitle: 'Recent collaborators · Quick redial',
              ),
            ),
            const SizedBox(height: 14),

            // Search bar
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _SearchBar(
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Body
            MizdahFadeUp(
              controller: _entryCtrl,
              delay: 0.20,
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation(MizdahTokens.primary),
                      ),
                    ),
                  ),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: MizdahCard(
                    padding: EdgeInsets.zero,
                    child: MizdahEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load people',
                      subtitle: 'Pull down to retry',
                    ),
                  ),
                ),
                data: (history) {
                  final people = _derivePeople(history);
                  final filtered = _query.isEmpty
                      ? people
                      : people
                          .where((p) =>
                              p.name.toLowerCase().contains(_query.toLowerCase()))
                          .toList();
                  if (people.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: MizdahCard(
                        padding: EdgeInsets.zero,
                        child: MizdahEmptyState(
                          icon: Icons.people_alt_rounded,
                          title: 'No people yet',
                          subtitle:
                              'After your first meeting, the people you collaborate with show up here.',
                        ),
                      ),
                    );
                  }
                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: MizdahCard(
                        padding: EdgeInsets.zero,
                        child: MizdahEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matches',
                          subtitle: 'Try a different name.',
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            '${filtered.length} ${filtered.length == 1 ? 'person' : 'people'}',
                            style: TextStyle(
                              color: MizdahTokens.mutedOf(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        for (final p in filtered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PersonCard(person: p),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: MizdahTokens.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MizdahTokens.border(context), width: 1),
        boxShadow: MizdahTokens.shadow(context, elevation: 0.4),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: MizdahTokens.mutedOf(context), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: TextStyle(
                color: MizdahTokens.inkOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search people',
                hintStyle: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final _Person person;
  const _PersonCard({required this.person});

  String _formatRelative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inHours < 1) return '${diff.inMinutes.clamp(1, 60)}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(when);
  }

  @override
  Widget build(BuildContext context) {
    final code = person.lastMeetingCode?.isNotEmpty == true
        ? MeetingUtils.extractCode(person.lastMeetingCode!)
        : null;
    return MizdahCard(
      padding: const EdgeInsets.all(14),
      onTap: code == null
          ? null
          : () => context.push('/pre-join/$code'),
      child: Row(
        children: [
          MizdahAvatar(name: person.name, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        color: MizdahTokens.mutedOf(context), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _formatRelative(person.lastSeen),
                      style: TextStyle(
                        color: MizdahTokens.mutedOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${person.meetCount} meeting${person.meetCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Color(0xFF7C3AED),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Quick-redial button
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: code == null
                  ? null
                  : MizdahTokens.heroGradient,
              color: code == null ? const Color(0xFFEEF0F7) : null,
              shape: BoxShape.circle,
              boxShadow: code == null
                  ? null
                  : [
                      BoxShadow(
                        color:
                            MizdahTokens.primary.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Icon(
              Icons.videocam_rounded,
              color: code == null ? MizdahTokens.mutedOf(context) : Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────

class _Person {
  final String name;
  final DateTime lastSeen;
  final String? lastMeetingCode;
  final int meetCount;
  const _Person({
    required this.name,
    required this.lastSeen,
    required this.lastMeetingCode,
    required this.meetCount,
  });

  _Person copyWith({int? meetCount}) => _Person(
        name: name,
        lastSeen: lastSeen,
        lastMeetingCode: lastMeetingCode,
        meetCount: meetCount ?? this.meetCount,
      );
}
