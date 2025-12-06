/// Channel model for Live TV
class Channel {
  final String streamId;
  final String num;
  final String name;
  final String streamType;
  final String streamIcon;
  final String epgChannelId;
  final String categoryId;
  final String categoryName;

  const Channel({
    required this.streamId,
    required this.num,
    required this.name,
    required this.streamType,
    this.streamIcon = '',
    this.epgChannelId = '',
    required this.categoryId,
    required this.categoryName,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      streamId: json['stream_id']?.toString() ?? '',
      num: json['num']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      streamType: json['stream_type']?.toString() ?? '',
      streamIcon: json['stream_icon']?.toString() ?? '',
      epgChannelId: json['epg_channel_id']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'num': num,
      'name': name,
      'stream_type': streamType,
      'stream_icon': streamIcon,
      'epg_channel_id': epgChannelId,
      'category_id': categoryId,
      'category_name': categoryName,
    };
  }
}

/// VOD (Video on Demand) model for Movies
class VodItem {
  final String streamId;
  final String name;
  final String streamIcon;
  final String rating;
  final String categoryId;
  final String categoryName;
  final String containerExtension;

  const VodItem({
    required this.streamId,
    required this.name,
    this.streamIcon = '',
    this.rating = '',
    required this.categoryId,
    required this.categoryName,
    this.containerExtension = 'mp4',
  });

  factory VodItem.fromJson(Map<String, dynamic> json) {
    return VodItem(
      streamId: json['stream_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      streamIcon: json['stream_icon']?.toString() ?? '',
      rating: json['rating']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'name': name,
      'stream_icon': streamIcon,
      'rating': rating,
      'category_id': categoryId,
      'category_name': categoryName,
      'container_extension': containerExtension,
    };
  }
}

/// Series model
class Series {
  final String seriesId;
  final String name;
  final String cover;
  final String plot;
  final String categoryId;
  final String categoryName;

  const Series({
    required this.seriesId,
    required this.name,
    this.cover = '',
    this.plot = '',
    required this.categoryId,
    required this.categoryName,
  });

  factory Series.fromJson(Map<String, dynamic> json) {
    return Series(
      seriesId: json['series_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      plot: json['plot']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'series_id': seriesId,
      'name': name,
      'cover': cover,
      'plot': plot,
      'category_id': categoryId,
      'category_name': categoryName,
    };
  }
}

/// EPG (Electronic Program Guide) entry
class EpgEntry {
  final String id;
  final String epgId;
  final String title;
  final String lang;
  final String start;
  final String end;
  final String description;
  final String channelId;

  const EpgEntry({
    required this.id,
    required this.epgId,
    required this.title,
    this.lang = '',
    required this.start,
    required this.end,
    this.description = '',
    required this.channelId,
  });

  factory EpgEntry.fromJson(Map<String, dynamic> json) {
    return EpgEntry(
      id: json['id']?.toString() ?? '',
      epgId: json['epg_id']?.toString() ?? '',
      title: _decodeBase64(json['title']?.toString()),
      lang: json['lang']?.toString() ?? '',
      start: json['start']?.toString() ?? '',
      end: json['end']?.toString() ?? '',
      description: _decodeBase64(json['description']?.toString()),
      channelId: json['channel_id']?.toString() ?? '',
    );
  }

  static String _decodeBase64(String? text) {
    if (text == null || text.isEmpty) return '';
    try {
      final bytes = base64Decode(text);
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return text;
    }
  }

  /// Calculate progress percentage for current program
  double getProgress() {
    try {
      final startTime = DateTime.parse(start);
      final endTime = DateTime.parse(end);
      final now = DateTime.now();

      if (now.isBefore(startTime)) return 0.0;
      if (now.isAfter(endTime)) return 1.0;

      final totalDuration = endTime.difference(startTime).inSeconds;
      final elapsed = now.difference(startTime).inSeconds;

      return elapsed / totalDuration;
    } catch (e) {
      return 0.0;
    }
  }
}
