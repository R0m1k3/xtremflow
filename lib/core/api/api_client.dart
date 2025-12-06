import 'package:dio/dio.dart';
import 'dart:html' as html;

/// API Client for communicating with the backend
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  
  late final Dio _dio;
  String? _token;

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _getBaseUrl(),
      headers: {'Content-Type': 'application/json'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    
    // Add interceptor for logging
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ));
  }

  /// Get base URL (same origin for production)
  String _getBaseUrl() {
    // Use current origin for API calls
    return '';
  }

  /// Set authentication token
  void setToken(String? token) {
    _token = token;
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
      // Store in localStorage for persistence
      html.window.localStorage['auth_token'] = token;
    } else {
      _dio.options.headers.remove('Authorization');
      html.window.localStorage.remove('auth_token');
    }
  }

  /// Get stored token from localStorage
  String? getStoredToken() {
    return html.window.localStorage['auth_token'];
  }

  /// Restore token from localStorage
  void restoreToken() {
    final storedToken = getStoredToken();
    if (storedToken != null) {
      setToken(storedToken);
    }
  }

  /// Clear token
  void clearToken() {
    setToken(null);
  }

  /// GET request
  Future<Response> get(String path) async {
    return _dio.get(path);
  }

  /// POST request
  Future<Response> post(String path, {dynamic data}) async {
    return _dio.post(path, data: data);
  }

  /// PUT request
  Future<Response> put(String path, {dynamic data}) async {
    return _dio.put(path, data: data);
  }

  /// DELETE request
  Future<Response> delete(String path) async {
    return _dio.delete(path);
  }
}
