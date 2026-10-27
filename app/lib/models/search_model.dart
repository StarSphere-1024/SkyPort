import '../src/rust/api.dart' as rust;

class SearchConfiguration {
  final bool hex;
  final bool caseSensitive;
  final bool showSent;
  final bool stripAnsi;

  const SearchConfiguration({
    required this.hex,
    required this.caseSensitive,
    required this.showSent,
    required this.stripAnsi,
  });

  rust.SearchOptions toRust() => rust.SearchOptions(
    hex: hex,
    caseSensitive: caseSensitive,
    showSent: showSent,
    stripAnsi: stripAnsi,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchConfiguration &&
      hex == other.hex &&
      caseSensitive == other.caseSensitive &&
      showSent == other.showSent &&
      stripAnsi == other.stripAnsi;

  @override
  int get hashCode => Object.hash(hex, caseSensitive, showSent, stripAnsi);
}

class SearchState {
  final bool visible;
  final String draft;
  final bool caseSensitive;
  final String? activeQuery;
  final SearchConfiguration? options;
  final bool submitting;
  final bool complete;
  final bool invalidated;
  final int total;
  final int? selectedIndex;
  final rust.SearchHit? selectedHit;
  final rust.SearchRecordView? selectedView;
  final Object? error;
  final bool wrapped;
  final int generation;
  final int navigation;

  const SearchState({
    this.visible = false,
    this.draft = '',
    this.caseSensitive = true,
    this.activeQuery,
    this.options,
    this.submitting = false,
    this.complete = true,
    this.invalidated = false,
    this.total = 0,
    this.selectedIndex,
    this.selectedHit,
    this.selectedView,
    this.error,
    this.wrapped = false,
    this.generation = 0,
    this.navigation = 0,
  });

  bool get hasResults => activeQuery != null && !invalidated;
  bool dirty(SearchConfiguration current) =>
      activeQuery != null && (draft != activeQuery || options != current);

  SearchState copyWith({
    bool? visible,
    String? draft,
    bool? caseSensitive,
    String? activeQuery,
    SearchConfiguration? options,
    bool? submitting,
    bool? complete,
    bool? invalidated,
    int? total,
    int? selectedIndex,
    rust.SearchHit? selectedHit,
    rust.SearchRecordView? selectedView,
    Object? error,
    bool clearError = false,
    bool clearSelection = false,
    bool? wrapped,
    int? generation,
    int? navigation,
  }) => SearchState(
    visible: visible ?? this.visible,
    draft: draft ?? this.draft,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    activeQuery: activeQuery ?? this.activeQuery,
    options: options ?? this.options,
    submitting: submitting ?? this.submitting,
    complete: complete ?? this.complete,
    invalidated: invalidated ?? this.invalidated,
    total: total ?? this.total,
    selectedIndex: clearSelection ? null : selectedIndex ?? this.selectedIndex,
    selectedHit: clearSelection ? null : selectedHit ?? this.selectedHit,
    selectedView: clearSelection ? null : selectedView ?? this.selectedView,
    error: clearError ? null : error ?? this.error,
    wrapped: wrapped ?? this.wrapped,
    generation: generation ?? this.generation,
    navigation: navigation ?? this.navigation,
  );
}
