// ════════════════════════════════════════════════════════════════════
//  Chat Riverpod providers
// ════════════════════════════════════════════════════════════════════
//  All UI screens consume these — never the repository directly. The
//  repository is chosen at runtime: by default we hit the live
//  backend (`RealChatRepository`, REST + /chats socket namespace per
//  docs/CHATS_API.md). Set `kUseMockChats = true` to fall back to
//  the deterministic in-memory `MockChatRepository` for offline dev
//  or screen demos.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'data/chat_models.dart';
import 'data/chat_repository.dart';
import 'data/real_chat_repository.dart';

/// Flip to `true` to bypass the live backend and run against the
/// in-memory mock seed data (handy for screen captures or when the
/// backend is down). Default is `false` — point at the real API.
const bool kUseMockChats = false;

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  // Use auth state directly — must NOT consume
  // effectiveSelfEmailProvider here, because that one watches
  // conversationsProvider, which watches this provider. The cycle
  // collapses an entire chain. The UI layer uses
  // effectiveSelfEmailProvider for display; the repository just
  // needs *some* identity string for outbound socket / REST calls.
  final me = ref.watch(authProvider).user;
  final email = me?.email ?? 'me@mizdah.dev';
  if (kUseMockChats) {
    return MockChatRepository(email);
  }
  return RealChatRepository(selfEmail: email, selfUserId: me?.id);
});

/// Live stream of conversations for the current user.
final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(chatRepositoryProvider).watchConversations();
});

/// Initial message history for a single conversation (oldest → newest).
final conversationHistoryProvider =
    FutureProvider.family<List<ChatMessage>, String>((ref, conversationId) {
  return ref
      .watch(chatRepositoryProvider)
      .fetchMessages(conversationId: conversationId);
});

/// Live deltas (new + updated messages) for a single open conversation.
final conversationDeltasProvider =
    StreamProvider.family<ChatMessage, String>((ref, conversationId) {
  return ref
      .watch(chatRepositoryProvider)
      .watchMessages(conversationId);
});

/// Best-known email for the local user. Auth state is the primary
/// source; when `auth.user.email` is blank — typically because the
/// secure-storage cache pre-dates the email-storage fix or
/// `/api/auth/me` returned `session_superseded` — we fall back to
/// the email that appears in EVERY one of the user's conversations
/// (the intersection of participants). With a single conversation
/// we can't disambiguate and return ''.
///
/// Both the chats list and the chat detail consume this so the
/// "peer" rendering is consistent across the chat surface.
final effectiveSelfEmailProvider = Provider<String>((ref) {
  final auth = ref.watch(authProvider).user;
  final fromAuth = auth?.email.trim() ?? '';
  if (fromAuth.isNotEmpty) return fromAuth;
  final convs = ref.watch(conversationsProvider).asData?.value ?? const [];
  return deriveSelfEmailFromConversations(convs);
});

/// Pure helper — compute the email that's present in every
/// conversation. Exposed so a screen can call it directly with a
/// custom list (e.g. tests, or call sites that already have the
/// list in hand and want to avoid a second `ref.watch`).
String deriveSelfEmailFromConversations(List<Conversation> convs) {
  if (convs.length < 2) return '';
  final candidate =
      convs.first.participants.map((e) => e.toLowerCase()).toSet();
  for (var i = 1; i < convs.length; i++) {
    final ps = convs[i].participants.map((e) => e.toLowerCase()).toSet();
    candidate.retainWhere(ps.contains);
    if (candidate.isEmpty) return '';
  }
  return candidate.length == 1 ? candidate.first : '';
}
