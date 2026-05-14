// ════════════════════════════════════════════════════════════════════
//  Contact models — local + matched (Mizdah) representations
//  ────────────────────────────────────────────────────────────────────
//  Two distinct shapes:
//
//    • DeviceContact  — what we read from the device address book.
//                       Has display name + raw phones/emails. No
//                       knowledge of whether the person is on Mizdah.
//
//    • MizdahContact  — a matched result from /api/users/contacts/match.
//                       Includes the Mizdah userId + email + avatar so
//                       the UI can place a call without another lookup.
// ════════════════════════════════════════════════════════════════════

import 'models.dart';

/// One entry as it exists in the user's phone.
class DeviceContact {
  /// `displayName` from `flutter_contacts`. May be empty if the user
  /// only saved a phone number.
  final String displayName;
  /// E.164 phone strings, deduped. May be empty if the address-book
  /// entry only had an email.
  final List<String> phones;
  /// Email strings, lowercased + deduped.
  final List<String> emails;

  const DeviceContact({
    required this.displayName,
    required this.phones,
    required this.emails,
  });

  /// "Primary" phone for display — first entry if any.
  String? get primaryPhone => phones.isEmpty ? null : phones.first;

  /// Primary email for display — first entry if any.
  String? get primaryEmail => emails.isEmpty ? null : emails.first;

  /// Persist to SharedPreferences so the Call tab's "Invite to Mizdah"
  /// section paints instantly on cold boot, before the next sync
  /// round-trip completes. Contains only what's already on the
  /// device address book — nothing the user hasn't already opted in
  /// to letting the app see.
  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'phones': phones,
        'emails': emails,
      };

  factory DeviceContact.fromJson(Map<String, dynamic> json) {
    return DeviceContact(
      displayName: (json['displayName'] as String?) ?? '',
      phones: (json['phones'] as List?)?.whereType<String>().toList() ??
          const [],
      emails: (json['emails'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }

  /// Initials used for the avatar placeholder. Falls back to "?" if
  /// the contact has no name.
  String get initials {
    final n = displayName.trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// One matched Mizdah user, returned from /api/users/contacts/match.
/// Mirrors the response shape in docs/PHONE_AND_CONTACTS_BACKEND.md
/// §4.2: each row tells us which value (`phone` or `email`) we
/// submitted matched, and gives the canonical user object.
class MizdahContact {
  final String userId;
  final String name;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  /// "phone" | "email" — which submitted field hit. Used to label
  /// search results.
  final String matchedBy;
  /// The exact value that matched — the phone string we sent, or
  /// the email. Echoes back so the UI can show "matched [phone]"
  /// even when the user has multiple numbers stored.
  final String matchedValue;
  /// Display name of the local device contact that we matched
  /// against (may differ from the Mizdah display name — the user
  /// might have a contact saved as "Mum" who's on Mizdah as
  /// "Anita Sharma"). Set by the repository AFTER the network
  /// round-trip, so the UI can prefer the local name.
  final String? localDeviceName;

  const MizdahContact({
    required this.userId,
    required this.name,
    this.email,
    this.phone,
    this.avatarUrl,
    required this.matchedBy,
    required this.matchedValue,
    this.localDeviceName,
  });

  factory MizdahContact.fromJson(Map<String, dynamic> json) {
    return MizdahContact(
      userId: json['userId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: (json['email'] as String?)?.trim().isEmpty == true
          ? null
          : json['email'] as String?,
      phone: (json['phone'] as String?)?.trim().isEmpty == true
          ? null
          : json['phone'] as String?,
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl']) as String?,
      matchedBy: json['matchedBy']?.toString() ?? 'phone',
      matchedValue: json['matchedValue']?.toString() ?? '',
    );
  }

  /// Persisting matches to SharedPreferences keeps them across cold
  /// boots so the Call-tab list renders instantly before the next
  /// sync round-trip completes.
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'matchedBy': matchedBy,
        'matchedValue': matchedValue,
        if (localDeviceName != null) 'localDeviceName': localDeviceName,
      };

  MizdahContact copyWith({String? localDeviceName}) {
    return MizdahContact(
      userId: userId,
      name: name,
      email: email,
      phone: phone,
      avatarUrl: avatarUrl,
      matchedBy: matchedBy,
      matchedValue: matchedValue,
      localDeviceName: localDeviceName ?? this.localDeviceName,
    );
  }

  /// Convert to a regular `User` — handy when we want to reuse
  /// existing call-button widgets that take a `User`.
  User toUser() => User(
        id: userId,
        email: email ?? '',
        name: localDeviceName?.trim().isNotEmpty == true
            ? localDeviceName!
            : name,
        avatarUrl: avatarUrl,
        phone: phone,
      );

  String get displayName =>
      (localDeviceName?.trim().isNotEmpty == true ? localDeviceName! : name);
}
