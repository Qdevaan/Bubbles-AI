import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/app_cache_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/glass_morphism.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _exporting = false;
  String? _exportError;
  bool _deleting = false;
  String? _deleteError;
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportData() async {
    setState(() { _exporting = true; _exportError = null; });
    try {
      final user = AuthService.instance.currentUser!;
      final sb = Supabase.instance.client;

      final sessions = await sb
          .from('sessions')
          .select('id, title, mode, created_at, summary')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      final entities = await sb
          .from('entities')
          .select('id, display_name, entity_type, description, mention_count')
          .eq('user_id', user.id);
      final highlights = await sb
          .from('highlights')
          .select('id, title, body, highlight_type, created_at')
          .eq('user_id', user.id);

      final export = jsonEncode({
        'exported_at': DateTime.now().toIso8601String(),
        'user_id': user.id,
        'sessions': sessions,
        'entities': entities,
        'highlights': highlights,
      });

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/bubbles_export_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(export);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bubbles AI — My Data Export',
      );
    } catch (e) {
      if (mounted) setState(() => _exportError = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showDeleteConfirmation() async {
    _confirmCtrl.clear();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
          title: Text('Delete Account',
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This is permanent and cannot be undone. All your data will be deleted.',
                style: GoogleFonts.manrope(fontSize: 13, color: AppColors.slate400),
              ),
              const SizedBox(height: 16),
              Text('Type DELETE to confirm:',
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.slate900)),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                style: GoogleFonts.manrope(
                    color: isDark ? Colors.white : AppColors.slate900),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: GoogleFonts.manrope(color: AppColors.slate400),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (_deleteError != null) ...[
                const SizedBox(height: 8),
                Text(_deleteError!,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.manrope(color: AppColors.slate400)),
            ),
            TextButton(
              onPressed: _deleting
                  ? null
                  : () async {
                      if (_confirmCtrl.text.trim() != 'DELETE') {
                        setDialogState(() =>
                            _deleteError = 'Type DELETE exactly to confirm.');
                        return;
                      }
                      setDialogState(
                          () { _deleting = true; _deleteError = null; });
                      try {
                        await AuthService.instance.deleteAccount();
                        if (mounted) {
                          context.read<AppCacheService>().invalidateAll();
                        }
                        await AuthService.instance.signOut();
                        if (ctx.mounted) {
                          ctx.go('/login');
                        }
                      } catch (e) {
                        setDialogState(() {
                          _deleting = false;
                          _deleteError =
                              'Deletion failed. Your account was not deleted.';
                        });
                      }
                    },
              child: Text('Delete',
                  style: GoogleFonts.manrope(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: isDark ? Colors.white : AppColors.slate900,
                          size: 20),
                    ),
                    const SizedBox(width: 16),
                    Text('Data Management',
                        style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Colors.white : AppColors.slate900)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // Export card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha(26),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.download_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text('Export My Data',
                                    style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.slate900)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Downloads your sessions, entities, and highlights as a JSON file and opens the share sheet.',
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: AppColors.slate400),
                            ),
                            if (_exportError != null) ...[
                              const SizedBox(height: 8),
                              Text(_exportError!,
                                  style: GoogleFonts.manrope(
                                      fontSize: 12, color: AppColors.error)),
                            ],
                            const SizedBox(height: 16),
                            AppButton(
                              label: 'Export Data',
                              icon: Icons.ios_share_rounded,
                              loading: _exporting,
                              onTap: _exportData,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Delete card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withAlpha(26),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.delete_forever_rounded,
                                      color: AppColors.error, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text('Delete Account',
                                    style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.error)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Permanently deletes your account and all associated data. This cannot be undone.',
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: AppColors.slate400),
                            ),
                            const SizedBox(height: 16),
                            AppButton(
                              label: 'Delete My Account',
                              icon: Icons.warning_amber_rounded,
                              onTap: _showDeleteConfirmation,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
