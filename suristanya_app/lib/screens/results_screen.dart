import 'package:flutter/material.dart';

import '../models/prediction.dart';
import '../models/screening_result.dart';
import '../theme/app_theme.dart';
import '../widgets/result_card.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is! Map<String, dynamic>) {
      return _scaffoldMessage(
        'No results to show.\nPlease complete a scan first.',
      );
    }

    Map<String, dynamic>? predictionsResponse;
    ScreeningResult? screening;

    if (args['predictions'] is Map) {
      predictionsResponse = (args['predictions'] as Map)
          .cast<String, dynamic>();
      final scr = args['screening'];
      if (scr is ScreeningResult) {
        screening = scr;
      } else if (scr is Map) {
        try {
          screening = ScreeningResult.fromJson(scr.cast<String, dynamic>());
        } catch (_) {}
      }
    } else if (args['summary'] is Map) {
      predictionsResponse = args;
    }

    final summaryJson = (predictionsResponse?['summary'] as Map?)
        ?.cast<String, dynamic>();
    final predictionsJson = predictionsResponse?['predictions'] as List?;

    if (summaryJson == null || predictionsJson == null) {
      return _scaffoldMessage('Malformed response from server.');
    }

    final summary = HealthSummary.fromJson(summaryJson);
    final predictions = predictionsJson
        .map((p) => Prediction.fromJson((p as Map).cast<String, dynamic>()))
        .toList();

    final severityRank = {'high': 3, 'moderate': 2, 'low': 1};
    final primary = predictions.isEmpty
        ? null
        : predictions.reduce((a, b) {
            final ra = severityRank[a.severity.toLowerCase()] ?? 0;
            final rb = severityRank[b.severity.toLowerCase()] ?? 0;
            return ra >= rb ? a : b;
          });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Your Health Insights'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          // FIXED: Routes back to Dashboard instead of Chat
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            '/dashboard',
            (route) => false,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (screening != null) ...[
                _ScreeningCard(screening: screening),
                const SizedBox(height: 20),
                const _SectionLabel('Clinical Findings'),
                const SizedBox(height: 10),
                ...screening.findings.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FindingCard(finding: f),
                  ),
                ),
                if (screening.recommendations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const _SectionLabel('Recommended Steps'),
                  const SizedBox(height: 10),
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

              const _SectionLabel('Image Analysis'),
              const SizedBox(height: 10),

              // Hero Score Card
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
                      'Overall Health Score',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          height: 96,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: summary.score / 100),
                            duration: const Duration(milliseconds: 1100),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 96,
                                    height: 96,
                                    child: CircularProgressIndicator(
                                      value: value,
                                      strokeWidth: 8,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      valueColor: const AlwaysStoppedAnimation(
                                        AppColors.accent,
                                      ),
                                      strokeCap: StrokeCap.round,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${(value * 100).round()}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                      ),
                                      const Text(
                                        '/ 100',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      summary.status.toLowerCase() == 'healthy'
                                      ? AppColors.success.withValues(alpha: 0.9)
                                      : AppColors.warning.withValues(
                                          alpha: 0.9,
                                        ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  summary.status,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Confidence: ${summary.confidencePercent}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '(${summary.confidenceLabel} confidence)',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  const Text(
                    'Key Findings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${predictions.length} markers',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              ...predictions.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ResultCard(
                    prediction: p,
                    isPrimary: identical(p, primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Disclaimer
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
                        'This is a screening tool, not a diagnosis. Please consult a doctor for medical advice.',
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

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      // FIXED: Routes to dashboard and clears history
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/dashboard',
                        (route) => false,
                      ),
                      child: const Text('Back to Dashboard'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/full-report',
                        arguments: args,
                      ),
                      child: const Text('View Full Result'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                // FIXED: Starts a fresh scan
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/chat',
                  (route) => false,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Scan Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scaffoldMessage(String text) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Results')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _ScreeningCard extends StatelessWidget {
  final ScreeningResult screening;
  const _ScreeningCard({required this.screening});

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

  IconData get _icon {
    switch (screening.severityRank) {
      case 3:
        return Icons.warning_amber_rounded;
      case 2:
        return Icons.priority_high_rounded;
      case 1:
        return Icons.info_outline_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SCREENING RESULT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      screening.headline,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _accent,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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

class _FindingCard extends StatelessWidget {
  final ScreeningFinding finding;
  const _FindingCard({required this.finding});

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
