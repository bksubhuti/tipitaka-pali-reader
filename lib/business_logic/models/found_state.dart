import 'package:flutter/foundation.dart';

import 'found_info.dart';

sealed class FoundState {}

class FoundInitial extends FoundState {}

class FoundEmpty extends FoundState {}

class FoundData extends FoundState {
  final List<FoundInfo> founds;
  final int? current;
  FoundData({required this.founds, this.current});

  FoundData copyWith({
    List<FoundInfo>? founds,
    int? current,
  }) {
    return FoundData(
      founds: founds ?? this.founds,
      current: current ?? this.current,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FoundData &&
        listEquals(other.founds, founds) &&
        other.current == current;
  }

  @override
  int get hashCode => founds.hashCode ^ current.hashCode;
}
