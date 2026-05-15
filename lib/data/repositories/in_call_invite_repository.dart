import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../models/models.dart';

/// One typed error per documented backend `code` in
/// docs/ADD_PARTICIPANT_BACKEND.md §2/§3/§2b. Callers `switch` on
/// the runtime type to pick the right user-facing snackbar; falling
/// back to the generic [InCallInviteFailure] keeps the call sites
/// from blowing up when the backend introduces a new code we
/// haven't mapped yet.
sealed class InCallInviteError implements Exception {
  final String message;
  const InCallInviteError(this.message);
  @override
  String toString() => message;
}

class InviteNotAllowedByHostError extends InCallInviteError {
  const InviteNotAllowedByHostError(super.message);
}

class ForbiddenNotParticipantError extends InCallInviteError {
  const ForbiddenNotParticipantError(super.message);
}

class ForbiddenNotHostError extends InCallInviteError {
  const ForbiddenNotHostError(super.message);
}

class AlreadyInMeetingError extends InCallInviteError {
  const AlreadyInMeetingError(super.message);
}

class CannotInviteSelfError extends InCallInviteError {
  const CannotInviteSelfError(super.message);
}

class MeetingFullError extends InCallInviteError {
  const MeetingFullError(super.message);
}

class AlreadyPromotedError extends InCallInviteError {
  const AlreadyPromotedError(super.message);
}

class RateLimitedError extends InCallInviteError {
  const RateLimitedError(super.message);
}

class InCallInviteFailure extends InCallInviteError {
  const InCallInviteFailure(super.message);
}

/// Result of a successful `inviteToLiveMeeting` call.
class InviteResult {
  final String inviteId;
  final String inviteeUserId;
  final String meetingCode;

  const InviteResult({
    required this.inviteId,
    required this.inviteeUserId,
    required this.meetingCode,
  });

  factory InviteResult.fromJson(Map<String, dynamic> json) {
    return InviteResult(
      inviteId: json['inviteId']?.toString() ?? '',
      inviteeUserId: json['inviteeUserId']?.toString() ?? '',
      meetingCode: json['meetingCode']?.toString() ?? '',
    );
  }
}

/// Result of a successful `promoteToMeeting` call.
class PromotionResult {
  final String meetingId;
  final String meetingCode;
  final String inviteId;

  const PromotionResult({
    required this.meetingId,
    required this.meetingCode,
    required this.inviteId,
  });

  factory PromotionResult.fromJson(Map<String, dynamic> json) {
    return PromotionResult(
      meetingId: json['meetingId']?.toString() ?? '',
      meetingCode: json['meetingCode']?.toString() ?? '',
      inviteId: json['inviteId']?.toString() ?? '',
    );
  }
}

/// Wraps the three endpoints from docs/ADD_PARTICIPANT_BACKEND.md.
/// All three are JWT-gated; the ApiClient interceptor attaches the
/// bearer header for us so call sites don't think about auth.
class InCallInviteRepository {
  final ApiClient _apiClient;

  InCallInviteRepository(this._apiClient);

  /// `POST /api/meeting/:id/invite-in-call`
  ///
  /// Server-side validation:
  /// - caller must be active in the meeting (FORBIDDEN_NOT_PARTICIPANT)
  /// - if `permissions.allowParticipantsToInvite == false`, caller
  ///   must be the host (INVITE_NOT_ALLOWED_BY_HOST)
  /// - invitee must be a Mizdah user (INVITEE_NOT_FOUND)
  /// - per-meeting cap (MEETING_FULL), rate limit (RATE_LIMITED)
  ///
  /// Exactly one of [inviteeUserId] / [inviteeEmail] is required.
  /// `userId` is preferred when known (cheaper server lookup).
  Future<InviteResult> inviteToLiveMeeting({
    required String meetingId,
    String? inviteeUserId,
    String? inviteeEmail,
  }) async {
    assert(inviteeUserId != null || inviteeEmail != null,
        'must supply one of inviteeUserId or inviteeEmail');
    try {
      final response = await _apiClient.post(
        '${ApiConfig.meetingBase}/$meetingId/invite-in-call',
        data: {
          if (inviteeUserId != null && inviteeUserId.isNotEmpty)
            'inviteeUserId': inviteeUserId,
          if (inviteeEmail != null && inviteeEmail.isNotEmpty)
            'inviteeEmail': inviteeEmail,
        },
      );
      return InviteResult.fromJson(
          Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `POST /api/p2p-call/:callId/promote-to-meeting`
  ///
  /// Creates a meeting room server-side, fans `p2p:promoted` to both
  /// existing peers (they transparently move from P2P → SFU), and
  /// sends an `in_call_invite` to the third user.
  ///
  /// Non-idempotent — the SECOND call on the same callId returns
  /// `409 ALREADY_PROMOTED`, mapped to [AlreadyPromotedError].
  ///
  /// Exactly one of [inviteeUserId] / [inviteeEmail] is required.
  Future<PromotionResult> promoteToMeeting({
    required String callId,
    String? inviteeUserId,
    String? inviteeEmail,
  }) async {
    assert(inviteeUserId != null || inviteeEmail != null,
        'must supply one of inviteeUserId or inviteeEmail');
    try {
      final response = await _apiClient.post(
        '${ApiConfig.p2pCallBase}/$callId/promote-to-meeting',
        data: {
          if (inviteeUserId != null && inviteeUserId.isNotEmpty)
            'inviteeUserId': inviteeUserId,
          if (inviteeEmail != null && inviteeEmail.isNotEmpty)
            'inviteeEmail': inviteeEmail,
        },
      );
      return PromotionResult.fromJson(
          Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `PATCH /api/meeting/:id/permissions`
  ///
  /// Host-only — non-hosts get FORBIDDEN_NOT_HOST. Partial-update
  /// semantics: keys absent from [permissions.toJson] are untouched
  /// on the server side. Server emits `meeting:permissions-changed`
  /// on the meeting room so every participant updates in real time.
  Future<MeetingPermissions> setPermissions({
    required String meetingId,
    required MeetingPermissions permissions,
  }) async {
    try {
      final response = await _apiClient.patch(
        '${ApiConfig.meetingBase}/$meetingId/permissions',
        data: permissions.toJson(),
      );
      final raw = response.data;
      if (raw is Map && raw['permissions'] is Map) {
        return MeetingPermissions.fromJson(
            Map<String, dynamic>.from(raw['permissions'] as Map));
      }
      // Older server build that doesn't wrap in `permissions` key —
      // tolerate by assuming the body itself is the new permissions
      // blob (matches the request shape).
      if (raw is Map) {
        return MeetingPermissions.fromJson(
            Map<String, dynamic>.from(raw));
      }
      return permissions;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Map the backend's typed `code` strings to a typed Dart class
  /// so call sites can `switch` on the failure mode instead of
  /// string-matching error messages.
  InCallInviteError _mapError(DioException e) {
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    final message = data is Map
        ? (data['error']?.toString() ?? 'Something went wrong')
        : 'Network error';
    switch (code) {
      case 'INVITE_NOT_ALLOWED_BY_HOST':
        return InviteNotAllowedByHostError(message);
      case 'FORBIDDEN_NOT_PARTICIPANT':
        return ForbiddenNotParticipantError(message);
      case 'FORBIDDEN_NOT_HOST':
        return ForbiddenNotHostError(message);
      case 'ALREADY_IN_MEETING':
        return AlreadyInMeetingError(message);
      case 'CANNOT_INVITE_SELF':
        return CannotInviteSelfError(message);
      case 'MEETING_FULL':
        return MeetingFullError(message);
      case 'ALREADY_PROMOTED':
        return AlreadyPromotedError(message);
      case 'RATE_LIMITED':
        return RateLimitedError(message);
      default:
        return InCallInviteFailure(message);
    }
  }
}

final inCallInviteRepositoryProvider = Provider<InCallInviteRepository>(
  (ref) => InCallInviteRepository(ApiClient()),
);
