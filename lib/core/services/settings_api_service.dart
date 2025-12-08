import '../api/api_client.dart';

/// Service for user settings API
class SettingsApiService {
  final ApiClient _api = ApiClient();

  /// Get settings from API
  Future<Map<String, dynamic>?> getSettings() async {
    // Restore token from localStorage before making the request
    _api.restoreToken();
    
    if (_api.getStoredToken() == null) {
      print('[SettingsAPI] getSettings: No auth token found');
      return null;
    }

    try {
      print('[SettingsAPI] getSettings: Fetching settings...');
      final response = await _api.get('/api/settings');
      
      print('[SettingsAPI] getSettings: Response status ${response.statusCode}');
      if (response.statusCode == 200) {
        if (response.data == null) return {};
        final decoded = response.data as Map<String, dynamic>;
        print('[SettingsAPI] getSettings: Loaded ${decoded.length} settings');
        return decoded;
      }
      print('[SettingsAPI] getSettings: Failed with data: ${response.data}');
      return null;
    } catch (e) {
      print('[SettingsAPI] getSettings: Exception: $e');
      return null;
    }
  }

  /// Save settings to API
  Future<bool> saveSettings(Map<String, dynamic> settings) async {
    // Restore token from localStorage before making the request
    _api.restoreToken();
    
    if (_api.getStoredToken() == null) {
      print('[SettingsAPI] saveSettings: No auth token found');
      return false;
    }

    try {
      print('[SettingsAPI] saveSettings: Saving ${settings.length} settings...');
      final response = await _api.post('/api/settings', data: settings);
      
      print('[SettingsAPI] saveSettings: Response status ${response.statusCode}');
      if (response.statusCode != 200) {
        print('[SettingsAPI] saveSettings: Failed with data: ${response.data}');
      }
      return response.statusCode == 200;
    } catch (e) {
      print('[SettingsAPI] saveSettings: Exception: $e');
      return false;
    }
  }
}
