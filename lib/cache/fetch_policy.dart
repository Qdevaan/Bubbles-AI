enum FetchPolicy {
  /// Check cache first, return if exists and not expired. If expired or missing, fetch from network.
  cacheFirst,

  /// Return stale cache immediately while triggering a background refresh.
  staleWhileRevalidate,

  /// Always try network first, fallback to cache on failure.
  networkFirst,

  /// Only ever read from local storage (e.g. settings).
  cacheOnly,
}
