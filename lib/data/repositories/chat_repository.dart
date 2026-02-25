import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class ChatRepository {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> sendMessage({
    required String meetingId,
    required String senderId,
    required String senderName,
    required String content,
    String? recipientId,
    String? recipientName,
    String? attachmentUrl,
  }) async {
    try {
      final response = await _apiClient.post(ApiConfig.chatSend, data: {
        'meetingId': meetingId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'recipientId': recipientId,
        'recipientName': recipientName,
        'attachmentUrl': attachmentUrl,
      });
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getChatHistory(String meetingId, String userId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.chatHistory}/$meetingId', queryParameters: {
        'userId': userId,
      });
      final List data = response.data is List ? response.data : (response.data['data'] ?? []);
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _apiClient.delete('${ApiConfig.chatHistory}/$messageId');
    } catch (e) {
      rethrow;
    }
  }
}

final chatRepositoryProvider = Provider((ref) => ChatRepository());
