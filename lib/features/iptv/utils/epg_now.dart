import '../../../core/models/iptv_models.dart';

/// What is on now and next on a channel, from its short EPG.
class EpgNow {
  const EpgNow({this.current, this.next, this.start, this.end, this.now});

  static const empty = EpgNow();

  final EpgEntry? current;
  final EpgEntry? next;

  /// Times of [current].
  final DateTime? start, end;

  /// The instant the values were computed for.
  final DateTime? now;

  /// Share of [current] already run, 0..1, or `null` without valid times.
  double? get progress {
    final s = start, e = end, n = now;
    if (s == null || e == null || n == null) return null;
    final total = e.difference(s).inSeconds;
    if (total <= 0) return null;
    return (n.difference(s).inSeconds / total).clamp(0.0, 1.0);
  }

  /// Time left of [current], or `null` when unknown or over.
  Duration? get remaining {
    final e = end, n = now;
    if (e == null || n == null) return null;
    final left = e.difference(n);
    return left.isNegative ? null : left;
  }

  /// `21:10 – 23:15`, or `null` without valid times.
  String? get timeRange {
    final s = start, e = end;
    if (s == null || e == null) return null;
    return '${formatHm(s)} – ${formatHm(e)}';
  }

  /// `encore 12 min`, or `null`.
  String? get remainingText {
    final r = remaining;
    return r == null ? null : formatRemaining(r);
  }

  /// Start of [next] as `HH:MM`, or `null`.
  String? get nextStart {
    final s = EpgEntry.parseDateTime(next?.start);
    return s == null ? null : formatHm(s);
  }
}

/// The programme on at [now] (the entry whose start ≤ now < end) and the one
/// after it. Entries need not be sorted.
EpgNow epgNow(List<EpgEntry> entries, DateTime now) {
  final timed = <(DateTime, DateTime, EpgEntry)>[];
  for (final e in entries) {
    final s = EpgEntry.parseDateTime(e.start);
    final f = EpgEntry.parseDateTime(e.end);
    if (s == null || f == null) continue;
    timed.add((s, f, e));
  }
  timed.sort((a, b) => a.$1.compareTo(b.$1));
  for (var i = 0; i < timed.length; i++) {
    final (s, f, e) = timed[i];
    if (!now.isBefore(s) && now.isBefore(f)) {
      return EpgNow(
        current: e,
        next: i + 1 < timed.length ? timed[i + 1].$3 : null,
        start: s,
        end: f,
        now: now,
      );
    }
  }
  // Nothing on right now: show what comes next, if anything.
  for (final (s, _, e) in timed) {
    if (s.isAfter(now)) return EpgNow(next: e, now: now);
  }
  return EpgNow(now: now);
}

/// « encore 12 min », « encore 1 h 03 ». Under a minute: « encore 1 min ».
String formatRemaining(Duration d) {
  final minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return 'encore $m min';
  return 'encore $h h ${m.toString().padLeft(2, '0')}';
}

/// `HH:MM`.
String formatHm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
