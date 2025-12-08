import '../api/api_client.dart';
import '../models/playlist_config.dart';

/// Service for managing playlists via API
class PlaylistApiService {
  final ApiClient _api = ApiClient();

  /// Get all playlists for current user
  Future<List<PlaylistConfig>> getPlaylists() async {
    try {
      final response = await _api.get('/api/playlists');
      final data = response.data as Map<String, dynamic>;
      final playlistsData = data['playlists'] as List<dynamic>;

      return playlistsData.map((p) {
        final playlist = p as Map<String, dynamic>;
        return PlaylistConfig(
          id: playlist['id'] as String,
          name: playlist['name'] as String,
          dns: playlist['serverUrl'] as String? ?? playlist['dns'] as String,
          username: playlist['username'] as String,
          password: playlist['password'] as String,
          createdAt: DateTime.tryParse(playlist['createdAt'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      print('Error fetching playlists: $e');
      return [];
    }
  }

  /// Create a new playlist
  Future<PlaylistConfig?> createPlaylist({
    required String name,
    required String dns,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _api.post('/api/playlists', data: {
        'name': name,
        'serverUrl': dns,
        'username': username,
        'password': password,
        'dns': dns,
      },);

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        final playlist = data['playlist'] as Map<String, dynamic>;
        return PlaylistConfig(
          id: playlist['id'] as String,
          name: playlist['name'] as String,
          dns: playlist['serverUrl'] as String? ?? playlist['dns'] as String,
          username: playlist['username'] as String,
          password: playlist['password'] as String,
          createdAt: DateTime.tryParse(playlist['createdAt'] as String? ?? '') ?? DateTime.now(),
        );
      }
      return null;
    } catch (e) {
      print('Error creating playlist: $e');
      return null;
    }
  }

  /// Update a playlist
  Future<PlaylistConfig?> updatePlaylist({
    required String id,
    required String name,
    required String dns,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _api.put('/api/playlists/$id', data: {
        'name': name,
        'serverUrl': dns,
        'username': username,
        'password': password,
        'dns': dns,
      },);

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        final playlist = data['playlist'] as Map<String, dynamic>;
        return PlaylistConfig(
          id: playlist['id'] as String,
          name: playlist['name'] as String,
          dns: playlist['serverUrl'] as String? ?? playlist['dns'] as String,
          username: playlist['username'] as String,
          password: playlist['password'] as String,
          createdAt: DateTime.tryParse(playlist['createdAt'] as String? ?? '') ?? DateTime.now(),
        );
      }
      return null;
    } catch (e) {
      print('Error updating playlist: $e');
      return null;
    }
  }

  /// Delete a playlist
  Future<bool> deletePlaylist(String id) async {
    try {
      final response = await _api.delete('/api/playlists/$id');
      final data = response.data as Map<String, dynamic>;
      return data['success'] == true;
    } catch (e) {
      print('Error deleting playlist: $e');
      return false;
    }
  }
}
