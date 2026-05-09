// ════════════════════════════════════════════════════════════════════
//  New Chat — search registered users by gmail address or display
//  name and start a 1:1 conversation. Tapping a result calls
//  `openConversationWith` which is idempotent on the backend.
// ════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../chats_provider.dart';
import '../data/chat_models.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  List<ChatUser> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _runSearch(v));
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final repo = ref.read(chatRepositoryProvider);
    final out = await repo.searchUsers(q);
    if (!mounted || _query != q) return;
    setState(() {
      _results = out;
      _searching = false;
    });
  }

  Future<void> _open(ChatUser u) async {
    final repo = ref.read(chatRepositoryProvider);
    final conv = await repo.openConversationWith(u.email);
    if (!mounted) return;
    // Replace the new-chat route with the detail so back goes to list.
    context.pushReplacement('/chats/${conv.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 18, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: MizdahTokens.inkOf(context), size: 18),
                    splashRadius: 22,
                  ),
                  Text(
                    'New chat',
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: MizdahTokens.surface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: MizdahTokens.border(context), width: 1),
                  boxShadow:
                      MizdahTokens.shadow(context, elevation: 0.4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.alternate_email_rounded,
                        color: MizdahTokens.mutedOf(context), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        onChanged: _onChanged,
                        style: TextStyle(
                          color: MizdahTokens.inkOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Search Gmail address or name',
                          hintStyle: TextStyle(
                            color: MizdahTokens.mutedOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor:
                  AlwaysStoppedAnimation(MizdahTokens.primary),
            ),
          ),
        ),
      );
    }
    if (_query.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MizdahTokens.iconTileBg(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.alternate_email_rounded,
                    color: MizdahTokens.primary, size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                'Find someone to chat with',
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Type a Gmail address (or part of one) to search registered Mizdah users.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: const MizdahCard(
          padding: EdgeInsets.zero,
          child: MizdahEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            subtitle:
                'Make sure the email is registered with Mizdah, or try a different one.',
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      itemCount: _results.length,
      itemBuilder: (ctx, i) {
        final u = _results[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MizdahCard(
            padding: const EdgeInsets.all(12),
            onTap: () => _open(u),
            child: Row(
              children: [
                MizdahAvatar(name: u.label, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MizdahTokens.inkOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        u.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MizdahTokens.mutedOf(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: MizdahTokens.heroGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_rounded,
                      color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
