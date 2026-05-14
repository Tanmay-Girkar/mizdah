// ════════════════════════════════════════════════════════════════════
//  Contacts repository — match device contacts against Mizdah users
//  ────────────────────────────────────────────────────────────────────
//  Wraps the new POST /api/users/contacts/match endpoint documented
//  at docs/PHONE_AND_CONTACTS_BACKEND.md §4. Splits the contact list
//  into batches of 500 (the spec's cap) and folds results into a
//  single MizdahContact list.
//
//  Also handles local caching: matches are persisted to SharedPreferences
//  so the Call tab can paint instantly on cold-boot before the next
//  network sync completes.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/services/contacts_service.dart';
import '../models/contact_models.dart';

class ContactsRepository {
  final ApiClient _apiClient = ApiClient();

  // ── Cache keys ────────────────────────────────────────────────────
  // Versioned so a future schema change can invalidate without
  // touching unrelated SharedPreferences entries.
  static const _kCacheContacts = 'mizdah.contacts.matched.v1';
  static const _kCacheSyncedAt = 'mizdah.contacts.syncedAt.v1';

  /// Hit the backend's match endpoint with the given phones + emails.
  /// Splits into 500-entry batches to respect the spec's request cap
  /// (§4.1). Returns the union of all batches' matches, with
  /// duplicate userIds collapsed.
  Future<List<MizdahContact>> matchContacts({
    required List<String> phones,
    required List<String> emails,
  }) async {
    final byUserId = <String, MizdahContact>{};

    // Helper to send one batch.
    Future<void> sendBatch(
        List<String> phoneBatch, List<String> emailBatch) async {
      if (phoneBatch.isEmpty && emailBatch.isEmpty) return;
      try {
        final response = await _apiClient.post(
          '${ApiConfig.baseUrl}/api/users/contacts/match',
          data: {
            'phones': phoneBatch,
            'emails': emailBatch,
          },
        );
        final data = response.data;
        if (data is! Map) return;
        final rawMatches = data['matches'];
        if (rawMatches is! List) return;
        for (final m in rawMatches) {
          if (m is! Map) continue;
          final entry = MizdahContact.fromJson(Map<String, dynamic>.from(m));
          // Phone wins over email when both signals map to the same
          // user — per §4.3 of the spec. The server already enforces
          // this, but defending here against any future loosening.
          final existing = byUserId[entry.userId];
          if (existing == null) {
            byUserId[entry.userId] = entry;
          } else if (existing.matchedBy != 'phone' && entry.matchedBy == 'phone') {
            byUserId[entry.userId] = entry;
          }
        }
        final stats = data['stats'];
        if (stats is Map) {
          debugPrint('[contacts-match] stats=$stats');
        }
      } catch (e) {
        debugPrint('[contacts-match] batch failed: $e');
        // Swallow — the next batch may still succeed and a partial
        // list is better than no list at all.
      }
    }

    // Slice into 500-entry chunks. Phone batches and email batches
    // are sent independently so a user with 800 phones + 50 emails
    // does 2 phone requests + 1 email request — not 3 requests where
    // each has both phones and emails interleaved.
    const batchSize = 500;
    for (var i = 0; i < phones.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, phones.length);
      await sendBatch(phones.sublist(i, end), const []);
    }
    for (var i = 0; i < emails.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, emails.length);
      await sendBatch(const [], emails.sublist(i, end));
    }

    return byUserId.values.toList();
  }

  /// One-shot sync: read the device address book, normalise phones,
  /// hit /contacts/match, persist the result, return both the
  /// matched users and the leftover "not on Mizdah" device contacts.
  ///
  /// Returns null if contacts permission is denied — caller decides
  /// whether to prompt and re-call.
  Future<ContactsSyncResult?> sync({required String defaultRegion}) async {
    final allowed = await ContactsService.instance.hasPermission();
    if (!allowed) {
      debugPrint('[contacts-sync] aborted — permission not granted');
      return null;
    }

    final stopwatch = Stopwatch()..start();
    final devices = await ContactsService.instance.loadAllContacts(
      defaultRegion: defaultRegion,
    );
    final allPhones = <String>{};
    final allEmails = <String>{};
    for (final c in devices) {
      allPhones.addAll(c.phones);
      allEmails.addAll(c.emails);
    }
    debugPrint('[contacts-sync] device read in ${stopwatch.elapsedMilliseconds}ms '
        'devices=${devices.length} '
        'uniquePhones=${allPhones.length} '
        'uniqueEmails=${allEmails.length}');

    final matched = await matchContacts(
      phones: allPhones.toList(),
      emails: allEmails.toList(),
    );

    // Attach the local display name for each matched user — match by
    // phone first (precise), then email (fallback). Phone-keyed lookup
    // table keeps the loop O(n).
    final phoneToLocalName = <String, String>{};
    final emailToLocalName = <String, String>{};
    for (final c in devices) {
      if (c.displayName.isEmpty) continue;
      for (final p in c.phones) {
        phoneToLocalName.putIfAbsent(p, () => c.displayName);
      }
      for (final e in c.emails) {
        emailToLocalName.putIfAbsent(e, () => c.displayName);
      }
    }
    final stitched = matched
        .map((m) => m.copyWith(
              localDeviceName: m.matchedBy == 'phone'
                  ? phoneToLocalName[m.matchedValue]
                  : emailToLocalName[m.matchedValue],
            ))
        .toList();

    // Sort matched alphabetically by displayed name for a stable UI.
    stitched.sort((a, b) => a.displayName
        .toLowerCase()
        .compareTo(b.displayName.toLowerCase()));

    // "Not on Mizdah" set — device contacts whose phones/emails
    // didn't appear in the matched results. Used by the Invite UI.
    final matchedPhones = matched
        .where((m) => m.matchedBy == 'phone' && m.phone != null)
        .map((m) => m.phone!)
        .toSet();
    final matchedEmails = matched
        .where((m) => m.matchedBy == 'email' && m.email != null)
        .map((m) => m.email!.toLowerCase())
        .toSet();
    final invitable = <DeviceContact>[];
    for (final c in devices) {
      final hasMatch =
          c.phones.any(matchedPhones.contains) ||
              c.emails.any(matchedEmails.contains);
      if (!hasMatch && c.phones.isNotEmpty) {
        invitable.add(c);
      }
    }
    invitable.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    // Persist matched list so the next cold-boot renders instantly.
    await _persistCache(stitched);

    stopwatch.stop();
    debugPrint('[contacts-sync] done in ${stopwatch.elapsedMilliseconds}ms '
        'matched=${stitched.length} '
        'invitable=${invitable.length}');
    return ContactsSyncResult(
      matched: stitched,
      invitable: invitable,
    );
  }

  // ── Local cache ──────────────────────────────────────────────────

  /// Read the cached match list from SharedPreferences. Used to paint
  /// the Call tab instantly on cold-boot while the network sync runs
  /// in the background.
  Future<List<MizdahContact>> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheContacts);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => MizdahContact.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('[contacts-cache] load failed: $e');
      return const [];
    }
  }

  /// When was the last successful sync? Used by the provider to
  /// decide if we should auto-sync on tab open (>6h old).
  Future<DateTime?> lastSyncedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kCacheSyncedAt);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCache(List<MizdahContact> contacts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCacheContacts,
        jsonEncode(contacts.map((c) => c.toJson()).toList()),
      );
      await prefs.setInt(
        _kCacheSyncedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[contacts-cache] save failed: $e');
    }
  }

  /// Clear cache — call this on logout so a different user signing
  /// in on the same device doesn't briefly see the previous user's
  /// matched contacts.
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCacheContacts);
      await prefs.remove(_kCacheSyncedAt);
    } catch (_) {}
  }
}

/// Return type of `ContactsRepository.sync`.
class ContactsSyncResult {
  final List<MizdahContact> matched;
  final List<DeviceContact> invitable;
  const ContactsSyncResult({
    required this.matched,
    required this.invitable,
  });
}
