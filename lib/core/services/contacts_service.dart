// ════════════════════════════════════════════════════════════════════
//  Contacts service — reads device address book, normalises phones
//  ────────────────────────────────────────────────────────────────────
//  Pure-Dart wrapper around `flutter_contacts` + `phone_numbers_parser`.
//  The repository on top of this calls `loadAllContacts` to get the
//  deduped, E.164-normalised list, then uploads it to the backend
//  /api/users/contacts/match endpoint.
//
//  WHAT IS NOT DONE HERE:
//   • No network. This file never hits the backend — it's a pure
//     local read + transform.
//   • No persistence. The list is returned to the caller; if they
//     want to cache it, they cache the MATCH RESULT (smaller, less
//     PII) not the raw contacts.
//   • No deltas. We re-read the full address book every sync. With
//     a few hundred contacts this is fast enough; if it becomes a
//     bottleneck we can switch to flutter_contacts' change-stream.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../data/models/contact_models.dart';

class ContactsService {
  ContactsService._();
  static final ContactsService instance = ContactsService._();

  /// Probe whether contacts permission is currently granted. Does NOT
  /// trigger the permission prompt — the caller (UI / provider)
  /// decides when to do that, after showing the rationale sheet.
  Future<bool> hasPermission() async {
    return Permission.contacts.isGranted;
  }

  /// Trigger the system permission prompt. Returns true if the user
  /// granted (or had already granted).
  Future<bool> requestPermission() async {
    final status = await Permission.contacts.request();
    debugPrint('[contacts] permission request → $status');
    return status.isGranted || status.isLimited;
  }

  /// Read every device contact with at least one phone or email,
  /// normalise the phone numbers to E.164 using `defaultRegion` as
  /// the assumed country for entries that don't carry a `+`.
  ///
  /// `defaultRegion` is the ISO-3166-1 alpha-2 code of the user's
  /// own country (we know it from the user's `phoneCountry` field).
  /// Without it, a 10-digit Indian number like `9876543210` would
  /// be impossible to map to `+919876543210` — we'd just have to
  /// drop it.
  Future<List<DeviceContact>> loadAllContacts({
    required String defaultRegion,
  }) async {
    final permission = await Permission.contacts.status;
    if (!permission.isGranted && !permission.isLimited) {
      debugPrint('[contacts] loadAllContacts called without permission '
          '($permission) — returning empty list');
      return const [];
    }
    debugPrint('[contacts] loading address book defaultRegion=$defaultRegion');
    final raw = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
      withAccounts: false,
      withGroups: false,
      // Tombstones (deleted contacts) just add noise.
      deduplicateProperties: true,
    );
    debugPrint('[contacts] raw count=${raw.length}');

    final out = <DeviceContact>[];
    final region = IsoCode.fromJson(defaultRegion.toUpperCase());
    for (final c in raw) {
      final phones = <String>{};
      for (final p in c.phones) {
        final norm = _normalise(p.number, region);
        if (norm != null) phones.add(norm);
      }
      final emails = <String>{};
      for (final e in c.emails) {
        final addr = e.address.trim().toLowerCase();
        if (addr.isEmpty || !addr.contains('@')) continue;
        emails.add(addr);
      }
      if (phones.isEmpty && emails.isEmpty) continue;
      out.add(DeviceContact(
        displayName: c.displayName.trim(),
        phones: phones.toList(),
        emails: emails.toList(),
      ));
    }
    debugPrint('[contacts] usable contacts=${out.length} '
        'totalPhones=${out.fold<int>(0, (acc, c) => acc + c.phones.length)} '
        'totalEmails=${out.fold<int>(0, (acc, c) => acc + c.emails.length)}');
    return out;
  }

  /// Best-effort phone normalisation. Returns the E.164 string on
  /// success, or null if parsing failed (which is fine — we just
  /// don't upload that one). Doesn't throw — phone formats are a
  /// swamp and we don't want one weird contact to kill the sync.
  String? _normalise(String raw, IsoCode region) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final parsed = PhoneNumber.parse(trimmed, callerCountry: region);
      if (!parsed.isValid()) return null;
      return parsed.international;
    } catch (e) {
      // The library throws on malformed input. Skip silently.
      return null;
    }
  }
}
