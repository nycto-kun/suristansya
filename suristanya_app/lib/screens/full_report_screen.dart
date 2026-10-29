import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/prediction.dart';
import '../models/screening_result.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';

class FullReportScreen extends StatefulWidget {
  const FullReportScreen({super.key});

  @override
  State<FullReportScreen> createState() => _FullReportScreenState();
}

class _FullReportScreenState extends State<FullReportScreen> {
  HealthSummary? _summary;
  List<Prediction>? _predictions;
  ScreeningResult? _screening;
  bool _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_summary != null) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map<String, dynamic>) return;

    // New shape: {predictions: {...}, screening: ScreeningResult?}
    // Legacy shape: {summary: {...}, predictions: [...]}
    Map<String, dynamic>? predsResponse;
    ScreeningResult? screening;

    if (args['predictions'] is Map) {
      predsResponse = (args['predictions'] as Map).cast<String, dynamic>();
      final scr = args['screening'];
      if (scr is ScreeningResult) {
        screening = scr;
      } else if (scr is Map) {
        try {
          screening = ScreeningResult.fromJson(scr.cast<String, dynamic>());
        } catch (_) {}
      }
    } else if (args['summary'] is Map) {
      predsResponse = args;
    }

    if (predsResponse == null) return;

    final summaryJson = (predsResponse['summary'] as Map?)
        ?.cast<String, dynamic>();
    final predictionsJson = predsResponse['predictions'] as List?;
    if (summaryJson == null || predictionsJson == null) return;

    _summary = HealthSummary.fromJson(summaryJson);
    _predictions = predictionsJson
        .map((p) => Prediction.fromJson((p as Map).cast<String, dynamic>()))
        .toList();
    _screening = screening;
  }

  Future<void> _exportPdf() async {
    if (_summary == null || _predictions == null) return;

    setState(() => _exporting = true);
    try {
      final bytes = await PdfService.buildReport(
        summary: _summary!,
        predictions: _predictions!,
        screening: _screening,
        generatedAt: DateTime.now(),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Suristanya_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not export PDF: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_summary == null || _predictions == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Full Report')),
        body: const Center(child: Text('No report to display.')),
      );
    }

    final summary = _summary!;
    final predictions = _predictions!;
    final screening = _screening;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Full Report'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            onPressed: _exporting ? null : _exportPdf,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header card ─────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Screening Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Generated by Suristanya AI',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _StatBox(
                          label: 'Score',
                          value: '${summary.score}',
                          sub: '/100',
                        ),
                        const SizedBox(width: 12),
                        _StatBox(
                          label: 'Status',
                          value: summary.status,
                          sub: '',
                        ),
                        const SizedBox(width: 12),
                        _StatBox(
                          label: 'Confidence',
                          value: summary.confidencePercent,
                          sub: summary.confidenceLabel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── SCREENING section ───────────────────────
              if (screening != null) ...[
                const Text(
                  'Clinical Screening',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                _ScreeningSummaryCard(screening: screening),
                const SizedBox(height: 12),
                ...screening.findings.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ScreeningFindingCard(finding: f),
                  ),
                ),
                if (screening.recommendations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Recommended Steps',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: screening.recommendations
                          .map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      r,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: AppColors.border),
                const SizedBox(height: 20),
              ],

              // ── Summary ─────────────────────────────────
              const Text(
                'Image Analysis Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _summaryText(summary),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Detailed findings ───────────────────────
              const Text(
                'Detailed Findings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              ...predictions.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _DetailedMarkerCard(
                    index: entry.key + 1,
                    prediction: entry.value,
                  ),
                );
              }),
              const SizedBox(height: 8),

              // ── Next steps ──────────────────────────────
              const Text(
                'Next Steps',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildNextSteps(summary, predictions)
                      .map(
                        (step) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  step,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 20),

              // ── Disclaimer ──────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.warning,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This report is generated by an AI screening tool and is not a medical diagnosis. Always consult a qualified healthcare professional before making any health decisions.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Actions ─────────────────────────────────
              FilledButton.icon(
                onPressed: _exporting ? null : _exportPdf,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(_exporting ? 'Preparing...' : 'Download PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back to Results'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summaryText(HealthSummary summary) {
    final status = summary.status.toLowerCase();
    if (status == 'healthy') {
      return 'Your overall screening score is ${summary.score}/100, indicating a healthy presentation. '
          'The visual markers captured in your images are within normal ranges. '
          'Continue with regular health checkups and a balanced lifestyle.';
    }
    if (status.contains('attention')) {
      return 'Your overall screening score is ${summary.score}/100, suggesting some areas to pay attention to. '
          'One or more visual markers showed signs worth monitoring. '
          'Consider a follow-up with a healthcare professional and repeat the scan in a few weeks.';
    }
    return 'Your overall screening score is ${summary.score}/100. '
        'The AI detected visual markers that warrant closer attention. '
        'Please consult a doctor for a complete evaluation.';
  }

  List<String> _buildNextSteps(
    HealthSummary summary,
    List<Prediction> predictions,
  ) {
    final steps = <String>[];

    final moderateOrHigh = predictions
        .where(
          (p) =>
              p.severity.toLowerCase() == 'moderate' ||
              p.severity.toLowerCase() == 'high',
        )
        .toList();

    if (moderateOrHigh.isEmpty) {
      steps.add('Keep up your current routine — no immediate action needed.');
      steps.add('Repeat a scan in 4–6 weeks to track any changes over time.');
    } else {
      steps.add(
        'Focus on these markers: ${moderateOrHigh.map((p) => p.condition).join(", ")}.',
      );
      for (final p in moderateOrHigh) {
        for (final rec in p.recommendations) {
          steps.add(rec);
        }
      }
      steps.add(
        'Consider a routine blood panel (CBC) to confirm the findings.',
      );
    }

    steps.add('Stay hydrated and maintain a balanced, iron-rich diet.');
    steps.add(
      'If symptoms worsen or you feel unwell, seek medical care promptly.',
    );

    return steps;
  }
}

// ─── SCREENING WIDGETS ────────────────────────────────────────

class _ScreeningSummaryCard extends StatelessWidget {
  final ScreeningResult screening;
  const _ScreeningSummaryCard({required this.screening});

  Color get _accent {
    switch (screening.severityRank) {
      case 3:
        return AppColors.danger;
      case 2:
        return AppColors.warning;
      case 1:
        return AppColors.accentDark;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            screening.headline,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _accent,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            screening.message,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreeningFindingCard extends StatelessWidget {
  final ScreeningFinding finding;
  const _ScreeningFindingCard({required this.finding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  finding.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            finding.detail,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
          if (finding.source.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.menu_book_rounded,
                    size: 12,
                    color: AppColors.accentDark,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      finding.source,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.accentDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── IMAGE ANALYSIS WIDGETS ───────────────────────────────────

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  const _StatBox({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  sub,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailedMarkerCard extends StatelessWidget {
  final int index;
  final Prediction prediction;
  const _DetailedMarkerCard({required this.index, required this.prediction});

  Color get _severityColor {
    switch (prediction.severity.toLowerCase()) {
      case 'high':
        return AppColors.danger;
      case 'moderate':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  prediction.condition,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _severityColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  prediction.severity.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _severityColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Confidence',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                prediction.confidencePercent,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _severityColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: prediction.confidence,
              minHeight: 6,
              color: _severityColor,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            prediction.description,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
          if (prediction.detectedFrom.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.image_search_rounded,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Detected from: ${prediction.detectedFrom.join(", ")}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
          if (prediction.recommendations.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RECOMMENDATIONS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...prediction.recommendations.map(
                    (rec) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.arrow_right_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              rec,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
