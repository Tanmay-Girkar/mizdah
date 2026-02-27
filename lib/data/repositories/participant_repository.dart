import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class ParticipantRepository {
  final ApiClient _apiClient = ApiClient();

  Future<void> logJoin(String meetingId, String userId) async {
    try {
      await _apiClient.post(ApiConfig.participantJoin, data: {
        'meetingId': meetingId,
        'userId': userId,
      });
    } catch (e) {
      // Log error but don't necessarily crash the join flow
      print('Error logging participant join: $e');
    }
  }

  Future<void> logLeave(String meetingId, String userId) async {
    try {
      await _apiClient.post(ApiConfig.participantLeave, data: {
        'meetingId': meetingId,
        'userId': userId,
      });
    } catch (e) {
      print('Error logging participant leave: $e');
    }
  }

  Future<List<CallHistory>> getUserHistory(String userId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.userParticipation}/$userId');
      final dynamic data = response.data;
      List rawList = [];
      if (data is Map && data.containsKey('data')) {
        rawList = data['data'] as List;
      } else if (data is List) {
        rawList = data;
      }
      return rawList.map((json) => CallHistory.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching user history: $e');
      return [];
    }
  }

  Future<List<dynamic>> getMeetingParticipants(String meetingId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.meetingParticipants}/$meetingId');
      final dynamic data = response.data;
      if (data is Map && data.containsKey('data')) {
        return data['data'] as List;
      } else if (data is List) {
        return data;
      }
      return [];
    } catch (e) {
      print('Error fetching meeting participants: $e');
      return [];
    }
  }
}

final participantRepositoryProvider = Provider((ref) => ParticipantRepository());
