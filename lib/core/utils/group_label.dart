/// A provider group name split into its country prefix and its own name:
/// `FR | Sport` → country `France`, name `Sport`. The prefix is written out
/// once, quietly, under the name instead of repeated as a code on every card.
class GroupLabel {
  const GroupLabel({required this.name, this.country});

  final String name;

  /// Country (or language) in plain words, `null` when the group has none.
  final String? country;

  static const Map<String, String> _countries = {
    'FR': 'France',
    'BE': 'Belgique',
    'CH': 'Suisse',
    'LU': 'Luxembourg',
    'CA': 'Canada',
    'QC': 'Québec',
    'UK': 'Royaume-Uni',
    'GB': 'Royaume-Uni',
    'US': 'États-Unis',
    'USA': 'États-Unis',
    'EN': 'Anglais',
    'ES': 'Espagne',
    'DE': 'Allemagne',
    'IT': 'Italie',
    'PT': 'Portugal',
    'NL': 'Pays-Bas',
    'PL': 'Pologne',
    'RO': 'Roumanie',
    'TR': 'Turquie',
    'MA': 'Maroc',
    'DZ': 'Algérie',
    'TN': 'Tunisie',
    'AR': 'Arabe',
    'AF': 'Afrique',
    'AFR': 'Afrique',
    'BR': 'Brésil',
    'IN': 'Inde',
    'AL': 'Albanie',
    'GR': 'Grèce',
    'SE': 'Suède',
    'NO': 'Norvège',
    'DK': 'Danemark',
    'FI': 'Finlande',
    'RU': 'Russie',
    'UA': 'Ukraine',
    'MX': 'Mexique',
    'LAT': 'Amérique latine',
    'EXYU': 'Ex-Yougoslavie',
    'INT': 'International',
  };

  // `FR | Sport`, `FR| SPORT`, `|FR| Sport`, `FR - Sport`, `FR: Sport`,
  // `[FR] Sport`, `(FR) Sport`.
  static final RegExp _prefix = RegExp(
    r'^\s*(?:\|\s*([A-Za-z]{2,4})\s*\||\[\s*([A-Za-z]{2,4})\s*\]|\(\s*([A-Za-z]{2,4})\s*\)|([A-Za-z]{2,4})\s*(?:\||:|-|–|»))\s*(.+)$',
  );

  factory GroupLabel.parse(String raw) {
    final match = _prefix.firstMatch(raw);
    if (match != null) {
      final code = (match[1] ?? match[2] ?? match[3] ?? match[4] ?? '')
          .toUpperCase();
      final rest = match[5]!.trim();
      // Only a real code counts: `Sport - Live` must not become `Sport`.
      final isCode =
          _countries.containsKey(code) ||
          (match[4] == null && code.isNotEmpty) ||
          (match[4] != null && match[4] == match[4]!.toUpperCase());
      if (isCode && rest.isNotEmpty) {
        return GroupLabel(name: rest, country: _countries[code] ?? code);
      }
    }
    return GroupLabel(name: raw.trim());
  }

  /// `France · 48 chaînes`, `France`, `48 chaînes` or empty.
  String meta({int? channelCount}) {
    final parts = [
      if (country != null) country!,
      if (channelCount != null)
        channelCount == 1 ? '1 chaîne' : '$channelCount chaînes',
    ];
    return parts.join(' · ');
  }
}
