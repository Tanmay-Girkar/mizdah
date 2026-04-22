import 'package:flutter/foundation.dart';
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
      debugPrint('Error logging participant join: $e');
    }
  }

  Future<void> logLeave(String meetingId, String userId) async {
    try {
      await _apiClient.post(ApiConfig.participantLeave, data: {
        'meetingId': meetingId,
        'userId': userId,
      });
    } catch (e) {
      debugPrint('Error logging participant leave: $e');
    }
  }

  static const List<Map<String, dynamic>> _integratedMeetings = [
    {
      "id": "5cceddfd-8260-4e2b-ab91-c0cc9dbda5b9",
      "meeting_code": "auixqlkbpu",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-22T05:56:18.368Z"
    },
    {
      "id": "67c04e39-b35a-48d2-a0ee-a42ece868b53",
      "meeting_code": "wgcsunjhkc",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-22T05:54:39.860Z"
    },
    {
      "id": "abd9a4e3-310f-4e2f-a207-c235d4aca016",
      "meeting_code": "cywdvdvnjp",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-22T04:02:26.506Z"
    },
    {
      "id": "6ee9bc11-0bb8-4ef2-a119-34fc11c6cd5e",
      "meeting_code": "nmnjdhtvri",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:38:03.733Z"
    },
    {
      "id": "894f384a-70d8-4b75-9603-3107c830d008",
      "meeting_code": "ofivsxhldc",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:23:29.649Z"
    },
    {
      "id": "2ea3eb1a-9b04-42be-ae82-c671329a9ea2",
      "meeting_code": "fufqqssjjl",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:23:22.394Z"
    },
    {
      "id": "49c88abc-bc70-4a9b-9522-48dec3d68a10",
      "meeting_code": "lbaswouapv",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:23:12.037Z"
    },
    {
      "id": "dcb904d4-7f0e-43a7-be1e-0df5f3ab9d01",
      "meeting_code": "ijvolinhlz",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:13:22.503Z"
    },
    {
      "id": "5e006804-e918-41a2-86a4-72feb33e3a45",
      "meeting_code": "nnovxkjxkc",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:12:28.664Z"
    },
    {
      "id": "bb6ed959-b9ef-4236-bdb8-f58b49562a1b",
      "meeting_code": "gqkksjrmup",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:09:12.529Z"
    },
    {
      "id": "d74dd629-9005-4eaf-9bb1-595ea15edd7c",
      "meeting_code": "nsuaefmhiv",
      "host_id": "a7bae225-5f5a-40b6-b177-36cf1c0d3e48",
      "private_chat_enabled": true,
      "general_chat_enabled": true,
      "whiteboard_enabled": true,
      "screenshare_enabled": true,
      "reactions_enabled": true,
      "camera_enabled": true,
      "created_at": "2026-04-21T07:08:27.070Z"
    },
  ];

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

      // Merge with integrated meetings for demonstration/integration
      final integrated = _integratedMeetings.map((json) => CallHistory.fromJson(json)).toList();
      final history = rawList.map((json) => CallHistory.fromJson(json)).toList();
      
      final combined = [...history, ...integrated];

      // Sort by timestamp descending (most recent first)
      combined.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return combined;
    } catch (e) {
      debugPrint('Error fetching user history: $e');
      // Return integrated meetings as fallback if API fails
      return _integratedMeetings.map((json) => CallHistory.fromJson(json)).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
      debugPrint('Error fetching meeting participants: $e');
      return [];
    }
  }
}

final participantRepositoryProvider = Provider((ref) => ParticipantRepository());
