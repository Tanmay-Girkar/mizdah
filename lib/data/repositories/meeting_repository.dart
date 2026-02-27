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
      final dynamic data = response.data;
      if (data is Map<String, dynamic>) {
        final Map<String, dynamic> meetingData = data.containsKey('data') 
            ? (data['data'] as Map<String, dynamic>)
            : (data.containsKey('meeting') ? (data['meeting'] as Map<String, dynamic>) : data);
        return Meeting.fromJson(meetingData);
      }
      throw Exception('Server returned invalid data format');
    } catch (e) {
      print('Error creating meeting: $e');
      rethrow;
    }
  }

  Future<Meeting?> getMeetingInfo(String code) async {
    try {
      final response = await _apiClient.get('${ApiConfig.getMeeting}/$code');
      final dynamic data = response.data;
      if (data is Map<String, dynamic>) {
        final Map<String, dynamic> meetingData = data.containsKey('data') 
            ? (data['data'] as Map<String, dynamic>)
            : (data.containsKey('meeting') ? (data['meeting'] as Map<String, dynamic>) : data);
        return Meeting.fromJson(meetingData);
      }
      return null;
    } catch (e) {
      print('Error fetching meeting info: $e');
      return null;
    }
  }

  Future<List<Meeting>> getMeetingsByHost(String userId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.userMeetings}/$userId');
      final dynamic data = response.data;
      List rawList = [];
      if (data is Map && data.containsKey('data')) {
        rawList = data['data'] as List;
      } else if (data is List) {
        rawList = data;
      }
      return rawList.map((json) => Meeting.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching meetings by host: $e');
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
