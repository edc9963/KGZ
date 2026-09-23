/// A small `firstOrNull` for [Iterable], shared by [AppStore] and the
/// domain managers/queries in this folder. Kept as a local extension
/// (instead of depending on `package:collection`) to match how the rest
/// of the codebase already avoided that dependency.
extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
