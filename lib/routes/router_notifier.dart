import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

/// Listens to Supabase auth state changes and notifies GoRouter to
/// re-evaluate redirects whenever the user signs in or out.
class RouterNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _authSub;

  RouterNotifier() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  /// Auth-aware redirect. Returns target path or null (stay on current route).
  String? redirect(BuildContext context, GoRouterState state) {
    final isLoggedIn = AuthService.instance.currentSession != null;
    final path = state.matchedLocation;

    const publicPaths = {'/login', '/signup', '/verify-email', '/splash'};
    final isPublic = publicPaths.contains(path);

    if (!isLoggedIn && !isPublic) return '/login';
    if (isLoggedIn && path == '/login') return '/home';
    if (isLoggedIn && path == '/signup') return '/home';
    return null;
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}
