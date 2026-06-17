// Purpose: Bottom sheet for exporting session data — lets the user pick format (PDF/JSON) and trigger the export.
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/design_tokens.dart';
import '../services/auth_service.dart';
import '../repositories/sessions_repository.dart';
import 'package:provider/provider.dart';

import '../widgets/app_sheet.dart';
import '../widgets/app_snack_bar.dart';
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
    return AppSheet.show<void>(
      context: context,
      title: 'Export $sessionTitle',
      subtitle:
          'Choose your preferred format to export the complete session transcript, analytics, and notes.',
      icon: Icons.download_outlined,
      child: ExportBottomSheet(
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Exported session: ${widget.sessionTitle}',
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Export failed: $e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._formats.entries.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedFormat = f.key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedFormat == f.key
                          ? Theme.of(context).colorScheme.primary
                          : (isDark
                              ? AppColors.glassBorder
                              : Colors.grey.shade300),
                      width: _selectedFormat == f.key ? 2 : 1,
                    ),
                    color: _selectedFormat == f.key
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withAlpha(30)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _formatIcons[f.key]!,
                        color: _selectedFormat == f.key
                            ? Theme.of(context).colorScheme.primary
                            : (isDark
                                ? AppColors.slate400
                                : AppColors.slate600),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          f.value,
                          style: GoogleFonts.manrope(
                            fontWeight: _selectedFormat == f.key
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _selectedFormat == f.key
                                ? Theme.of(context).colorScheme.primary
                                : (isDark
                                    ? AppColors.slate300
                                    : AppColors.slate700),
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
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _exporting ? null : _handleExport,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'Export',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }
}
