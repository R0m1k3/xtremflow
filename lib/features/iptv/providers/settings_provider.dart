import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings state for IPTV preferences
class IptvSettings {
  /// Category filter keywords (comma-separated)
  /// Example: "FR,FRANCE,HD" will show only categories containing one of these words
  final String categoryFilter;

  const IptvSettings({
    this.categoryFilter = '',
  });

  IptvSettings copyWith({
    String? categoryFilter,
  }) {
    return IptvSettings(
      categoryFilter: categoryFilter ?? this.categoryFilter,
    );
  }

  /// Get list of filter keywords (trimmed and non-empty)
  List<String> get filterKeywords {
    if (categoryFilter.isEmpty) return [];
    return categoryFilter
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Check if a category name matches the filter
  /// Returns true if no filter is set or if the category contains any keyword
  bool matchesFilter(String categoryName) {
    final keywords = filterKeywords;
    if (keywords.isEmpty) return true;
    
    final upperName = categoryName.toUpperCase();
    return keywords.any((keyword) => upperName.contains(keyword));
  }
}

/// IPTV Settings notifier for managing user preferences
class IptvSettingsNotifier extends StateNotifier<IptvSettings> {
  IptvSettingsNotifier() : super(const IptvSettings());

  void setCategoryFilter(String filter) {
    state = state.copyWith(categoryFilter: filter);
  }

  void clearCategoryFilter() {
    state = state.copyWith(categoryFilter: '');
  }
}

/// Provider for IPTV settings
final iptvSettingsProvider =
    StateNotifierProvider<IptvSettingsNotifier, IptvSettings>((ref) {
  return IptvSettingsNotifier();
});
