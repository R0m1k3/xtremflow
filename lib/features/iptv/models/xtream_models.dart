import 'dart:convert';

/// Xtream API Data Models (lightweight for memory optimization)

class LiveChannel {
  final String streamId;
  final String name;
  final String? streamIcon;
  final String? categoryId;
  final String streamType;
  final String? epgChannelId;

  const LiveChannel({
    required this.streamId,
    required this.name,
    this.streamIcon,
    this.categoryId,
    required this.streamType,
    this.epgChannelId,
  });

  factory LiveChannel.fromJson(Map<String, dynamic> json) {
    return LiveChannel(
      streamId: json['stream_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      streamIcon: json['stream_icon']?.toString(),
      categoryId: json['category_id']?.toString(),
      streamType: json['stream_type']?.toString() ?? 'live',
      epgChannelId: json['epg_channel_id']?.toString(),
    );
  }

  String getStreamUrl(String dns, String username, String password) {
    return '$dns/live/$username/$password/$streamId.m3u8';
  }
}

class Movie {
  final String streamId;
  final String name;
  final String? streamIcon;
  final String? categoryId;
  final String categoryName;
  final String? containerExtension;
  final String? rating;

  const Movie({
    required this.streamId,
    required this.name,
    this.streamIcon,
    this.categoryId,
    this.categoryName = '',
    this.containerExtension,
    this.rating,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    // Essayer plusieurs champs possibles pour l'image (différentes API Xtream utilisent différents noms)
    final imageUrl = json['stream_icon']?.toString() ?? 
                     json['cover']?.toString() ?? 
                     json['movie_image']?.toString() ??
                     json['cover_big']?.toString();
    
    return Movie(
      streamId: json['stream_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      streamIcon: imageUrl,
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name']?.toString() ?? '',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
      rating: json['rating']?.toString(),
    );
  }

  String getStreamUrl(String dns, String username, String password) {
    return '$dns/movie/$username/$password/$streamId.$containerExtension';
  }
}

class Series {
  final String seriesId;
  final String name;
  final String? cover;
  final String? categoryId;
  final String categoryName;
  final String? rating;

  const Series({
    required this.seriesId,
    required this.name,
    this.cover,
    this.categoryId,
    this.categoryName = '',
    this.rating,
  });

  factory Series.fromJson(Map<String, dynamic> json) {
    return Series(
      seriesId: json['series_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      cover: json['cover']?.toString(),
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name']?.toString() ?? '',
      rating: json['rating']?.toString(),
    );
  }
}

/// Season model for series
class Season {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? cover;

  const Season({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.cover,
  });

  factory Season.fromJson(Map<String, dynamic> json) {
    return Season(
      seasonNumber: int.tryParse(json['season_number']?.toString() ?? '1') ?? 1,
      name: json['name']?.toString() ?? 'Season ${json['season_number'] ?? 1}',
      episodeCount: int.tryParse(json['episode_count']?.toString() ?? '0') ?? 0,
      cover: json['cover']?.toString(),
    );
  }
}

/// Episode model for series
class Episode {
  final String id;
  final int episodeNum;
  final String title;
  final String? containerExtension;
  final String? info;
  final String? cover;
  final int? durationSecs;

  const Episode({
    required this.id,
    required this.episodeNum,
    required this.title,
    this.containerExtension,
    this.info,
    this.cover,
    this.durationSecs,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id']?.toString() ?? '',
      episodeNum: int.tryParse(json['episode_num']?.toString() ?? '1') ?? 1,
      title: json['title']?.toString() ?? 'Episode ${json['episode_num'] ?? 1}',
      containerExtension: json['container_extension']?.toString() ?? 'mkv',
      info: json['info']?.toString(),
      cover: json['custom_cover']?.toString() ?? json['cover']?.toString(),
      durationSecs: int.tryParse(json['duration_secs']?.toString() ?? '0'),
    );
  }

  String getStreamUrl(String dns, String username, String password) {
    return '$dns/series/$username/$password/$id.${containerExtension ?? 'mkv'}';
  }
}

/// Series info with seasons and episodes
class SeriesInfo {
  final String seriesId;
  final String name;
  final String? cover;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? rating;
  final List<Season> seasons;
  final Map<int, List<Episode>> episodes;

  const SeriesInfo({
    required this.seriesId,
    required this.name,
    this.cover,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
    required this.seasons,
    required this.episodes,
  });

  factory SeriesInfo.fromJson(Map<String, dynamic> json) {
    final seasonsData = json['seasons'] as List<dynamic>? ?? [];
    final seasons = seasonsData.map((s) => Season.fromJson(s as Map<String, dynamic>)).toList();

    final episodesData = json['episodes'] as Map<String, dynamic>? ?? {};
    final episodes = <int, List<Episode>>{};
    
    episodesData.forEach((seasonNum, episodesList) {
      final seasonInt = int.tryParse(seasonNum) ?? 1;
      final episodeList = (episodesList as List<dynamic>?)
          ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
          .toList() ?? [];
      episodes[seasonInt] = episodeList;
    });

    final info = json['info'] as Map<String, dynamic>? ?? {};

    return SeriesInfo(
      seriesId: json['series_id']?.toString() ?? info['series_id']?.toString() ?? '',
      name: info['name']?.toString() ?? json['name']?.toString() ?? 'Unknown',
      cover: info['cover']?.toString() ?? json['cover']?.toString(),
      plot: info['plot']?.toString(),
      cast: info['cast']?.toString(),
      director: info['director']?.toString(),
      genre: info['genre']?.toString(),
      releaseDate: info['releaseDate']?.toString(),
      rating: info['rating']?.toString(),
      seasons: seasons,
      episodes: episodes,
    );
  }
}

class Category {
  final String categoryId;
  final String categoryName;

  const Category({
    required this.categoryId,
    required this.categoryName,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? 'Unknown',
    );
  }
}

class ShortEPG {
  final String? nowPlaying;
  final String? nextPlaying;
  final double? progress; // 0.0 to 1.0

  const ShortEPG({
    this.nowPlaying,
    this.nextPlaying,
    this.progress,
  });

  factory ShortEPG.fromJson(Map<String, dynamic> json) {
    final epgListings = json['epg_listings'] as List?;
    
    if (epgListings == null || epgListings.isEmpty) {
      return const ShortEPG();
    }

    String? nowTitle;
    String? nextTitle;
    double? currentProgress;

    final now = DateTime.now();

    // Helper to decode Base64 encoded title with proper UTF-8 support
    String decodeTitle(String? encodedTitle) {
      if (encodedTitle == null || encodedTitle.isEmpty) return '';
      try {
        // Try Base64 decode with UTF-8 encoding
        final bytes = base64Decode(encodedTitle);
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        // Not Base64, return as-is
        return encodedTitle;
      }
    }

    // Helper to parse timestamp (Unix epoch or ISO format)
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      
      final strValue = value.toString();
      
      // Try parsing as Unix timestamp (seconds)
      final intValue = int.tryParse(strValue);
      if (intValue != null) {
        return DateTime.fromMillisecondsSinceEpoch(intValue * 1000);
      }
      
      // Try parsing as ISO date string
      return DateTime.tryParse(strValue);
    }

    for (var i = 0; i < epgListings.length; i++) {
      final listing = epgListings[i] as Map<String, dynamic>;
      
      // Parse start/stop timestamps (can be 'start', 'start_timestamp', or Unix epoch)
      final start = parseTimestamp(listing['start']) ?? 
                    parseTimestamp(listing['start_timestamp']);
      final stop = parseTimestamp(listing['stop']) ?? 
                   parseTimestamp(listing['end']) ??
                   parseTimestamp(listing['stop_timestamp']);

      if (start != null && stop != null) {
        if (now.isAfter(start) && now.isBefore(stop)) {
          // Decode title (may be Base64 encoded)
          nowTitle = decodeTitle(listing['title']?.toString());
          
          final duration = stop.difference(start).inSeconds;
          final elapsed = now.difference(start).inSeconds;
          if (duration > 0) {
            currentProgress = elapsed / duration;
          }

          // Get next item
          if (i + 1 < epgListings.length) {
            final nextListing = epgListings[i + 1] as Map<String, dynamic>;
            nextTitle = decodeTitle(nextListing['title']?.toString());
          }
          break;
        }
      }
    }

    return ShortEPG(
      nowPlaying: nowTitle,
      nextPlaying: nextTitle,
      progress: currentProgress,
    );
  }
}
