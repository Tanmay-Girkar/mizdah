import '../models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';
import '../../features/auth/auth_provider.dart';

abstract class MizdahRepository {
  Future<List<Contact>> getContacts();
  Future<List<Meeting>> getMeetings();
  Future<List<CallHistory>> getCallHistory();
  Future<Meeting> createMeeting({required String title, required DateTime dateTime, String? code});
  Future<Meeting?> getMeetingByCode(String code);
}

class RealMizdahRepository implements MizdahRepository {
  final ApiClient _apiClient;
  final String? _currentUserId;

  RealMizdahRepository(this._apiClient, this._currentUserId);

  @override
  Future<List<Contact>> getContacts() async {
    try {
      final response = await _apiClient.get(ApiConfig.adminUsers);
      final List data = response.data['users'] ?? response.data;
      return data.map((json) => Contact.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<Meeting>> getMeetings() async {
    if (_currentUserId == null) return [];
    try {
      final response = await _apiClient.get('${ApiConfig.scheduling}/user/$_currentUserId');
      final List data = response.data['data'] ?? response.data;
      return data.map((json) => Meeting.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<CallHistory>> getCallHistory() async {
    if (_currentUserId == null) return [];
    try {
      final response = await _apiClient.get('${ApiConfig.userParticipation}/$_currentUserId');
      final List data = response.data['data'] ?? response.data;
      return data.map((json) => CallHistory.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Meeting> createMeeting({required String title, required DateTime dateTime, String? code}) async {
    if (_currentUserId == null) throw Exception("Not logged in");
    try {
      // Backend renamed `title` → `topic` (verified by 400 response
      // "Meeting topic is required" against /api/meetings/create on
      // 2026-05-09). Send both keys so this client keeps working
      // against older/newer service versions; whichever the backend
      // reads, the other is ignored.
      final response = await _apiClient.post(ApiConfig.createMeeting, data: {
        'hostId': _currentUserId,
        'topic': title,
        'title': title,
        'scheduledFor': dateTime.toIso8601String(),
        if (code != null) 'id': code,
        if (code != null) 'meeting_code': code,
      });
      return Meeting.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to create meeting: $e');
    }
  }

  @override
  Future<Meeting?> getMeetingByCode(String code) async {
    try {
      final response = await _apiClient.get('${ApiConfig.getMeeting}/$code');
      return Meeting.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }
}

final mizdahRepositoryProvider = Provider<MizdahRepository>((ref) {
  final user = ref.watch(authProvider).user;
  return RealMizdahRepository(ApiClient(), user?.id);
});
