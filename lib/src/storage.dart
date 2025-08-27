import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

import 'exceptions.dart';
import 'models/strapi_file.dart';
import 'utils/http_client.dart';

/// File upload service for Strapi integration.
class LDKStorage {
  /// Creates a new [LDKStorage] instance.
  LDKStorage(this._httpClient);

  final LDKHttpClient _httpClient;

  /// Uploads a single file to Strapi.
  Future<StrapiFile> upload(
    File file, {
    String? alternativeText,
    String? caption,
    Map<String, dynamic>? additionalData,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      if (!file.existsSync()) {
        throw LDKFileException('File does not exist: ${file.path}');
      }

      final mimeType = lookupMimeType(file.path);
      if (mimeType == null) {
        throw LDKFileException(
            'Could not determine MIME type for file: ${file.path}');
      }

      final data = <String, dynamic>{
        if (alternativeText != null) 'alternativeText': alternativeText,
        if (caption != null) 'caption': caption,
        ...?additionalData,
      };

      final response = await _httpClient.uploadFile<List<dynamic>>(
        '/api/upload',
        file,
        fieldName: 'files',
        data: data,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
      );

      if (response.data == null || response.data!.isEmpty) {
        throw const LDKFileException('Invalid response from server');
      }

      final fileData = response.data!.first as Map<String, dynamic>;
      return StrapiFile.fromJson(fileData);
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKFileException('File upload failed: ${e.toString()}',
          originalError: e);
    }
  }

  /// Uploads multiple files to Strapi.
  Future<List<StrapiFile>> uploadMultiple(
    List<File> files, {
    Map<String, dynamic>? additionalData,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      if (files.isEmpty) {
        throw const LDKFileException('No files provided for upload');
      }

      // Validate all files exist
      for (final file in files) {
        if (!file.existsSync()) {
          throw LDKFileException('File does not exist: ${file.path}');
        }
      }

      final response = await _httpClient.uploadFiles<List<dynamic>>(
        '/api/upload',
        files,
        fieldName: 'files',
        data: additionalData,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
      );

      if (response.data == null) {
        throw const LDKFileException('Invalid response from server');
      }

      final filesData = response.data! as List<dynamic>;
      return filesData
          .map((fileData) =>
              StrapiFile.fromJson(fileData as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKFileException('Multiple file upload failed: ${e.toString()}',
          originalError: e);
    }
  }

  /// Deletes a file from Strapi by ID.
  Future<void> delete(int fileId) async {
    try {
      await _httpClient
          .delete<Map<String, dynamic>>('/api/upload/files/$fileId');
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKFileException('File deletion failed: ${e.toString()}',
          originalError: e);
    }
  }

  /// Gets file information by ID.
  Future<StrapiFile> getById(int fileId) async {
    try {
      final response = await _httpClient.get<Map<String, dynamic>>(
        '/api/upload/files/$fileId',
      );

      if (response.data == null) {
        throw const LDKFileException('Invalid response from server');
      }

      return StrapiFile.fromJson(response.data!);
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKFileException('Failed to get file info: ${e.toString()}',
          originalError: e);
    }
  }

  /// Lists all uploaded files with optional filtering.
  Future<List<StrapiFile>> list({
    int? limit,
    int? start,
    String? sort,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (limit != null) queryParams['pagination[limit]'] = limit.toString();
      if (start != null) queryParams['pagination[start]'] = start.toString();
      if (sort != null) queryParams['sort'] = sort;

      if (filters != null) {
        for (final entry in filters.entries) {
          queryParams['filters[${entry.key}]'] = entry.value.toString();
        }
      }

      final response = await _httpClient.get<List<dynamic>>(
        '/api/upload/files',
        queryParameters: queryParams,
      );

      if (response.data == null) {
        throw const LDKFileException('Invalid response from server');
      }

      return response.data!
          .map((fileData) =>
              StrapiFile.fromJson(fileData as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKFileException('Failed to list files: ${e.toString()}',
          originalError: e);
    }
  }

  /// Updates file information (metadata only, not the file itself).
  Future<StrapiFile> updateInfo(
    int fileId, {
    String? name,
    String? alternativeText,
    String? caption,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name,
        if (alternativeText != null) 'alternativeText': alternativeText,
        if (caption != null) 'caption': caption,
        ...?additionalData,
      };

      if (data.isEmpty) {
        throw const LDKFileException('No data provided for update');
      }

      final response = await _httpClient.put<Map<String, dynamic>>(
        '/api/upload/files/$fileId',
        data: data,
      );

      if (response.data == null) {
        throw const LDKFileException('Invalid response from server');
      }

      return StrapiFile.fromJson(response.data!);
    } catch (e) {
      if (e is LDKException) rethrow;
      throw LDKFileException('Failed to update file info: ${e.toString()}',
          originalError: e);
    }
  }

  /// Validates a file before upload.
  bool validateFile(
    File file, {
    int? maxSizeBytes,
    List<String>? allowedMimeTypes,
    List<String>? allowedExtensions,
  }) {
    try {
      // Check if file exists
      if (!file.existsSync()) {
        return false;
      }

      // Check file size
      if (maxSizeBytes != null) {
        final fileSize = file.lengthSync();
        if (fileSize > maxSizeBytes) {
          return false;
        }
      }

      // Check MIME type
      if (allowedMimeTypes != null) {
        final mimeType = lookupMimeType(file.path);
        if (mimeType == null || !allowedMimeTypes.contains(mimeType)) {
          return false;
        }
      }

      // Check file extension
      if (allowedExtensions != null) {
        final extension = file.path.split('.').last.toLowerCase();
        if (!allowedExtensions.contains(extension)) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Gets the MIME type of a file.
  String? getMimeType(File file) {
    return lookupMimeType(file.path);
  }

  /// Gets the file extension.
  String getFileExtension(File file) {
    return file.path.split('.').last.toLowerCase();
  }

  /// Formats file size in human-readable format.
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
