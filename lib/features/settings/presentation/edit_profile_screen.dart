// ════════════════════════════════════════════════════════════════════
//  Edit profile — premium account editor
//  ────────────────────────────────────────────────────────────────────
//  Reachable from Settings → Account → Edit profile.
//
//  Wired up:
//    • Display name → POST /api/auth/update {name}
//    • Avatar      → POST /api/files/upload (multipart)
//                    then POST /api/auth/update {avatar_url}
//    • Password    → POST /api/auth/update {password} via dialog
//
//  Name + password endpoints are documented in MOBILE_API_DOCS.md §1.4
//  and verified against the dev backend. Whether `/api/auth/update`
//  accepts `avatar_url` is the one outstanding backend confirmation —
//  flagged in docs/PROFILE_API.md.
// ════════════════════════════════════════════════════════════════════

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/ui/mizdah_design.dart';
import '../../../data/repositories/auth_repository.dart';
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
  bool _uploadingAvatar = false;
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
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_hasChanges) {
        // Real change — push to the server. AuthNotifier.updateProfile
        // already saves the fresh user into both auth state AND
        // secure storage, so the rest of the app updates instantly.
        await ref
            .read(authProvider.notifier)
            .updateProfile(name: newName);
      } else {
        // No actual edit — just refresh the local secure-storage
        // cache with the current user. Useful when the cache predates
        // the email-persistence fix (see auth_provider.dart): one tap
        // here populates the email field without requiring a logout.
        final me = ref.read(authProvider).user;
        if (me != null) {
          await StorageService.saveUserData(
            id: me.id,
            name: me.name,
            email: me.email,
            avatarUrl: me.avatarUrl,
          );
        }
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MizdahTokens.surface(context),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                _hasChanges ? 'Profile updated' : 'Profile cache refreshed',
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
      if (mounted) context.pop();
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
                            avatarUrl: user?.avatarUrl,
                            uploading: _uploadingAvatar,
                            onTap: _pickAndUploadAvatar,
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
                                        // Always rebuild so the Save
                                        // button's enable/disable
                                        // state tracks the field's
                                        // emptiness reactively.
                                        setState(() {
                                          if (_error != null) _error = null;
                                        });
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
                                  onTap: _changePassword,
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
                            enabled:
                                !_saving && _nameCtrl.text.trim().isNotEmpty,
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

  /// Pick an image, upload to /api/files/upload, then patch the
  /// user's avatar_url via /api/auth/update. The local user state
  /// updates immediately so the avatar in the drawer + settings
  /// header refreshes without a re-login.
  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;
    // Capture before any await — context is no longer reliable across
    // the async gap that the file picker introduces.
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final file = picked?.files.firstOrNull;
    if (file == null || file.path == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final repo = AuthRepository();
      final url = await repo.uploadFile(
        filePath: file.path!,
        fileName: file.name,
      );
      await ref
          .read(authProvider.notifier)
          .updateProfile(avatarUrl: url);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MizdahTokens.surface(context),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                'Profile photo updated',
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB42318),
          content: Text(
            'Could not upload photo: $e',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// Modal sheet: enter a new password (twice). On submit, calls
  /// /api/auth/update with the password field.
  Future<void> _changePassword() async {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PasswordSheet(
        newCtrl: newCtrl,
        confirmCtrl: confirmCtrl,
      ),
    );
    if (ok != true) {
      newCtrl.dispose();
      confirmCtrl.dispose();
      return;
    }
    final pw = newCtrl.text;
    newCtrl.dispose();
    confirmCtrl.dispose();
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile(password: pw);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MizdahTokens.surface(context),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                'Password updated',
                style: TextStyle(
                  color: MizdahTokens.inkOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB42318),
          content: Text(
            'Could not update password',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  String _shortId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }
}

// ────────────────────────────────────────────────────────────────────

class _AvatarEditor extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback onTap;
  const _AvatarEditor({
    required this.name,
    required this.avatarUrl,
    required this.uploading,
    required this.onTap,
  });

  String get _initial => name.isEmpty ? '?' : name[0].toUpperCase();
  bool get _hasUrl => avatarUrl != null && avatarUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 124,
      height: 124,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: MizdahTokens.heroGradient,
        shape: BoxShape.circle,
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
    );
    return SizedBox(
      width: 124,
      height: 124,
      child: Stack(
        children: [
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
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
            child: ClipOval(
              child: _hasUrl
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return fallback;
                      },
                      errorBuilder: (ctx, error, stack) => fallback,
                    )
                  : fallback,
            ),
          ),
          if (uploading)
            Positioned.fill(
              child: ClipOval(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
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

// ────────────────────────────────────────────────────────────────────
//  Password change sheet — used by `_changePassword`.
// ────────────────────────────────────────────────────────────────────

class _PasswordSheet extends StatefulWidget {
  final TextEditingController newCtrl;
  final TextEditingController confirmCtrl;
  const _PasswordSheet({required this.newCtrl, required this.confirmCtrl});

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  String? _error;
  bool _obscure = true;

  bool get _valid {
    final n = widget.newCtrl.text;
    final c = widget.confirmCtrl.text;
    return n.length >= 5 && n == c;
  }

  void _submit() {
    final n = widget.newCtrl.text;
    final c = widget.confirmCtrl.text;
    if (n.length < 5) {
      setState(() => _error = 'Password must be at least 5 characters');
      return;
    }
    if (n != c) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: MizdahTokens.surface(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MizdahTokens.border(context),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Change password',
                  style: TextStyle(
                    color: MizdahTokens.inkOf(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'At least 5 characters. Use a unique one.',
                  style: TextStyle(
                    color: MizdahTokens.mutedOf(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _PwField(
                  controller: widget.newCtrl,
                  hint: 'New password',
                  obscure: _obscure,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  trailing: IconButton(
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: MizdahTokens.mutedOf(context),
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _PwField(
                  controller: widget.confirmCtrl,
                  hint: 'Confirm new password',
                  obscure: _obscure,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFB42318), size: 14),
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
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: MizdahTokens.iconTileBg(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: MizdahTokens.inkOf(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: MizdahPressScale(
                        scaleTo: 0.97,
                        onTap: _valid ? _submit : () {},
                        child: Opacity(
                          opacity: _valid ? 1 : 0.45,
                          child: Container(
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: MizdahTokens.heroGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text(
                              'Update password',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PwField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final ValueChanged<String> onChanged;
  final Widget? trailing;
  const _PwField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: MizdahTokens.bg(context),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: MizdahTokens.border(context), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded,
              color: MizdahTokens.mutedOf(context), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: onChanged,
              style: TextStyle(
                color: MizdahTokens.inkOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 16),
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  color: MizdahTokens.mutedOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
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
      onTap: () async {
        if (text.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
            content: Text('Account ID copied'),
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
