// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'search_result_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SearchResultState {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is SearchResultState);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'SearchResultState()';
  }
}

/// @nodoc
class $SearchResultStateCopyWith<$Res> {
  $SearchResultStateCopyWith(
      SearchResultState _, $Res Function(SearchResultState) __);
}

/// Adds pattern-matching-related methods to [SearchResultState].
extension SearchResultStatePatterns on SearchResultState {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SearchResultStateLoading value)? loading,
    TResult Function(SearchResultStateLoaded value)? loaded,
    TResult Function(SearchResultStateNoData value)? noData,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case SearchResultStateLoading() when loading != null:
        return loading(_that);
      case SearchResultStateLoaded() when loaded != null:
        return loaded(_that);
      case SearchResultStateNoData() when noData != null:
        return noData(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SearchResultStateLoading value) loading,
    required TResult Function(SearchResultStateLoaded value) loaded,
    required TResult Function(SearchResultStateNoData value) noData,
  }) {
    final _that = this;
    switch (_that) {
      case SearchResultStateLoading():
        return loading(_that);
      case SearchResultStateLoaded():
        return loaded(_that);
      case SearchResultStateNoData():
        return noData(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SearchResultStateLoading value)? loading,
    TResult? Function(SearchResultStateLoaded value)? loaded,
    TResult? Function(SearchResultStateNoData value)? noData,
  }) {
    final _that = this;
    switch (_that) {
      case SearchResultStateLoading() when loading != null:
        return loading(_that);
      case SearchResultStateLoaded() when loaded != null:
        return loaded(_that);
      case SearchResultStateNoData() when noData != null:
        return noData(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? loading,
    TResult Function(List<SearchResult> results, int bookCount)? loaded,
    TResult Function()? noData,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case SearchResultStateLoading() when loading != null:
        return loading();
      case SearchResultStateLoaded() when loaded != null:
        return loaded(_that.results, _that.bookCount);
      case SearchResultStateNoData() when noData != null:
        return noData();
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() loading,
    required TResult Function(List<SearchResult> results, int bookCount) loaded,
    required TResult Function() noData,
  }) {
    final _that = this;
    switch (_that) {
      case SearchResultStateLoading():
        return loading();
      case SearchResultStateLoaded():
        return loaded(_that.results, _that.bookCount);
      case SearchResultStateNoData():
        return noData();
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? loading,
    TResult? Function(List<SearchResult> results, int bookCount)? loaded,
    TResult? Function()? noData,
  }) {
    final _that = this;
    switch (_that) {
      case SearchResultStateLoading() when loading != null:
        return loading();
      case SearchResultStateLoaded() when loaded != null:
        return loaded(_that.results, _that.bookCount);
      case SearchResultStateNoData() when noData != null:
        return noData();
      case _:
        return null;
    }
  }
}

/// @nodoc

class SearchResultStateLoading implements SearchResultState {
  const SearchResultStateLoading();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is SearchResultStateLoading);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'SearchResultState.loading()';
  }
}

/// @nodoc

class SearchResultStateLoaded implements SearchResultState {
  const SearchResultStateLoaded(
      final List<SearchResult> results, this.bookCount)
      : _results = results;

  final List<SearchResult> _results;
  List<SearchResult> get results {
    if (_results is EqualUnmodifiableListView) return _results;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_results);
  }

  final int bookCount;

  /// Create a copy of SearchResultState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SearchResultStateLoadedCopyWith<SearchResultStateLoaded> get copyWith =>
      _$SearchResultStateLoadedCopyWithImpl<SearchResultStateLoaded>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SearchResultStateLoaded &&
            const DeepCollectionEquality().equals(other._results, _results) &&
            (identical(other.bookCount, bookCount) ||
                other.bookCount == bookCount));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, const DeepCollectionEquality().hash(_results), bookCount);

  @override
  String toString() {
    return 'SearchResultState.loaded(results: $results, bookCount: $bookCount)';
  }
}

/// @nodoc
abstract mixin class $SearchResultStateLoadedCopyWith<$Res>
    implements $SearchResultStateCopyWith<$Res> {
  factory $SearchResultStateLoadedCopyWith(SearchResultStateLoaded value,
          $Res Function(SearchResultStateLoaded) _then) =
      _$SearchResultStateLoadedCopyWithImpl;
  @useResult
  $Res call({List<SearchResult> results, int bookCount});
}

/// @nodoc
class _$SearchResultStateLoadedCopyWithImpl<$Res>
    implements $SearchResultStateLoadedCopyWith<$Res> {
  _$SearchResultStateLoadedCopyWithImpl(this._self, this._then);

  final SearchResultStateLoaded _self;
  final $Res Function(SearchResultStateLoaded) _then;

  /// Create a copy of SearchResultState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? results = null,
    Object? bookCount = null,
  }) {
    return _then(SearchResultStateLoaded(
      null == results
          ? _self._results
          : results // ignore: cast_nullable_to_non_nullable
              as List<SearchResult>,
      null == bookCount
          ? _self.bookCount
          : bookCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class SearchResultStateNoData implements SearchResultState {
  const SearchResultStateNoData();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is SearchResultStateNoData);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'SearchResultState.noData()';
  }
}

// dart format on
