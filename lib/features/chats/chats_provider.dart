// ════════════════════════════════════════════════════════════════════
//  Chat Riverpod providers
// ════════════════════════════════════════════════════════════════════
//  All UI screens consume these — never the repository directly. Swap
//  the repository implementation in one place when the backend lands.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'data/chat_models.dart';
import 'data/chat_repository.dart';

/// The active repository. Today this is a `MockChatRepository` seeded
/// with the signed-in user's email. When the backend ships, replace
/// the body with `RealChatRepository(ApiClient(), socket)`.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final email = ref.watch(authProvider).user?.email ?? 'me@mizdah.dev';
  return MockChatRepository(email);
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
