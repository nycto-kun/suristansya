import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/body_scan.dart';
import '../models/screening_result.dart';
import '../services/api_service.dart';
import '../services/scan_history_store.dart';
import '../services/screening_session.dart';
import '../theme/app_theme.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _progressTimer;
  int _progress = 0;
  int _stepIndex = 0;

  Map<String, dynamic>? _predictionResponse;
  ScreeningResult? _screeningResponse;
  String? _error;
  bool _started = false;

  static const _steps = [
    'Uploading images...',
    'Running AI diagnostics...',
    'Applying clinical rules...',
    'Evaluating health markers...',
    'Preparing your insights...',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _startProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  void _startProgress() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      if (_progress >= 100) {
        t.cancel();
        _tryNavigate();
        return;
      }
      if (!mounted) return;
      setState(() {
        _progress = (_progress + 2).clamp(0, 100);
        _stepIndex = (_progress / 22).floor().clamp(0, _steps.length - 1);
      });
    });
  }

  Future<void> _runAll() async {
    if (_started) return;
    _started = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map<BodyPart, XFile>) {
      setState(() => _error = 'No images were provided.');
      return;
    }

    try {
      final imageBytes = <String, List<int>>{};
      for (final entry in args.entries) {
        final bytes = await entry.value.readAsBytes();
        imageBytes[entry.key.apiKey] = bytes;
      }

      // 1. GET PREDICTION FROM AI
      final predictionResponse = await ApiService.instance.predictFromBytes(images: imageBytes);

      ScreeningResult? screeningResponse;
      try {
        screeningResponse = await ApiService.instance.assessScreen(ScreeningSession.instance.toJson());
      } catch (_) {}

      // 2. EXTRACT THE RAW LOGGING DATA
      final rawProbs = predictionResponse['raw_probs'];
      final modelVersion = predictionResponse['model_version'];

      // 3. SAVE TO DATABASE (Passing the new variables)
      await ScanHistoryStore.instance.add(
        apiResponse: predictionResponse,
        screening: screeningResponse,
        images: imageBytes,
        rawProbs: rawProbs,           // <-- NEW
        modelVersion: modelVersion,   // <-- NEW
      );

      if (!mounted) return;
      setState(() {
        _predictionResponse = predictionResponse;
        _screeningResponse = screeningResponse;
      });
      _tryNavigate();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _tryNavigate() {
    if (!mounted) return;
    if (_error != null) return;
    if (_progress < 100) return;
    if (_predictionResponse == null) return;

    // FIXES BACK BUTTON: Clears Scan screen, returns to Dashboard when Back is pressed
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/results',
      ModalRoute.withName('/dashboard'), 
      arguments: {
        'predictions': _predictionResponse,
        'screening': _screeningResponse,
      },
    );
  }

  void _retry() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(child: _error != null ? _buildError() : _buildLoading()),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Something went wrong', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.4)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _retry,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
              child: const Text('Back to Scan'),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(),
          const Text('Analyzing Results', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 8),
          Text('Analyzing your health markers', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
          const SizedBox(height: 40),
          SizedBox(
            width: 240, height: 240,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    ...List.generate(3, (i) {
                      return Container(
                        width: 80.0 + i * 60, height: 80.0 + i * 60,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.accent.withValues(alpha: 0.15 + i * 0.08), width: 1.5)),
                      );
                    }),
                    Transform.rotate(
                      angle: _controller.value * 2 * math.pi,
                      child: Container(
                        width: 220, height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [AppColors.accent.withValues(alpha: 0.0), AppColors.accent.withValues(alpha: 0.55), AppColors.accent.withValues(alpha: 0.0)],
                            stops: const [0.0, 0.15, 0.3],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withValues(alpha: 0.15), border: Border.all(color: AppColors.accent, width: 2)),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 40),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: _progress / 100, minHeight: 6, color: AppColors.accent, backgroundColor: Colors.white.withValues(alpha: 0.1)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_steps[_stepIndex], style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600)),
              Text('$_progress%', style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}