import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/design_tokens.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../repositories/sessions_repository.dart';
import 'package:provider/provider.dart';

class ExportBottomSheet extends StatefulWidget {
  final String sessionId;
  final String sessionTitle;
  final bool isConsultant;

  const ExportBottomSheet({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
    this.isConsultant = false,
  });

  static Future<void> show(BuildContext context, String sessionId, String sessionTitle, {bool isConsultant = false}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportBottomSheet(
        sessionId: sessionId,
        sessionTitle: sessionTitle,
        isConsultant: isConsultant,
      ),
    );
  }

  @override
  State<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends State<ExportBottomSheet> {
  String _selectedFormat = 'markdown';
  bool _exporting = false;

  final Map<String, String> _formats = {
    'markdown': 'Markdown (.md)',
    'txt': 'Text (.txt)',
    'json': 'JSON Data'
  };

  final Map<String, IconData> _formatIcons = {
    'markdown': Icons.text_snippet_outlined,
    'txt': Icons.article_outlined,
    'json': Icons.data_object_rounded,
  };

  Future<void> _handleExport() async {
    setState(() => _exporting = true);
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) throw Exception("Not logged in");

      final repo = context.read<SessionsRepository>();
      final result = await repo.getSessionLogs(widget.sessionId, widget.isConsultant, user.id);
      final logs = result.data ?? [];

      if (logs.isEmpty) throw Exception("No logs to export.");

      String dataStr = "";
      String ext = _selectedFormat == 'markdown' ? 'md' : _selectedFormat;
      
      if (_selectedFormat == 'json') {
        dataStr = const JsonEncoder.withIndent('  ').convert(logs);
      } else if (_selectedFormat == 'markdown') {
        dataStr = "# ${widget.sessionTitle}\n\n";
        for (var log in logs) {
          if (widget.isConsultant) {
            final q = log['question']?.toString() ?? log['query']?.toString() ?? '';
            final a = log['answer']?.toString() ?? log['response']?.toString() ?? '';
            if (q.isNotEmpty) dataStr += "**You**:\n$q\n\n";
            if (a.isNotEmpty) dataStr += "**Consultant AI**:\n$a\n\n";
          } else {
            final role = log['role']?.toString() ?? 'unknown';
            final content = log['content']?.toString() ?? '';
            dataStr += "**${role.toUpperCase()}**:\n$content\n\n";
          }
        }
      } else if (_selectedFormat == 'txt') {
        dataStr = "Title: ${widget.sessionTitle}\n\n";
        for (var log in logs) {
          if (widget.isConsultant) {
            final q = log['question']?.toString() ?? log['query']?.toString() ?? '';
            final a = log['answer']?.toString() ?? log['response']?.toString() ?? '';
            if (q.isNotEmpty) dataStr += "You:\n$q\n\n";
            if (a.isNotEmpty) dataStr += "Consultant AI:\n$a\n\n";
          } else {
            final role = log['role']?.toString() ?? 'unknown';
            final content = log['content']?.toString() ?? '';
            dataStr += "${role.toUpperCase()}:\n$content\n\n";
          }
        }
      }

      final dir = await getTemporaryDirectory();
      final filename = "Session_${widget.sessionId}.$ext";
      final file = File('${dir.path}/$filename');
      await file.writeAsString(dataStr);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Exported session: ${widget.sessionTitle}',
      );

      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
          )
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1B1F).withAlpha(240) : Colors.white.withAlpha(240),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: isDark ? AppColors.glassBorder : Colors.grey.shade300),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Export ${widget.sessionTitle}',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose your preferred format to export the complete session transcript, analytics, and notes.',
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: isDark ? AppColors.slate400 : AppColors.slate600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            
            ..._formats.entries.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedFormat = f.key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedFormat == f.key
                          ? Theme.of(context).colorScheme.primary
                          : (isDark ? AppColors.glassBorder : Colors.grey.shade300),
                      width: _selectedFormat == f.key ? 2 : 1,
                    ),
                    color: _selectedFormat == f.key
                        ? Theme.of(context).colorScheme.primary.withAlpha(30)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _formatIcons[f.key]!,
                        color: _selectedFormat == f.key
                            ? Theme.of(context).colorScheme.primary
                            : (isDark ? AppColors.slate400 : AppColors.slate600),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          f.value,
                          style: GoogleFonts.manrope(
                            fontWeight: _selectedFormat == f.key ? FontWeight.w700 : FontWeight.w600,
                            color: _selectedFormat == f.key
                                ? Theme.of(context).colorScheme.primary
                                : (isDark ? AppColors.slate300 : AppColors.slate700),
                          ),
                        ),
                      ),
                      if (_selectedFormat == f.key)
                        Icon(
                          Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            )),
            
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _exporting ? null : _handleExport,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _exporting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Export',
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
