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
    return Movie(
      streamId: json['stream_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      streamIcon: json['stream_icon']?.toString(),
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

    for (var i = 0; i < epgListings.length; i++) {
      final listing = epgListings[i];
      final start = DateTime.tryParse(listing['start']?.toString() ?? '');
      final stop = DateTime.tryParse(listing['stop']?.toString() ?? '');

      if (start != null && stop != null) {
        if (now.isAfter(start) && now.isBefore(stop)) {
          nowTitle = listing['title']?.toString();
          final duration = stop.difference(start).inSeconds;
          final elapsed = now.difference(start).inSeconds;
          currentProgress = elapsed / duration;

          // Get next item
          if (i + 1 < epgListings.length) {
            nextTitle = epgListings[i + 1]['title']?.toString();
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
