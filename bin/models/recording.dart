import 'dart:convert';

class Recording {
  final String id;
  final String userId;
  final String channelId;
  final String streamUrl;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String status; // 'scheduled', 'recording', 'completed', 'failed', 'cancelled'
  final String? filePath;
  final String? errorReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  Recording({
    required this.id,
    required this.userId,
    required this.channelId,
    required this.streamUrl,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.filePath,
    this.errorReason,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'channel_id': channelId,
      'stream_url': streamUrl,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'status': status,
      'file_path': filePath,
      'error_reason': errorReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      channelId: map['channel_id'] ?? '',
      streamUrl: map['stream_url'] ?? '',
      title: map['title'] ?? '',
      startTime: DateTime.parse(map['start_time']),
      endTime: DateTime.parse(map['end_time']),
      status: map['status'] ?? 'scheduled',
      filePath: map['file_path'],
      errorReason: map['error_reason'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory Recording.fromJson(String source) =>
      Recording.fromMap(json.decode(source));

  Recording copyWith({
    String? id,
    String? userId,
    String? channelId,
    String? streamUrl,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? status,
    String? filePath,
    String? errorReason,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Recording(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      channelId: channelId ?? this.channelId,
      streamUrl: streamUrl ?? this.streamUrl,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      errorReason: errorReason ?? this.errorReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
