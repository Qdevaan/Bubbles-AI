enum CacheSource { memory, disk, network, none }

class CacheResult<T> {
  final T? data;
  final CacheSource source;
  final bool isStale;
  final int ageMs;

  CacheResult({
    this.data,
    required this.source,
    this.isStale = false,
    this.ageMs = 0,
  });

  bool get hasData => data != null;

  @override
  String toString() {
    return 'CacheResult(source: $source, isStale: $isStale, ageMs: $ageMs, hasData: $hasData)';
  }
}
