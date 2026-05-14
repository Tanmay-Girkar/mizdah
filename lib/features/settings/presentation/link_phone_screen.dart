// ════════════════════════════════════════════════════════════════════
//  Link phone — add or change the user's phone number
//  ────────────────────────────────────────────────────────────────────
//  Reachable from Settings → Account → Edit profile → Phone number.
//
//  Wired up:
//    • Phone + country → POST /api/auth/update {phone, phone_country}
//
//  No OTP. The user types a number, taps Save, the backend stores it.
//  See docs/PHONE_LINK_BACKEND.md for the full backend spec including
//  the security tradeoff we accepted by skipping verification.
// ════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';

import '../../../core/ui/mizdah_design.dart';
import '../../auth/auth_provider.dart';
import '../../call/contacts_provider.dart';

class LinkPhoneScreen extends ConsumerStatefulWidget {
  const LinkPhoneScreen({super.key});

  @override
  ConsumerState<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends ConsumerState<LinkPhoneScreen> {
  // Mirrors the register screen's phone-input plumbing. IntlPhoneField
  // gives us the full E.164 string and the ISO country code on each
  // `onChanged`. We carry both through to /api/auth/update.
  String _phoneE164 = '';
  String _phoneCountryIso = 'IN';
  bool _phoneIsValid = false;

  bool _saving = false;
  String? _error;
  String? _initialPhone;
  String? _initialCountry;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _initialPhone = user?.phone;
    _initialCountry = user?.phoneCountry ?? 'IN';
    if (_initialPhone != null) {
      _phoneE164 = _initialPhone!;
      _phoneCountryIso = _initialCountry!;
    }
  }

  Future<void> _save() async {
    if (!_phoneIsValid || _phoneE164.isEmpty) {
      setState(() => _error = 'Enter a valid phone number');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).updateProfile(
            phone: _phoneE164,
            phoneCountry: _phoneCountryIso,
          );
      if (!mounted) return;
      // Re-sync contacts so anyone whose address book has THIS number
      // sees us appear in their Mizdah-contacts list immediately on
      // their next sync — and conversely, if their default-region
      // changes because of the country we just set, we re-derive their
      // local matches with the right region.
      // ignore: discarded_futures
      ref.read(contactsProvider.notifier).sync();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number saved')),
      );
      context.pop();
    } catch (e) {
      // Surface the backend's machine-readable code when possible. The
      // codes are documented in docs/PHONE_LINK_BACKEND.md §2.5:
      //   INVALID_PHONE / INVALID_PHONE_COUNTRY → 400
      //   PHONE_ALREADY_TAKEN                   → 409
      String message = 'Could not save. Try again.';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final code = body['code']?.toString();
          final human = body['error']?.toString() ?? body['message']?.toString();
          if (code == 'PHONE_ALREADY_TAKEN') {
            message =
                'This number is already linked to another Mizdah account.';
          } else if (code == 'INVALID_PHONE' ||
              code == 'INVALID_PHONE_COUNTRY') {
            message = 'Phone number isn\'t valid for the selected country.';
          } else if (human != null && human.isNotEmpty) {
            message = human;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isChanging = (user?.phone ?? '').isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(isChanging ? 'Change phone number' : 'Link phone number'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Explainer card ──────────────────────────────────
              MizdahCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: MizdahTokens.heroGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phone_iphone_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isChanging
                                ? 'Change your number'
                                : 'Be findable by your number',
                            style: TextStyle(
                              color: MizdahTokens.inkOf(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isChanging
                                ? 'Update the phone number friends use to find '
                                    'you on Mizdah. The old number is replaced.'
                                : 'Anyone who has your phone number saved in '
                                    'their contacts will see you under "Mizdah '
                                    'contacts" and can call you in one tap.',
                            style: TextStyle(
                              color: MizdahTokens.mutedOf(context),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Phone field ─────────────────────────────────────
              _PhoneField(
                initialCountry: _initialCountry ?? 'IN',
                initialNumber: _stripCountryCode(
                  _initialPhone ?? '',
                  _initialCountry,
                ),
                onChanged: (p) {
                  setState(() {
                    _phoneE164 = p.completeNumber;
                    _phoneCountryIso = p.countryISOCode;
                    _phoneIsValid = p.isValidNumber();
                    if (_error != null) _error = null;
                  });
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFB42318), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFB42318),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const Spacer(),

              // ── Save button ─────────────────────────────────────
              _SaveBtn(
                label: isChanging ? 'Save changes' : 'Save number',
                busy: _saving,
                onTap: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// IntlPhoneField wants the NATIONAL number (without the +CC prefix),
  /// because the country code lives in its picker. The user object
  /// stores the full E.164 string. Strip the prefix so the user sees
  /// their existing digits when re-editing.
  String _stripCountryCode(String e164, String? countryIso) {
    if (e164.isEmpty || !e164.startsWith('+')) return '';
    // Try to find a digit boundary by length — Indian numbers are
    // +91 followed by 10 digits, US are +1 followed by 10, etc.
    // libphonenumber has the canonical way; for the prefill we just
    // chop off the +CC heuristically. The user can always re-type
    // if it looks wrong.
    final byCountry = <String, int>{
      'IN': 3, // +91
      'US': 2, // +1
      'GB': 3, // +44
      'AE': 4, // +971
    };
    final stripLen = byCountry[(countryIso ?? '').toUpperCase()] ?? 3;
    return e164.length > stripLen ? e164.substring(stripLen) : '';
  }
}

class _PhoneField extends StatelessWidget {
  final String initialCountry;
  final String initialNumber;
  final ValueChanged<PhoneNumber> onChanged;
  const _PhoneField({
    required this.initialCountry,
    required this.initialNumber,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.grey.shade100;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.transparent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone',
          style: TextStyle(
            color: MizdahTokens.mutedOf(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        IntlPhoneField(
          initialCountryCode: initialCountry,
          initialValue: initialNumber.isEmpty ? null : initialNumber,
          onChanged: onChanged,
          dropdownTextStyle: TextStyle(
            color: MizdahTokens.inkOf(context),
            fontSize: 15,
          ),
          dropdownIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: MizdahTokens.mutedOf(context),
          ),
          flagsButtonPadding: const EdgeInsets.symmetric(horizontal: 8),
          style: TextStyle(
            color: MizdahTokens.inkOf(context),
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Phone number',
            hintStyle: TextStyle(
              color: MizdahTokens.mutedOf(context).withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveBtn extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  const _SaveBtn({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MizdahPressScale(
      scaleTo: 0.96,
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: onTap == null ? null : MizdahTokens.heroGradient,
          color: onTap == null
              ? MizdahTokens.mutedOf(context).withValues(alpha: 0.18)
              : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: onTap == null
              ? null
              : [
                  BoxShadow(
                    color: MizdahTokens.primary.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
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
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
