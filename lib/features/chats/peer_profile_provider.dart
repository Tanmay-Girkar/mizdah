import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chats_provider.dart';
import 'data/chat_models.dart';

/// Look up another user's profile (display name + avatar URL) by
/// email. The chat list endpoint only carries participant *emails*,
/// so the only way to show a peer's avatar in the chat tile is to
/// resolve the email against the user-search endpoint.
///
/// Returns `null` when the search yields nothing — the tile then
/// falls back to its initials avatar. Errors are swallowed so a
/// transient network blip never blanks the chat list.
///
/// Family key is the email, lower-cased and trimmed by the caller
/// to keep the provider cache stable (so test1@MIZDAH.dev and
/// test1@mizdah.dev share one cache slot).
///
/// **Not autoDispose** — peer profiles change rarely. Keeping them
/// cached across tab switches saves a round-trip per chat row on
/// every chat-tab open. The cache shrinks naturally when the user
/// logs out (auth dependents invalidate).
final peerProfileProvider =
    FutureProvider.family<ChatUser?, String>((ref, emailKey) async {
  final lc = emailKey.trim().toLowerCase();
  if (lc.isEmpty) return null;
  final repo = ref.read(chatRepositoryProvider);
  try {
    final results = await repo.searchUsers(lc);
    for (final u in results) {
      if (u.email.toLowerCase() == lc) return u;
    }
    // The server's prefix-match might bring back near-misses on
    // a less-than-exact email query — tolerate the first hit
    // when no exact match is present, since email substrings are
    // unique enough in practice that a hit is the right person.
    if (results.isNotEmpty) return results.first;
    return null;
  } catch (_) {
    return null;
  }
});
