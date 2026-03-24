import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../routes/app_routes.dart';

class AuthGuard extends StatefulWidget {
  final Widget child;
  final bool requireAuth;

  const AuthGuard({super.key, required this.child, this.requireAuth = true});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _checkAuth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = Supabase.instance.client.auth.currentSession;
      if (widget.requireAuth && session == null) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      } else if (!widget.requireAuth && session != null) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
