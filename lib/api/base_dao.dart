import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

// API хандалтын үндсэн DAO
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;

  ApiResponse({required this.success, this.data, this.message, this.statusCode});

  factory ApiResponse.fromJson(
    Map<String, dynamic> json, {
    T Function(dynamic)? parse,
    int? statusCode,
  }) {
    return ApiResponse<T>(
      success: json['success'] == true,
      data: parse != null ? parse(json['data']) : json['data'],
      message: json['message']?.toString(),
      statusCode: statusCode,
    );
  }
}

enum HeaderType {
  jsonOnly, // Content-Type: application/json
  bearerToken, // Authorization: Bearer <token>
  xToken, // X-Token: Constants.xToken
  bearerAndJson, // Bearer + JSON
  bearerAndJsonAndXtokenAndTenant, // Bearer + JSON + X-Token + X-Tenant
  custom, // For custom headers
}

class RequestConfig {
  final HeaderType headerType;
  final Map<String, String>? customHeaders;
  final bool excludeToken;

  const RequestConfig({
    this.headerType = HeaderType.jsonOnly,
    this.customHeaders,
    this.excludeToken = false,
  });
}

abstract class BaseDAO {
  Future<ApiResponse<T>> post<T>(
    String url, {
    Map<String, dynamic>? body,
    RequestConfig config = const RequestConfig(),
    T Function(dynamic)? parse,
  }) async {
    try {
      final headers = await _buildHeaders(config);
      debugPrint('POST $url');
      debugPrint('Headers: $headers');
      debugPrint('Body: ${jsonEncode(body)}');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return _handleResponse<T>(response, parse: parse);
    } catch (e) {
      debugPrint('POST error: $e');
      return ApiResponse<T>(success: false, message: e.toString());
    }
  }

  Future<ApiResponse<T>> get<T>(
    String url, {
    RequestConfig config = const RequestConfig(),
    T Function(dynamic)? parse,
    // T Function(dynamic json)? transform,
  }) async {
    try {
      final headers = await _buildHeaders(config);
      debugPrint('GET $url');
      debugPrint('Headers: $headers');

      final response = await http.get(Uri.parse(url), headers: headers);
      final result = _handleResponse<T>(response, parse: parse);

      // if (result.success && transform != null && result.data != null) {
      //   return ApiResponse<T>(success: true, data: transform(result.data), message: result.message);
      // }

      // *** FIX 2: Return result directly (now that its type is ApiResponse<T>) ***
      return result;
      // return ApiResponse<T>(
      //   success: result.success,
      //   data: result.data as T?,
      //   message: result.message,
      // );
    } catch (e) {
      debugPrint('GET error: $e');
      return ApiResponse<T>(success: false, message: e.toString());
    }
  }

  Future<Map<String, String>> _buildHeaders(RequestConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('X-Medsoft-Token') ?? '';
    final savedTenant = prefs.getString('X-Tenant') ?? '';

    Map<String, String> headers = {};

    switch (config.headerType) {
      case HeaderType.jsonOnly:
        headers['Content-Type'] = 'application/json';
        break;
      case HeaderType.bearerToken:
        if (!config.excludeToken && savedToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $savedToken';
        }
        break;
      case HeaderType.xToken:
        headers['X-Token'] = Constants.xToken;
        break;
      case HeaderType.bearerAndJson:
        headers['Content-Type'] = 'application/json';
        if (!config.excludeToken && savedToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $savedToken';
        }
        break;
      case HeaderType.bearerAndJsonAndXtokenAndTenant:
        headers['Content-Type'] = 'application/json';
        if (!config.excludeToken && savedToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $savedToken';
        }
        headers['X-Token'] = Constants.xToken;
        if (!config.excludeToken && savedTenant.isNotEmpty) {
          headers['X-Tenant'] = savedToken;
        }
        break;
      case HeaderType.custom:
        // do nothing — will merge below
        break;
    }

    if (config.customHeaders != null) {
      headers.addAll(config.customHeaders!);
    }

    return headers;
  }

  ApiResponse<T> _handleResponse<T>(http.Response response, {T Function(dynamic)? parse}) {
    debugPrint('Response [${response.statusCode}]: ${response.body}');

    try {
      final jsonBody = jsonDecode(response.body);
      return ApiResponse.fromJson(jsonBody, parse: parse, statusCode: response.statusCode);
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        message: 'Invalid response format: $e',
        statusCode: response.statusCode,
      );
    }
  }

  Uint8List _handleRawResponse(http.Response response) {
    debugPrint('Response [${response.statusCode}]: ${response.body.length} bytes');

    // Check for success status code (200-299)
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Return the raw bytes directly
      return response.bodyBytes;
    } else {
      // Handle error status codes (4xx, 5xx)
      try {
        // Try to parse the error message if the server sent it as JSON
        final jsonBody = jsonDecode(response.body);
        throw Exception(
          jsonBody['message'] ?? 'Серверээс алдаатай хариу ирлээ. (Status: ${response.statusCode})',
        );
      } catch (e) {
        // If it's not JSON (e.g., raw HTML error page or empty body)
        throw Exception('Хүсэлт амжилтгүй боллоо. (Status: ${response.statusCode})');
      }
    }
  }

  Future<Uint8List> getRaw(String url, {RequestConfig config = const RequestConfig()}) async {
    try {
      final headers = await _buildHeaders(config);
      debugPrint('GET RAW $url');
      debugPrint('Headers: $headers');

      final response = await http.get(Uri.parse(url), headers: headers);
      return _handleRawResponse(response);
    } catch (e) {
      // Re-throw the error so it can be handled by the caller (_handlePrint)
      debugPrint('GET RAW error: $e');
      rethrow;
    }
  }
}
