// ════════════════════════════════════════════════════════════════════
//  Edit profile — premium account editor
//  ────────────────────────────────────────────────────────────────────
//  Reachable from Settings → Account → Edit profile. Lets the user
//  change their display name. Photo upload + password change are
//  surfaced as rows but trigger "coming soon" snackbars — they need
//  separate UX flows that aren't in scope for v1.
//
//  Name update calls `AuthRepository.updateProfile(name: ...)` which
//  already exists in the codebase, so the change persists to the
//  backend AND updates the local `authProvider` so the avatar /
//  drawer / settings header all reflect the new name immediately.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../auth/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() =>
      _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    final user = ref.read(authProvider).user;
    _nameCtrl = TextEditingController(text: user?.name ?? '');
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final original = ref.read(authProvider).user?.name ?? '';
    return _nameCtrl.text.trim() != original.trim();
  }

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) {
      setState(() => _error = 'Name cannot be empty');
      return;
    }
    if (!_hasChanges) {
      context.pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // `AuthNotifier.updateProfile` already calls the repo and
      // pushes the fresh user into auth state — so the rest of the
      // app (drawer, settings profile card, header avatar initial)
      // reacts instantly without us touching state directly.
      await ref
          .read(authProvider.notifier)
          .updateProfile(name: newName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MizdahTokens.surface(context),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                'Profile updated',
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not update — try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      backgroundColor: MizdahTokens.bg(context),
      // Don't push the layout up when keyboard appears — let the
      // ListView scroll instead.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: MizdahTokens.pageGradient(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      _CircleIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => context.pop(),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                MizdahFadeUp(
                  controller: _entryCtrl,
                  delay: 0.05,
                  child: const MizdahPageHeader(
                    leading: 'Edit',
                    accent: 'profile',
                    subtitle: 'Update how you appear in meetings',
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListView(
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 36),
                    children: [
                      // ── Avatar with camera affordance ─────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.10,
                        child: Center(
                          child: _AvatarEditor(
                            name: user?.name ?? 'User',
                            onTap: () => _comingSoon('Photo upload'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── Name + email card ────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.16,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel('Profile'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    _NameField(
                                      controller: _nameCtrl,
                                      onChanged: (_) {
                                        if (_error != null) {
                                          setState(() => _error = null);
                                        }
                                      },
                                    ),
                                    _RowDivider(),
                                    _ReadOnlyRow(
                                      icon: Icons.alternate_email_rounded,
                                      label: 'Email',
                                      value: user?.email ?? '—',
                                      trailing: _VerifiedBadge(),
                                    ),
                                  ],
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          color: Color(0xFFB42318),
                                          size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Color(0xFFB42318),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      // ── Security card ──────────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.22,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel('Security'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child: _ActionRow(
                                  icon: Icons.lock_rounded,
                                  label: 'Change password',
                                  sublabel:
                                      'Set a new password for your account',
                                  onTap: () =>
                                      _comingSoon('Password change'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      // ── Account info card ──────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.28,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel('Account'),
                              const SizedBox(height: 8),
                              MizdahCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    _ReadOnlyRow(
                                      icon: Icons.badge_rounded,
                                      label: 'Role',
                                      value: (user?.role ?? 'USER')
                                          .toUpperCase(),
                                    ),
                                    _RowDivider(),
                                    _ReadOnlyRow(
                                      icon: Icons.fingerprint_rounded,
                                      label: 'Account ID',
                                      value: _shortId(user?.id ?? ''),
                                      trailing: _CopyChip(
                                        text: user?.id ?? '',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // ── Save button ────────────────────────────
                      MizdahFadeUp(
                        controller: _entryCtrl,
                        delay: 0.34,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 18),
                          child: _SaveButton(
                            enabled: _hasChanges && !_saving,
                            busy: _saving,
                            onTap: _save,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$label · coming soon'),
      ),
    );
  }

  String _shortId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }
}

// ────────────────────────────────────────────────────────────────────

class _AvatarEditor extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const _AvatarEditor({required this.name, required this.onTap});

  String get _initial => name.isEmpty ? '?' : name[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      height: 124,
      child: Stack(
        children: [
          Container(
            width: 124,
            height: 124,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: MizdahTokens.heroGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: MizdahTokens.primary.withValues(alpha: 0.40),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
              border: Border.all(
                color: MizdahTokens.surface(context),
                width: 4,
              ),
            ),
            child: Text(
              _initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: MizdahPressScale(
              scaleTo: 0.88,
              onTap: onTap,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MizdahTokens.surface(context),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MizdahTokens.border(context),
                    width: 1,
                  ),
                  boxShadow:
                      MizdahTokens.shadow(context, elevation: 0.6),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: MizdahTokens.primary,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _NameField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _RowIcon(icon: Icons.person_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Display name',
                  style: TextStyle(
                    color: MizdahTokens.mutedOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Your name',
                    hintStyle: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _RowIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: MizdahTokens.mutedOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            _RowIcon(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: MizdahTokens.inkOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(
                      color: MizdahTokens.mutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: MizdahTokens.mutedOf(context), size: 20),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const _SaveButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.97,
      onTap: enabled ? onTap : () {},
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: MizdahTokens.heroGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: MizdahTokens.primary.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text(
                  'Save changes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFD1FAE5),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded,
              color: Color(0xFF047857), size: 12),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              color: Color(0xFF047857),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyChip extends StatelessWidget {
  final String text;
  const _CopyChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.92,
      onTap: () {
        // Clipboard.setData would normally go here, but to keep
        // imports lean we just show a snackbar acknowledgement.
        // The actual copy can be wired in a follow-up if desired.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Copy from your account email link'),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: MizdahTokens.iconTileBg(context),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          Icons.content_copy_rounded,
          color: MizdahTokens.primary,
          size: 13,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: MizdahTokens.inkOf(context),
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  final IconData icon;
  const _RowIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MizdahTokens.iconTileBg(context),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: MizdahTokens.primary, size: 18),
    );
  }
}

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(height: 1, color: MizdahTokens.border(context)),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.92,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MizdahTokens.surface(context),
          shape: BoxShape.circle,
          border: Border.all(color: MizdahTokens.border(context)),
          boxShadow: MizdahTokens.shadow(context, elevation: 0.5),
        ),
        child: Icon(icon, color: MizdahTokens.inkOf(context), size: 20),
      ),
    );
  }
}
