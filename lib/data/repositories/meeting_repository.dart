import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class MeetingRepository {
  final ApiClient _apiClient = ApiClient();

  Future<Meeting> createMeeting({String? hostId, String? customId, String? type}) async {
    try {
      final response = await _apiClient.post(ApiConfig.createMeeting, data: {
        if (hostId != null) 'hostId': hostId,
        if (customId != null) 'id': customId,
        if (type != null) 'type': type,
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
      debugPrint('Error creating meeting: $e');
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
      debugPrint('Error fetching meeting info: $e');
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
      debugPrint('Error fetching meetings by host: $e');
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

  // Waiting Room Management
  Future<List<Map<String, dynamic>>> getWaitingParticipants(String meetingId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.waitingRoomWaiting}/$meetingId');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching waiting participants: $e');
      return [];
    }
  }

  Future<bool> admitParticipant(String socketId) async {
    try {
      final response = await _apiClient.post(ApiConfig.waitingRoomAdmit, data: {'socketId': socketId});
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error admitting participant via REST: $e');
      return false;
    }
  }

  Future<bool> denyParticipant(String socketId) async {
    try {
      final response = await _apiClient.post(ApiConfig.waitingRoomDeny, data: {'socketId': socketId});
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error denying participant via REST: $e');
      return false;
    }
  }
}

final meetingRepositoryProvider = Provider((ref) => MeetingRepository());
