import 'package:http/http.dart' as http;

/// Subtitle track information
class SubtitleTrack {
  final String id;
  final String name;
  final String language;
  final String url;
  final bool isEnabled;

  SubtitleTrack({
    required this.id,
    required this.name,
    required this.language,
    required this.url,
    this.isEnabled = false,
  });

  SubtitleTrack copyWith({bool? isEnabled}) => SubtitleTrack(
    id: id,
    name: name,
    language: language,
    url: url,
    isEnabled: isEnabled ?? this.isEnabled,
  );
}

/// Subtitle content with timing
class SubtitleEntry {
  final int index;
  final Duration startTime;
  final Duration endTime;
  final String text;

  SubtitleEntry({
    required this.index,
    required this.startTime,
    required this.endTime,
    required this.text,
  });
}

/// Service for handling subtitles
class SubtitleService {
  static const _srtPattern = r'(\d+)\n(\d{2}):(\d{2}):(\d{2}),(\d{3}) --> (\d{2}):(\d{2}):(\d{2}),(\d{3})\n([\s\S]*?)(?=\n\n|\Z)';

  /// Parse SRT subtitle content
  static List<SubtitleEntry> parseSrt(String content) {
    final entries = <SubtitleEntry>[];
    final blocks = content.split('\n\n');
    
    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;

      try {
        final index = int.parse(lines[0]);
        final timeLine = lines[1];
        final text = lines.sublist(2).join('\n').trim();

        // Parse timing: 00:00:01,000 --> 00:00:05,000
        final times = timeLine.split('-->');
        if (times.length != 2) continue;

        final startTime = _parseTime(times[0].trim());
        final endTime = _parseTime(times[1].trim());

        entries.add(SubtitleEntry(
          index: index,
          startTime: startTime,
          endTime: endTime,
          text: text,
        ));
      } catch (e) {
        continue;
      }
    }

    return entries;
  }

  /// Parse WebVTT subtitle content
  static List<SubtitleEntry> parseWebVtt(String content) {
    final entries = <SubtitleEntry>[];
    final blocks = content.split('\n\n');
    
    for (final block in blocks) {
      if (block.trim().isEmpty || block.startsWith('WEBVTT')) continue;
      
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      try {
        final timeLine = lines[0];
        final text = lines.sublist(1).join('\n').trim();

        // Parse timing: 00:00:01.000 --> 00:00:05.000
        final times = timeLine.split('-->');
        if (times.length != 2) continue;

        final startTime = _parseWebVttTime(times[0].trim());
        final endTime = _parseWebVttTime(times[1].trim());

        entries.add(SubtitleEntry(
          index: entries.length,
          startTime: startTime,
          endTime: endTime,
          text: text,
        ));
      } catch (e) {
        continue;
      }
    }

    return entries;
  }

  /// Get subtitle at specific time
  static String? getSubtitleAtTime(List<SubtitleEntry> entries, Duration time) {
    for (final entry in entries) {
      if (time.compareTo(entry.startTime) >= 0 && time.compareTo(entry.endTime) <= 0) {
        return entry.text;
      }
    }
    return null;
  }

  /// Download subtitle from URL
  static Future<String> downloadSubtitle(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.body;
      }
      throw Exception('Failed to download subtitle: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error downloading subtitle: $e');
    }
  }

  /// Parse time format HH:MM:SS,mmm (SRT)
  static Duration _parseTime(String time) {
    final parts = time.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final secondsParts = parts[2].split(',');
    final seconds = int.parse(secondsParts[0]);
    final milliseconds = int.parse(secondsParts[1]);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Parse time format HH:MM:SS.mmm (WebVTT)
  static Duration _parseWebVttTime(String time) {
    final parts = time.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final secondsParts = parts[2].split('.');
    final seconds = int.parse(secondsParts[0]);
    final milliseconds = int.parse(secondsParts[1].padEnd(3, '0'));

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }
}
