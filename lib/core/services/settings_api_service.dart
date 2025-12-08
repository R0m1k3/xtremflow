import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:html' as html;
import '../models/app_user.dart';

class SettingsApiService {
  final String _baseUrl = html.window.location.origin;

  Future<Map<String, dynamic>?> getSettings() async {
    final token = html.window.localStorage['auth_token'];
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> saveSettings(Map<String, dynamic> settings) async {
    final token = html.window.localStorage['auth_token'];
    if (token == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(settings),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
