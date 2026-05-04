import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/performa.dart';
import '../services/api_service.dart';

class PerformaRepository {
  final ApiService _api;
  Performa? _cache;

  PerformaRepository(this._api);

  // -- CRUD ------------------------------------------------------------------

  Future<Performa> fetch(String userId) async {
    final data = await _api.getPerforma(userId);
    if (data == null) return Performa(userId: userId);
    _cache = Performa.fromSupabaseRow(data);
    return _cache!;
  }

  Future<void> save(String userId, Performa performa) async {
    await _api.updatePerforma(userId, performa.toManualJson());
    _cache = performa;
  }

  Future<void> approveInsight(String userId, String insightId, bool approved) async {
    await _api.approvePerformaInsight(userId, insightId, approved);
    if (_cache != null) {
      final updated = _cache!.aiInsights.map((i) {
        if (i.id == insightId) return i.copyWith(approved: approved);
        return i;
      }).where((i) => approved || i.id != insightId).toList();
      _cache = _cache!.copyWith(aiInsights: updated);
    }
  }

  Future<List<Map<String, dynamic>>> fetchPendingInsights(String userId) async {
    return await _api.getPerformaPendingInsights(userId) ?? [];
  }

  // -- Export ----------------------------------------------------------------

  Future<File> exportJson(Performa performa) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/performa_${performa.userId}.json');
    final map = {
      ...performa.toManualJson(),
      'aiInsights': performa.aiInsights.where((i) => i.approved).map((i) => i.toJson()).toList(),
      'inferredStrengths': performa.inferredStrengths,
      'inferredWeaknesses': performa.inferredWeaknesses,
      'notablePatterns': performa.notablePatterns,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(map));
    return file;
  }

  Future<File> exportMarkdown(Performa performa) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/performa_${performa.userId}.md');
    final buf = StringBuffer();
    buf.writeln('# My Performa Profile\n');
    buf.writeln('## About Me');
    if (performa.fullName.isNotEmpty) buf.writeln('**Name:** ${performa.fullName}');
    if (performa.role.isNotEmpty) buf.writeln('**Role:** ${performa.role}${performa.company.isNotEmpty ? " at ${performa.company}" : ""}');
    if (performa.industry.isNotEmpty) buf.writeln('**Industry:** ${performa.industry}');
    if (performa.communicationStyle.isNotEmpty) buf.writeln('**Style:** ${performa.communicationStyle}');
    if (performa.background.isNotEmpty) buf.writeln('\n${performa.background}');
    if (performa.goals.isNotEmpty) {
      buf.writeln('\n## Goals');
      for (final g in performa.goals) buf.writeln('- $g');
    }
    if (performa.conversationScenarios.isNotEmpty) {
      buf.writeln('\n## Conversation Scenarios');
      for (final s in performa.conversationScenarios) buf.writeln('- $s');
    }
    if (performa.recurringContacts.isNotEmpty) {
      buf.writeln('\n## Key People');
      for (final c in performa.recurringContacts) {
        buf.writeln('- **${c.name}** (${c.relationship})${c.notes.isNotEmpty ? ": ${c.notes}" : ""}');
      }
    }
    if (performa.customKeywords.isNotEmpty) {
      buf.writeln('\n## Watch Keywords');
      buf.writeln(performa.customKeywords.join(', '));
    }
    final approved = performa.aiInsights.where((i) => i.approved).toList();
    if (approved.isNotEmpty) {
      buf.writeln('\n## AI Insights');
      for (final i in approved) buf.writeln('- ${i.text}');
    }
    await file.writeAsString(buf.toString());
    return file;
  }

  Future<File> exportPdf(Performa performa) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/performa_${performa.userId}.pdf');
    final pdf = pw.Document();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Header(level: 0, child: pw.Text('Performa Profile', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 16),
        _pdfSection('About Me', [
          if (performa.fullName.isNotEmpty) 'Name: ${performa.fullName}',
          if (performa.role.isNotEmpty) 'Role: ${performa.role}${performa.company.isNotEmpty ? " at ${performa.company}" : ""}',
          if (performa.industry.isNotEmpty) 'Industry: ${performa.industry}',
          if (performa.communicationStyle.isNotEmpty) 'Style: ${performa.communicationStyle}',
        ]),
        if (performa.goals.isNotEmpty) _pdfSection('Goals', performa.goals),
        if (performa.conversationScenarios.isNotEmpty) _pdfSection('Scenarios', performa.conversationScenarios),
        if (performa.recurringContacts.isNotEmpty) _pdfSection('Key People',
          performa.recurringContacts.map((c) => '${c.name} (${c.relationship})').toList()),
        if (performa.customKeywords.isNotEmpty) _pdfSection('Watch Keywords', [performa.customKeywords.join(', ')]),
        if (performa.background.isNotEmpty) _pdfSection('Background', [performa.background]),
        _pdfInsightsTable(performa.aiInsights.where((i) => i.approved).toList()),
      ],
    ));

    await file.writeAsBytes(await pdf.save());
    return file;
  }

  pw.Widget _pdfSection(String title, List<String> items) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      ...items.map((i) => pw.Text('• $i', style: const pw.TextStyle(fontSize: 11))),
      pw.SizedBox(height: 12),
    ],
  );

  pw.Widget _pdfInsightsTable(List<PerformaInsight> insights) {
    if (insights.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('AI Insights', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Insight', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Confidence', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
            ]),
            ...insights.map((i) => pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(i.text, style: const pw.TextStyle(fontSize: 10))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${(i.confidence * 100).round()}%', style: const pw.TextStyle(fontSize: 10))),
            ])),
          ],
        ),
      ],
    );
  }
}
