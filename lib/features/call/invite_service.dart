// ════════════════════════════════════════════════════════════════════
//  Invite service — share-sheet invite for non-Mizdah contacts
//  ────────────────────────────────────────────────────────────────────
//  Builds the message + invite link and hands it to the OS share
//  sheet via `share_plus`. From there the user picks the channel —
//  SMS, WhatsApp, Telegram, email, whatever's installed.
//
//  Invite link is a placeholder for now (the app's marketing site)
//  because there's no deep-link / referral wiring yet — see TODO.
// ════════════════════════════════════════════════════════════════════

import 'package:share_plus/share_plus.dart';

import '../../data/models/contact_models.dart';

class InviteService {
  /// Replace with the canonical install link once the app has a
  /// marketing page / store listings. For now the message just nudges
  /// users to search "Mizdah" in their app store. When deep-link
  /// referrals exist, swap this for a personalised
  /// `https://mizdah.app/invite?ref=<userId>`.
  static const _inviteLink = 'https://mizdah.app';

  /// Open the OS share sheet pre-filled with a friendly invite.
  /// `recipient` is the device contact we're inviting; we use their
  /// first name in the salutation if available.
  static Future<void> invite(DeviceContact recipient) async {
    final firstName = _firstName(recipient.displayName);
    final greet = firstName.isEmpty ? 'Hey' : 'Hey $firstName';
    final message =
        "$greet — I'm on Mizdah. Join me so we can call and chat. "
        "Download it at $_inviteLink";
    await SharePlus.instance.share(
      ShareParams(text: message, subject: 'Join me on Mizdah'),
    );
  }

  static String _firstName(String displayName) {
    final t = displayName.trim();
    if (t.isEmpty) return '';
    return t.split(RegExp(r'\s+')).first;
  }
}
