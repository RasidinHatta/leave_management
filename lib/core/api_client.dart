import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'constants.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  final http.Client _httpClient;

  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? kBaseUrl,
        _httpClient = http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Uri _buildUri(String path, [Map<String, String?>? queryParams]) {
    final filtered = queryParams?.entries
        .where((e) => e.value != null && e.value!.isNotEmpty)
        .map((e) => MapEntry(e.key, e.value!))
        .toList();
    return Uri.parse('$baseUrl$path').replace(
      queryParameters:
          (filtered != null && filtered.isNotEmpty) ? Map.fromEntries(filtered) : null,
    );
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message;
      try {
        final body = jsonDecode(response.body);
        final msg = body['message'];
        if (msg is List) {
          message = msg.join(', ');
        } else {
          message = msg?.toString() ?? 'Request failed';
        }
      } catch (_) {
        message = 'Request failed with status ${response.statusCode}';
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
  }

  Future<dynamic> _get(String path, {Map<String, String?>? queryParams}) async {
    try {
      final response = await _httpClient
          .get(_buildUri(path, queryParams), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
          'Request timed out. Is the API running at $baseUrl?');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Connection failed: ${e.toString()}');
    }
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    try {
      final response = await _httpClient
          .post(_buildUri(path), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException('Request timed out.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Connection failed: ${e.toString()}');
    }
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    try {
      final response = await _httpClient
          .patch(_buildUri(path), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException('Request timed out.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Connection failed: ${e.toString()}');
    }
  }

  Future<dynamic> _delete(String path) async {
    try {
      final response = await _httpClient
          .delete(_buildUri(path), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException('Request timed out.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Connection failed: ${e.toString()}');
    }
  }

  // =================== API Methods ===================

  /// GET /leave/config/daily-report
  Future<List<Map<String, dynamic>>> getDailyReport({
    required String date,
    String? office,
    String? department,
    String? database,
  }) async {
    final result = await _get('/leave/config/daily-report', queryParams: {
      'date': date,
      'office': office,
      'department': department,
      'database': database,
    });
    return (result as List).cast<Map<String, dynamic>>();
  }

  /// GET /leave/config/targets
  Future<List<Map<String, dynamic>>> getTargets() async {
    final result = await _get('/leave/config/targets');
    return (result as List).cast<Map<String, dynamic>>();
  }

  /// GET /leave/config/targets/:databaseName
  Future<Map<String, dynamic>> getTargetByDb(String databaseName) async {
    final result = await _get('/leave/config/targets/$databaseName');
    return result as Map<String, dynamic>;
  }

  /// POST /leave/config/targets
  Future<Map<String, dynamic>> addTarget(Map<String, dynamic> data) async {
    final result = await _post('/leave/config/targets', data);
    return result as Map<String, dynamic>;
  }

  /// PATCH /leave/config/targets/:databaseName
  Future<Map<String, dynamic>> editTarget(
      String databaseName, Map<String, dynamic> data) async {
    final result = await _patch('/leave/config/targets/$databaseName', data);
    return result as Map<String, dynamic>;
  }

  /// DELETE /leave/config/targets/:databaseName
  Future<void> deleteTarget(String databaseName) async {
    await _delete('/leave/config/targets/$databaseName');
  }

  /// POST /leave/BF
  Future<Map<String, dynamic>> addBringForwardLeave({
    String? database,
    required int year,
    required int month,
    required List<Map<String, dynamic>> list,
  }) async {
    final body = <String, dynamic>{
      'year': year,
      'month': month,
      'list': list,
    };
    if (database != null && database.isNotEmpty) {
      body['database'] = database;
    }
    final result = await _post('/leave/BF', body);
    return result as Map<String, dynamic>;
  }

  /// POST /leave/taken
  Future<Map<String, dynamic>> addLeaveTaken({
    String? database,
    required List<Map<String, dynamic>> list,
  }) async {
    final body = <String, dynamic>{
      'list': list,
    };
    if (database != null && database.isNotEmpty) {
      body['database'] = database;
    }
    final result = await _post('/leave/taken', body);
    return result as Map<String, dynamic>;
  }
}
