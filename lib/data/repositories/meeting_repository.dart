import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class MeetingRepository {
  final ApiClient _apiClient = ApiClient();

  Future<Meeting> createMeeting({String? hostId, String? customId}) async {
    try {
      final response = await _apiClient.post(ApiConfig.createMeeting, data: {
        if (hostId != null) 'hostId': hostId,
        if (customId != null) 'id': customId,
      });
      return Meeting.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Meeting?> getMeetingInfo(String code) async {
    try {
      final response = await _apiClient.get('${ApiConfig.getMeeting}/$code');
      return Meeting.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<List<Meeting>> getMeetingsByHost(String userId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.userMeetings}/$userId');
      final List data = response.data is List ? response.data : (response.data['data'] ?? []);
      return data.map((json) => Meeting.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Meeting> updateSettings(String code, Map<String, dynamic> settings) async {
    try {
      final response = await _apiClient.patch('${ApiConfig.getMeeting}/$code/settings', data: settings);
      return Meeting.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }
}

final meetingRepositoryProvider = Provider((ref) => MeetingRepository());
