// Purpose: Dev-only screenshot capture tool — wraps a child widget and saves PNG screenshots to storage.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/
/// Long-screenshot developer tool.
///
/// A draggable hover button (debug builds only) that captures the *entire*
/// scrollable content of the current screen as one tall PNG and writes it to
/// `Documentation/Screenshots/` inside the app's external storage dir. Files
/// are auto-named after the current route (e.g. `settings__performa.png`), so
/// the capture for the Settings → Performa screen lands as `settings__performa`.
///
/// Capture strategy:
///   • Locate the dominant vertical scrollable in the widget tree.
///   • If it doesn't scroll → single full-screen frame.
///   • Otherwise auto-scroll top→bottom, grab each viewport via a
///     [RepaintBoundary], crop out the scrolling region, and stitch the strips
///     into one image — keeping the header (app bar) and footer (bottom nav)
///     exactly once.
///
/// On Android the output dir resolves to:
///   /storage/emulated/0/Android/data/<pkg>/files/Documentation/Screenshots
/// Pull it with:
///   adb pull /sdcard/Android/data/<pkg>/files/Documentation/Screenshots ./Documentation
/

/// Tracks the live navigator stack so captures can be named after the route
/// that's currently on screen (including nested sub-screens and popups).
class ScreenshotRouteObserver extends NavigatorObserver {
  ScreenshotRouteObserver._();
  static final ScreenshotRouteObserver instance = ScreenshotRouteObserver._();

  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final int i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
  }

  /// A filesystem-safe base name derived from the current route.
  ///
  /// `/settings/performa` → `settings__performa`. A popup/dialog with no route
  /// name is labelled after its parent, e.g. `settings__popup`.
  String currentName() {
    if (_stack.isEmpty) return 'screen';

    final String? topName = _stack.last.settings.name;
    if (topName != null && topName.trim().isNotEmpty) {
      return _slug(topName);
    }

    // Unnamed top route (e.g. showDialog) → name after nearest named parent.
    for (int i = _stack.length - 2; i >= 0; i--) {
      final String? name = _stack[i].settings.name;
      if (name != null && name.trim().isNotEmpty) {
        return '${_slug(name)}__popup';
      }
    }
    return 'popup';
  }

  String _slug(String routeName) {
    var s = routeName.trim();
    if (s.startsWith('/')) s = s.substring(1);
    s = s
        .replaceAll('/', '__')
        .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    s = s.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
    return s.isEmpty ? 'screen' : s;
  }
}

/// Wraps the whole app: provides the capture [RepaintBoundary] and the
/// draggable trigger button. No-op in release builds.
class ScreenshotTool extends StatefulWidget {
  final Widget child;
  const ScreenshotTool({super.key, required this.child});

  @override
  State<ScreenshotTool> createState() => _ScreenshotToolState();
}

class _ScreenshotToolState extends State<ScreenshotTool> {
  final GlobalKey _boundaryKey = GlobalKey();
  Offset? _btnPos; // null → use default bottom-right
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;

    final Size screen = MediaQuery.of(context).size;
    final Offset pos = _btnPos ??
        Offset(screen.width - 64, screen.height - 160);

    return Stack(
      children: [
        // Everything below the button is what gets captured.
        RepaintBoundary(key: _boundaryKey, child: widget.child),

        // Block input while a capture is running.
        if (_busy)
          const Positioned.fill(
            child: IgnorePointer(child: SizedBox.expand()),
          ),

        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: _DragButton(
            busy: _busy,
            onTap: _busy ? null : _capture,
            onDrag: (delta) {
              setState(() {
                final Offset next = pos + delta;
                _btnPos = Offset(
                  next.dx.clamp(0.0, screen.width - 48),
                  next.dy.clamp(0.0, screen.height - 48),
                );
              });
            },
          ),
        ),
      ],
    );
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    String message = '';
    try {
      // Hard timeout so the button can never spin forever, whatever the cause.
      final String path =
          await _runCapture().timeout(const Duration(seconds: 60));
      message = 'Saved → $path';
      debugPrint('📸 long-screenshot saved → $path');
    } catch (e, st) {
      message = 'Capture failed: $e';
      debugPrint('📸 long-screenshot FAILED: $e\n$st');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && message.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 12)),
          duration: const Duration(seconds: 4),
        ));
    }
  }

  // core

  Future<String> _runCapture() async {
    final BuildContext? ctx = _boundaryKey.currentContext;
    if (ctx == null) throw StateError('boundary not mounted');

    final RenderRepaintBoundary boundary =
        ctx.findRenderObject()! as RenderRepaintBoundary;
    final double pr = MediaQuery.of(ctx).devicePixelRatio;

    final ScrollableState? scrollable = _dominantScrollable(ctx);

    final bool scrollUsable = scrollable != null &&
        scrollable.position.hasContentDimensions &&
        scrollable.position.axis == Axis.vertical &&
        scrollable.position.maxScrollExtent >= 1.0;

    img.Image composed;
    if (!scrollUsable) {
      composed = await _grab(boundary, pr); // single frame
    } else {
      composed = await _captureLong(boundary, scrollable, pr);
    }

    final Uint8List png = Uint8List.fromList(img.encodePng(composed));
    return _write(png);
  }

  /// Scroll the screen top→bottom and stitch a tall image.
  Future<img.Image> _captureLong(
    RenderRepaintBoundary boundary,
    ScrollableState scrollable,
    double pr,
  ) async {
    final ScrollPosition position = scrollable.position;
    final double original = position.pixels;

    // Viewport rectangle (global logical coords == capture coords).
    final RenderBox vpBox =
        scrollable.context.findRenderObject()! as RenderBox;
    final Offset vpTopLeft = vpBox.localToGlobal(Offset.zero);
    final Size vpSize = vpBox.size;

    final int vpTopPx = (vpTopLeft.dy * pr).round();
    final int vpHeightPx = (vpSize.height * pr).round();
    final double vpH = vpSize.height;

    // First frame establishes header (above viewport) + footer (below it).
    // jumpTo (not animateTo) avoids triggering pull-to-refresh / overscroll.
    position.jumpTo(0);
    await _settle();
    final img.Image first = await _grab(boundary, pr);

    final int fullW = first.width;
    final int fullH = first.height;
    final img.Image header =
        vpTopPx > 0 ? img.copyCrop(first, x: 0, y: 0, width: fullW, height: vpTopPx) : img.Image(width: fullW, height: 0);
    final int footerTopPx = vpTopPx + vpHeightPx;
    final img.Image footer = footerTopPx < fullH
        ? img.copyCrop(first, x: 0, y: footerTopPx, width: fullW, height: fullH - footerTopPx)
        : img.Image(width: fullW, height: 0);

    // Walk the scroll content, cropping the viewport region each step and
    // trimming any overlap with what we've already captured.
    // Safety cap: paginated / infinite-scroll lists (e.g. session history)
    // grow maxScrollExtent on every step and never report a true bottom.
    // Bound the walk so capture always terminates.
    const int kMaxStrips = 40;
    final List<img.Image> strips = <img.Image>[];
    double capturedLogical = 0; // content height already captured
    double target = 0;
    double prevActual = -1;
    while (strips.length < kMaxStrips) {
      // Re-read maxScrollExtent each step — it can change as lazy content
      // builds or pages load while scrolling.
      position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      await _settle();
      final double actual = position.pixels;

      final img.Image frame =
          (capturedLogical == 0) ? first : await _grab(boundary, pr);

      // Where, inside the viewport, does the not-yet-captured content begin?
      final double skipLogical = (capturedLogical - actual).clamp(0.0, vpH);
      final double newLogical = vpH - skipLogical;
      if (newLogical > 0.5) {
        final int cropY = vpTopPx + (skipLogical * pr).round();
        int cropH = (newLogical * pr).round();
        if (cropY + cropH > vpTopPx + vpHeightPx) {
          cropH = (vpTopPx + vpHeightPx) - cropY;
        }
        if (cropH > 0) {
          strips.add(img.copyCrop(frame, x: 0, y: cropY, width: fullW, height: cropH));
          capturedLogical = actual + vpH;
        }
      }

      // Stop at the real bottom, or when the list can no longer advance
      // (covers never-ending paginated lists once they stall or hit the cap).
      if (actual >= position.maxScrollExtent - 0.5) break;
      if (actual <= prevActual + 0.5) break;
      prevActual = actual;
      target = actual + vpH;
    }

    // Restore the user's scroll position.
    position.jumpTo(original.clamp(0, position.maxScrollExtent));

    // Assemble: header + strips + footer.
    int totalH = header.height + footer.height;
    for (final s in strips) {
      totalH += s.height;
    }
    final img.Image canvas = img.Image(width: fullW, height: totalH);
    // Fill white so any transparency reads cleanly in docs.
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    int y = 0;
    if (header.height > 0) {
      img.compositeImage(canvas, header, dstX: 0, dstY: y);
      y += header.height;
    }
    for (final s in strips) {
      img.compositeImage(canvas, s, dstX: 0, dstY: y);
      y += s.height;
    }
    if (footer.height > 0) {
      img.compositeImage(canvas, footer, dstX: 0, dstY: y);
    }
    return canvas;
  }

  Future<img.Image> _grab(RenderRepaintBoundary boundary, double pr) async {
    final ui.Image image = await boundary.toImage(pixelRatio: pr);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('toByteData returned null');
    final img.Image? decoded =
        img.decodePng(bytes.buffer.asUint8List());
    if (decoded == null) throw StateError('decodePng failed');
    return decoded;
  }

  /// Wait for layout + paint to settle after a programmatic scroll.
  Future<void> _settle() async {
    await SchedulerBinding.instance.endOfFrame;
    // Give freshly-built (lazy) list rows time to lay out & paint.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await SchedulerBinding.instance.endOfFrame;
  }

  /// Find the vertical scrollable with the largest scroll extent in the tree.
  ScrollableState? _dominantScrollable(BuildContext context) {
    ScrollableState? best;
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final s = element.state as ScrollableState;
        final p = s.position;
        if (p.axis == Axis.vertical) {
          if (best == null ||
              p.maxScrollExtent > best!.position.maxScrollExtent) {
            best = s;
          }
        }
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return best;
  }

  Future<String> _write(Uint8List png) async {
    Directory base;
    if (Platform.isAndroid) {
      base = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final Directory dir =
        Directory('${base.path}/Documentation/Screenshots');
    await dir.create(recursive: true);

    final String name = ScreenshotRouteObserver.instance.currentName();
    String fileName = '$name.png';
    int n = 1;
    while (await File('${dir.path}/$fileName').exists()) {
      fileName = '${name}_$n.png';
      n++;
    }
    final File file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }
}

class _DragButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;
  final void Function(Offset delta) onDrag;
  const _DragButton({
    required this.busy,
    required this.onTap,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => onDrag(d.delta),
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.screenshot_monitor,
                  color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
