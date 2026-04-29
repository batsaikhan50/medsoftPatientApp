import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../constants.dart';

const Duration _kRequestTimeout = Duration(seconds: 30);

// Enhanced error handling with retry logic
class NetworkError extends Error {
  final String message;
  final int? statusCode;
  final String? endpoint;

  NetworkError(this.message, {this.statusCode, this.endpoint});

  @override
  String toString() => 'NetworkError: $message (Status: $statusCode, Endpoint: $endpoint)';
}

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

String statusMessage(int? statusCode) {
  switch (statusCode) {
    case 400:
      return 'Илгээсэн хүсэлт буруу байна.';
    case 401:
      return 'Баталгаажуулалт амжилтгүй боллоо. Дахин нэвтэрнэ үү.';
    case 403:
      return 'Та энэ үйлдлийг хийх эрхгүй байна.';
    case 404:
      return 'Хүссэн мэдээлэл олдсонгүй.';
    case 409:
      return 'Хүсэлтийг гүйцэтгэх боломжгүй байна.';
    case 422:
      return 'Оруулсан мэдээллээ шалгаад дахин оролдоно уу.';
    case 429:
      return 'Хэт олон оролдлого хийсэн байна. Дараа дахин оролдоно уу.';
    case 500:
      return 'Системийн алдаа гарлаа.';
    case 503:
      return 'Үйлчилгээ түр хугацаанд боломжгүй байна.';
    default:
      return 'Алдаа гарлаа. Дахин оролдоно уу.';
  }
}

abstract class BaseDAO {
  static void Function()? _onUnauthorized;
  static bool _handlingUnauthorized = false;

  static void setOnUnauthorized(void Function() handler) {
    _onUnauthorized = handler;
    _handlingUnauthorized = false;
  }

  Future<ApiResponse<T>> post<T>(
    String url, {
    Map<String, dynamic>? body,
    RequestConfig config = const RequestConfig(),
    T Function(dynamic)? parse,
    int maxRetries = 2,
    Duration? retryDelay,
  }) async {
    retryDelay ??= const Duration(milliseconds: 500);

    ApiResponse<T>? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final headers = await _buildHeaders(config);
        final response = await http
            .post(Uri.parse(url), headers: headers, body: body != null ? jsonEncode(body) : null)
            .timeout(_kRequestTimeout);
        final result = _handleResponse<T>(response, parse: parse);

        if (result.success || attempt == maxRetries) {
          return result;
        }

        lastError = result;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } on SocketException {
        final error = ApiResponse<T>(
          success: false,
          message: 'Интернэт холболтоо шалгана уу. Сүлжээний алдаа.',
        );
        if (attempt == maxRetries) return error;
        lastError = error;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } on TimeoutException {
        final error = ApiResponse<T>(
          success: false,
          message: 'Серверт холбогдоход хугацаа дууслаа. Дахин оролдоно уу.',
        );
        if (attempt == maxRetries) return error;
        lastError = error;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } catch (e) {
        final error = ApiResponse<T>(
          success: false,
          message: 'Системийн алдаа гарлаа: ${e.toString()}',
        );
        if (attempt == maxRetries) return error;
        lastError = error;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }

    return lastError ?? ApiResponse<T>(success: false, message: 'Хүсэлт амжилтгүй боллоо.');
  }

  Future<ApiResponse<T>> get<T>(
    String url, {
    RequestConfig config = const RequestConfig(),
    T Function(dynamic)? parse,
    int maxRetries = 2,
    Duration? retryDelay,
  }) async {
    retryDelay ??= const Duration(milliseconds: 500);

    ApiResponse<T>? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final headers = await _buildHeaders(config);
        final response = await http.get(Uri.parse(url), headers: headers).timeout(_kRequestTimeout);
        final result = _handleResponse<T>(response, parse: parse);

        if (result.success || attempt == maxRetries) {
          return result;
        }

        lastError = result;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } on SocketException {
        final error = ApiResponse<T>(
          success: false,
          message: 'Интернэт холболтоо шалгана уу. Сүлжээний алдаа.',
        );
        if (attempt == maxRetries) return error;
        lastError = error;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } on TimeoutException {
        final error = ApiResponse<T>(
          success: false,
          message: 'Серверт холбогдоход хугацаа дууслаа. Дахин оролдоно уу.',
        );
        if (attempt == maxRetries) return error;
        lastError = error;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } catch (e) {
        final error = ApiResponse<T>(
          success: false,
          message: 'Системийн алдаа гарлаа: ${e.toString()}',
        );
        if (attempt == maxRetries) return error;
        lastError = error;
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }

    return lastError ?? ApiResponse<T>(success: false, message: 'Хүсэлт амжилтгүй боллоо.');
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
          headers['X-Tenant'] = savedTenant;
        }
        break;
      case HeaderType.custom:
        break;
    }

    if (config.customHeaders != null) {
      headers.addAll(config.customHeaders!);
    }

    return headers;
  }

  ApiResponse<T> _handleResponse<T>(http.Response response, {T Function(dynamic)? parse}) {
    if (response.statusCode >= 400) {
      if ((response.statusCode == 401 || response.statusCode == 403) && !_handlingUnauthorized) {
        _handlingUnauthorized = true;
        Future.microtask(() => _onUnauthorized?.call());
      }
      return ApiResponse<T>(
        success: false,
        message: statusMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    }

    try {
      final jsonBody = jsonDecode(response.body);
      return ApiResponse.fromJson(jsonBody, parse: parse, statusCode: response.statusCode);
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        message: 'Системийн алдаа гарлаа. Мэдээллийн ажилтанд хандаж алдааг шалгуулна уу.',
        statusCode: response.statusCode,
      );
    }
  }

  Uint8List _handleRawResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    } else {
      try {
        final jsonBody = jsonDecode(response.body);
        throw Exception(
          jsonBody['message'] ?? 'Серверээс алдаатай хариу ирлээ. (Status: ${response.statusCode})',
        );
      } catch (e) {
        throw Exception('Хүсэлт амжилтгүй боллоо. (Status: ${response.statusCode})');
      }
    }
  }

  Future<Uint8List> getRaw(String url, {RequestConfig config = const RequestConfig()}) async {
    try {
      final headers = await _buildHeaders(config);
      final response = await http.get(Uri.parse(url), headers: headers).timeout(_kRequestTimeout);
      return _handleRawResponse(response);
    } on SocketException {
      throw NetworkError('Интернэт холболтоо шалгана уу. Сүлжээний алдаа.', endpoint: url);
    } on TimeoutException {
      throw NetworkError('Серверт холбогдоход хугацаа дууслаа. Дахин оролдоно уу.', endpoint: url);
    } catch (e) {
      throw NetworkError('Файл татахад алдаа гарлаа: ${e.toString()}', endpoint: url);
    }
  }
}
