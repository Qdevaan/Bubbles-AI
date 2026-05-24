import 'package:flutter/services.dart' show rootBundle;

/// Memoised loaders for static asset strings shared across screens.
///
/// `rootBundle.loadString` performs an async asset lookup each call. The
/// graph WebView template is the same on every navigation — there is no
/// reason to re-read it from disk. `template` caches the parsed string in
/// a process-lifetime `Future` so subsequent reads complete on the
/// microtask queue.
class GraphAssets {
  GraphAssets._();

  static Future<String>? _templateFuture;

  /// HTML template that renders the user's knowledge graph inside a
  /// `webview_flutter` view. Subsequent calls return the cached future.
  static Future<String> get template {
    return _templateFuture ??=
        rootBundle.loadString('assets/text/graph_template.html');
  }
}
