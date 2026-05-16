// ════════════════════════════════════════════════════════════════════
//  HostManagementRepository — wraps the four host-management endpoints
//  ────────────────────────────────────────────────────────────────────
//  See docs/HOST_MANAGEMENT_BACKEND.md §7 for the contract.
//
//    PATCH  /api/meeting/:id/participants/:userId/role
//    POST   /api/meeting/:id/transfer-host
//    POST   /api/meeting/:id/resume-host
//    GET    /api/meeting/:id/audit
//
//  Typed sealed error hierarchy keyed off each backend `code` string
//  — call sites switch on the runtime type to pick the right
//  snackbar / inline message, falling back to [HostManagementFailure]
//  when the backend introduces a code we haven't mapped yet.
// ════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';

/// Role tiers from docs/HOST_MANAGEMENT_BACKEND.md §1. Backend
/// stores as VARCHAR(16) so adding a new tier later is a code
/// change, not a migration.
enum MeetingRole {
  host,
  coHost,
  participant;

  /// Wire form — the literal string the backend reads/writes.
  String get wire => switch (this) {
        MeetingRole.host => 'host',
        MeetingRole.coHost => 'co_host',
        MeetingRole.participant => 'participant',
      };

  static MeetingRole parse(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'host':
        return MeetingRole.host;
      case 'co_host':
      case 'cohost':
      case 'co-host':
        return MeetingRole.coHost;
      default:
        return MeetingRole.participant;
    }
  }
}

// ── Sealed error hierarchy ────────────────────────────────────────

sealed class HostManagementError implements Exception {
  final String message;
  const HostManagementError(this.message);
  @override
  String toString() => message;
}

class InvalidRoleError extends HostManagementError {
  const InvalidRoleError(super.message);
}

class CannotDemoteHostViaRoleError extends HostManagementError {
  const CannotDemoteHostViaRoleError(super.message);
}

class CannotTransferToSelfError extends HostManagementError {
  const CannotTransferToSelfError(super.message);
}

class TargetNotActiveError extends HostManagementError {
  const TargetNotActiveError(super.message);
}

class HostManagementForbiddenError extends HostManagementError {
  const HostManagementForbiddenError(super.message);
}

class HostManagementNotFoundError extends HostManagementError {
  const HostManagementNotFoundError(super.message);
}

class ResumeTokenInvalidError extends HostManagementError {
  const ResumeTokenInvalidError(super.message);
}

class ResumeWindowExpiredError extends HostManagementError {
  const ResumeWindowExpiredError(super.message);
}

class MeetingNotActiveError extends HostManagementError {
  const MeetingNotActiveError(super.message);
}

class HostManagementFailure extends HostManagementError {
  const HostManagementFailure(super.message);
}

class HostManagementRepository {
  final ApiClient _apiClient;

  HostManagementRepository(this._apiClient);

  /// `PATCH /api/meeting/:id/participants/:userId/role`
  ///
  /// Host-only. Setting `role: host` is an implicit transfer —
  /// the backend equates it with calling `/transfer-host`. We
  /// disallow that here too so the verb is explicit at call
  /// sites; use [transferHost] when you mean a transfer.
  Future<MeetingRole> setRole({
    required String meetingId,
    required String participantUserId,
    required MeetingRole role,
  }) async {
    assert(role != MeetingRole.host,
        'Use transferHost() to set someone as the new host.');
    try {
      final response = await _apiClient.patch(
        '${ApiConfig.meetingBase}/$meetingId/participants/'
        '$participantUserId/role',
        data: {'role': role.wire},
      );
      final raw = response.data;
      if (raw is Map) {
        return MeetingRole.parse(raw['role']?.toString());
      }
      return role;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `POST /api/meeting/:id/transfer-host`
  ///
  /// Host-only. Atomically swaps host_id + the two participant
  /// rows' roles + emits meeting:host_changed with
  /// `reason: "manual"` to the room.
  Future<({String newHostUserId, String previousHostUserId})>
      transferHost({
    required String meetingId,
    required String toUserId,
  }) async {
    try {
      final response = await _apiClient.post(
        '${ApiConfig.meetingBase}/$meetingId/transfer-host',
        data: {'toUserId': toUserId},
      );
      final raw = response.data;
      if (raw is Map) {
        return (
          newHostUserId: raw['newHostUserId']?.toString() ?? toUserId,
          previousHostUserId:
              raw['previousHostUserId']?.toString() ?? '',
        );
      }
      return (newHostUserId: toUserId, previousHostUserId: '');
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `POST /api/meeting/:id/resume-host`
  ///
  /// Host's reconnect path — submits the one-time `sessionToken`
  /// delivered out-of-band via FCM during the 45 s grace window.
  /// Returns void on success; throws [ResumeTokenInvalidError]
  /// or [ResumeWindowExpiredError] on the documented failure
  /// modes (caller usually swallows — these aren't retryable).
  Future<void> resumeHost({
    required String meetingId,
    required String sessionToken,
  }) async {
    try {
      await _apiClient.post(
        '${ApiConfig.meetingBase}/$meetingId/resume-host',
        data: {'sessionToken': sessionToken},
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// `GET /api/meeting/:id/audit`
  ///
  /// Host-only paginated audit log. Returns the parsed rows +
  /// cursor for the next page.
  Future<({List<MeetingAuditEntry> rows, String? nextCursor})>
      getAudit({
    required String meetingId,
    int? limit,
    String? before,
  }) async {
    try {
      final response = await _apiClient.get(
        '${ApiConfig.meetingBase}/$meetingId/audit',
        queryParameters: {
          if (limit != null) 'limit': limit,
          if (before != null) 'before': before,
        },
      );
      final raw = response.data;
      if (raw is! Map) {
        return (rows: <MeetingAuditEntry>[], nextCursor: null);
      }
      final list = raw['data'];
      final rows = (list is List)
          ? list
              .whereType<Map>()
              .map((m) => MeetingAuditEntry.fromJson(
                  Map<String, dynamic>.from(m)))
              .toList()
          : <MeetingAuditEntry>[];
      final next = raw['nextCursor'] ?? raw['next_cursor'];
      return (
        rows: rows,
        nextCursor: next is String ? next : null,
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  HostManagementError _mapError(DioException e) {
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    final message = data is Map
        ? (data['error']?.toString() ?? 'Something went wrong')
        : 'Network error';
    switch (code) {
      case 'INVALID_ROLE':
        return InvalidRoleError(message);
      case 'CANNOT_DEMOTE_HOST_VIA_ROLE':
        return CannotDemoteHostViaRoleError(message);
      case 'CANNOT_TRANSFER_TO_SELF':
        return CannotTransferToSelfError(message);
      case 'TARGET_NOT_ACTIVE':
      case 'PARTICIPANT_NOT_FOUND':
        return TargetNotActiveError(message);
      case 'FORBIDDEN_NOT_HOST':
        return HostManagementForbiddenError(message);
      case 'MEETING_NOT_FOUND':
        return HostManagementNotFoundError(message);
      case 'RESUME_TOKEN_INVALID':
        return ResumeTokenInvalidError(message);
      case 'RESUME_WINDOW_EXPIRED':
        return ResumeWindowExpiredError(message);
      case 'MEETING_NOT_ACTIVE':
        return MeetingNotActiveError(message);
      default:
        return HostManagementFailure(message);
    }
  }
}

class MeetingAuditEntry {
  final String id;
  final String? actorId;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime at;

  const MeetingAuditEntry({
    required this.id,
    required this.actorId,
    required this.eventType,
    required this.payload,
    required this.at,
  });

  factory MeetingAuditEntry.fromJson(Map<String, dynamic> j) {
    final rawPayload = j['payload'];
    return MeetingAuditEntry(
      id: j['id']?.toString() ?? '',
      actorId: j['actorId']?.toString() ?? j['actor_id']?.toString(),
      eventType:
          (j['eventType'] ?? j['event_type'])?.toString() ?? 'unknown',
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const {},
      at: DateTime.tryParse((j['at'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
    );
  }
}

final hostManagementRepositoryProvider =
    Provider<HostManagementRepository>(
  (ref) => HostManagementRepository(ApiClient()),
);
