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
  final email = ref.watch(authProvider).user?.email ?? 'me@mizdah.dev';
  if (kUseMockChats) {
    return MockChatRepository(email);
  }
  return RealChatRepository(selfEmail: email);
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
