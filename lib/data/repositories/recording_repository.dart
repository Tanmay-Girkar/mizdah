import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class RecordingRepository {
  final ApiClient _apiClient = ApiClient();

  Future<void> startRecording(String meetingId) async {
    try {
      await _apiClient.post('${ApiConfig.recordingStart}/$meetingId');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> stopRecording(String meetingId) async {
    try {
      await _apiClient.post('${ApiConfig.recordingStop}/$meetingId');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> getRecordings(String meetingId) async {
    try {
      // Assuming a GET endpoint exists based on the docs
      final response = await _apiClient.get('${ApiConfig.baseUrl}/api/recording/$meetingId');
      return response.data is List ? response.data : (response.data['data'] ?? []);
    } catch (e) {
      return [];
    }
  }
}
