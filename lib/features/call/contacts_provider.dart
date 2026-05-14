// ════════════════════════════════════════════════════════════════════
//  Contacts Provider — Riverpod state for the Call-tab address book
//  ────────────────────────────────────────────────────────────────────
//  Owns:
//    • the current list of matched Mizdah contacts
//    • the list of "not on Mizdah" device contacts (for the Invite UI)
//    • the last-synced timestamp
//    • the permission state (granted / denied / unknown)
//
//  Provides actions:
//    • `requestAndSync()` — prompt for contacts permission, then sync
//    • `sync()`           — sync without prompting (assumes permission)
//    • `clearOnLogout()`  — drop the matched cache so the next user
//                           doesn't see the previous user's contacts
//
//  Auto-syncs on first read if:
//    • permission already granted, AND
//    • either no cache exists OR cache is older than 6 hours.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/contacts_service.dart';
import '../../data/models/contact_models.dart';
import '../../data/repositories/contacts_repository.dart';
import '../auth/auth_provider.dart';

enum ContactsPermissionState { unknown, granted, denied }

class ContactsState {
  final ContactsPermissionState permission;
  final List<MizdahContact> matched;
  final List<DeviceContact> invitable;
  final DateTime? lastSyncedAt;
  final bool syncing;
  final String? errorMessage;

  const ContactsState({
    this.permission = ContactsPermissionState.unknown,
    this.matched = const [],
    this.invitable = const [],
    this.lastSyncedAt,
    this.syncing = false,
    this.errorMessage,
  });

  ContactsState copyWith({
    ContactsPermissionState? permission,
    List<MizdahContact>? matched,
    List<DeviceContact>? invitable,
    DateTime? lastSyncedAt,
    bool? syncing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ContactsState(
      permission: permission ?? this.permission,
      matched: matched ?? this.matched,
      invitable: invitable ?? this.invitable,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncing: syncing ?? this.syncing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ContactsNotifier extends StateNotifier<ContactsState> {
  ContactsNotifier(this._ref) : super(const ContactsState()) {
    _bootstrap();
    // Wipe matched-contact cache when the user logs out so the next
    // account signing in on the same device doesn't briefly see the
    // previous user's friends list.
    _ref.listen<AuthState>(authProvider, (prev, next) {
      final wasIn = prev?.status == AuthStatus.authenticated;
      final outNow = next.status == AuthStatus.unauthenticated;
      if (wasIn && outNow) {
        // ignore: discarded_futures
        clearOnLogout();
      }
    });
  }

  final Ref _ref;
  final ContactsRepository _repo = ContactsRepository();

  /// On startup: paint the cached list immediately, check permission
  /// status, and ALWAYS kick a sync in the background when permission
  /// is granted.
  ///
  /// We deliberately don't gate on cache staleness any more. The
  /// `invitable` list (device contacts NOT on Mizdah) isn't persisted
  /// across cold boots — only the matched-user cache is — so without
  /// a sync on bootstrap, a returning user sees an empty Call tab
  /// until they pull-to-refresh. With this change the bootstrap fires
  /// the sync immediately and the list paints within a second.
  ///
  /// Rate-limiting concern: the spec allows 100 sync requests / hour
  /// per token. Even a chatty user opening the app 20x a day stays
  /// well under the cap.
  Future<void> _bootstrap() async {
    final cached = await _repo.loadCached();
    final cachedInvitable = await _repo.loadCachedInvitable();
    final lastAt = await _repo.lastSyncedAt();
    final granted = await ContactsService.instance.hasPermission();
    state = state.copyWith(
      matched: cached,
      invitable: cachedInvitable,
      lastSyncedAt: lastAt,
      permission: granted
          ? ContactsPermissionState.granted
          : ContactsPermissionState.unknown,
    );
    debugPrint('[contacts-provider] bootstrap '
        'cachedMatched=${cached.length} '
        'cachedInvitable=${cachedInvitable.length} '
        'lastSyncedAt=$lastAt '
        'permissionGranted=$granted');

    if (granted) {
      // ignore: discarded_futures
      sync();
    }
  }

  /// Resolve the user's home country code for phone normalisation.
  /// Prefers the explicit `phone_country` on their user object, falls
  /// back to `IN` since that's our primary market and matches the
  /// register screen's default.
  String _defaultRegion() {
    final user = _ref.read(authProvider).user;
    return user?.phoneCountry?.toUpperCase() ?? 'IN';
  }

  /// Prompt for permission (if needed), then sync. Returns true on
  /// successful sync, false if permission was denied.
  Future<bool> requestAndSync() async {
    final granted = await ContactsService.instance.requestPermission();
    if (!granted) {
      state = state.copyWith(permission: ContactsPermissionState.denied);
      return false;
    }
    state = state.copyWith(permission: ContactsPermissionState.granted);
    await sync();
    return true;
  }

  /// Run a sync — assumes permission is granted. Idempotent; if
  /// already syncing, the second call no-ops.
  Future<void> sync() async {
    if (state.syncing) {
      debugPrint('[contacts-provider] sync skipped — already in flight');
      return;
    }
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final result = await _repo.sync(defaultRegion: _defaultRegion());
      if (result == null) {
        state = state.copyWith(
          syncing: false,
          permission: ContactsPermissionState.denied,
          errorMessage: 'Contacts permission not granted',
        );
        return;
      }
      state = state.copyWith(
        syncing: false,
        permission: ContactsPermissionState.granted,
        matched: result.matched,
        invitable: result.invitable,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[contacts-provider] sync failed: $e');
      state = state.copyWith(
        syncing: false,
        errorMessage: 'Could not sync contacts. Pull to retry.',
      );
    }
  }

  /// Called from auth logout to clear cached matches.
  Future<void> clearOnLogout() async {
    await _repo.clearCache();
    state = const ContactsState();
  }
}

final contactsProvider =
    StateNotifierProvider<ContactsNotifier, ContactsState>(
  (ref) => ContactsNotifier(ref),
);
