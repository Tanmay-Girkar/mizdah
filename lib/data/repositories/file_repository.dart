import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

class FileRepository {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> uploadFile(File file) async {
    try {
      String fileName = file.path.split('/').last;
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await _apiClient.postMultipart(ApiConfig.fileUpload, formData);
      if (response.data is! Map) return {'error': 'Invalid format'};
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getFileMetadata(String fileId) async {
    try {
      final response = await _apiClient.get('${ApiConfig.files}/$fileId');
      if (response.data is! Map) return {'error': 'Invalid format'};
      return response.data;
    } catch (e) {
      rethrow;
    }
  }
}

final fileRepositoryProvider = Provider((ref) => FileRepository());
