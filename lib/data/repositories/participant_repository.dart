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
      final List data = response.data is List ? response.data : (response.data['data'] ?? []);
      return data.map((json) => CallHistory.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getMeetingParticipants(String meetingId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.meetingParticipants}/$meetingId');
      return response.data is List ? response.data : (response.data['data'] ?? []);
    } catch (e) {
      return [];
    }
  }
}

final participantRepositoryProvider = Provider((ref) => ParticipantRepository());
