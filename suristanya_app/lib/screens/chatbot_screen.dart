import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/screening_session.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatMessage {
  final String text;
  final ChatRole role;
  _ChatMessage(this.text, this.role);
}

enum _Stage { sex, pregnancy, age, symptoms, riskFactors, complete }

class _ChatbotScreenState extends State<ChatbotScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _freeText = TextEditingController();
  final List<_ChatMessage> _messages = [];
  _Stage _stage = _Stage.sex;
  bool _isTyping = false;

  ScreeningSession get _session => ScreeningSession.instance;

  static const _symptomLabels = {
    'fatigue': 'Fatigue or tiredness',
    'pallor': 'Pale skin, palms, or eyelids',
    'shortness_of_breath': 'Shortness of breath',
    'pica': 'Craving non-food items',
    'restless_legs': 'Restless legs at night',
    'hair_loss': 'Hair thinning or loss',
    'dizziness': 'Dizziness or lightheadedness',
    'cold_extremities': 'Cold hands and feet',
    'headache': 'Frequent headaches',
    'palpitations': 'Racing or pounding heartbeat',
    'smooth_tongue': 'Smooth or sore tongue',
    'brittle_nails': 'Brittle or ridged nails',
  };

  static const _riskLabels = {
    'heavy_menstruation': 'Heavy menstrual bleeding',
    // 'pregnancy': 'Currently pregnant', <-- Removed because it's redundant
    'gi_bleeding_history': 'History of GI bleeding',
    'nsaid_use': 'Regular NSAID use',
    'celiac': 'Celiac disease',
    'ibd': 'Inflammatory bowel disease',
    'bariatric_surgery': 'Bariatric surgery',
    'vegan_vegetarian': 'Vegan or vegetarian diet',
    'frequent_blood_donation': 'Frequent blood donation',
    'ckd': 'Chronic kidney disease',
    'heart_failure': 'Heart failure',
  };

  @override
  void initState() {
    super.initState();
    _session.reset();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _freeText.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _botSay(String text, {int delayMs = 500}) async {
    setState(() => _isTyping = true);
    _scrollToBottom();
    await Future.delayed(Duration(milliseconds: delayMs));
    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add(_ChatMessage(text, ChatRole.bot));
    });
    _scrollToBottom();
  }

  Future<void> _bootstrap() async {
    await _botSay(
      "Hi! I'm Ava 🌿 your screening assistant.\n\nI'll ask a few questions about your health and risk factors, then guide you to a body scan.",
      delayMs: 300,
    );
    await _botSay("First, what is your biological sex?");
  }

  void _pickSex(String value) {
    _session.sex = value == 'Male'
        ? 'male'
        : value == 'Female'
        ? 'female'
        : null;
    setState(() => _messages.add(_ChatMessage(value, ChatRole.user)));
    _scrollToBottom();

    if (value == 'Female') {
      _stage = _Stage.pregnancy;
      _botSay("Are you currently pregnant?");
    } else {
      _stage = _Stage.age;
      _botSay("What is your age range?");
    }
  }

  void _pickPregnancy(String value) {
    _session.pregnant = value == 'Yes';
    setState(() => _messages.add(_ChatMessage(value, ChatRole.user)));
    _scrollToBottom();
    _stage = _Stage.age;
    _botSay("What is your age range?");
  }

  void _pickAge(String label, int? ageValue) {
    _session.age = ageValue;
    setState(() => _messages.add(_ChatMessage(label, ChatRole.user)));
    _scrollToBottom();
    _stage = _Stage.symptoms;
    _botSay("Do you have any of these symptoms? Select all that apply.");
  }

  void _submitSymptoms() {
    final picked = _session.symptoms;
    setState(() {
      _messages.add(
        _ChatMessage(
          picked.isEmpty
              ? 'None of these'
              : picked.map((k) => _symptomLabels[k] ?? k).join(', '),
          ChatRole.user,
        ),
      );
    });
    _scrollToBottom();
    _stage = _Stage.riskFactors;
    _botSay("Do you have any of these risk factors? Select all that apply.");
  }

  void _submitRiskFactors() {
    final picked = _session.riskFactors;
    setState(() {
      _messages.add(
        _ChatMessage(
          picked.isEmpty
              ? 'None of these'
              : picked.map((k) => _riskLabels[k] ?? k).join(', '),
          ChatRole.user,
        ),
      );
    });
    _scrollToBottom();
    _stage = _Stage.complete;
    _botSay(
      "Thanks! I have enough to run your screening. 🌿\n\nTap Continue to capture your body scan.",
    );
  }

  Future<void> _handleFreeText() async {
    final text = _freeText.text.trim();
    if (text.isEmpty) return;

    _freeText.clear();
    setState(() {
      _messages.add(_ChatMessage(text, ChatRole.user));
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final reply = await ApiService.instance.chat(message: text, history: []);
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(reply.text, ChatRole.bot));
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(
          _ChatMessage("Sorry, I couldn't reach the server.", ChatRole.bot),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            '/dashboard',
            (route) => false,
          ),
        ),
        title: const Text('Screening Questionnaire'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return const ChatBubble(
                      message: '',
                      role: ChatRole.bot,
                      isTyping: true,
                    );
                  }
                  return ChatBubble(
                    message: _messages[index].text,
                    role: _messages[index].role,
                  );
                },
              ),
            ),
            if (!_isTyping) _buildInteractivePanel(),
            _buildTextInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractivePanel() {
    switch (_stage) {
      case _Stage.sex:
        return _chipRow([
          ('Male', () => _pickSex('Male')),
          ('Female', () => _pickSex('Female')),
          ('Prefer not to say', () => _pickSex('Prefer not to say')),
        ]);
      case _Stage.pregnancy:
        return _chipRow([
          ('Yes', () => _pickPregnancy('Yes')),
          ('No', () => _pickPregnancy('No')),
        ]);
      case _Stage.age:
        return _chipRow([
          ('Under 18', () => _pickAge('Under 18', 16)),
          ('18–30', () => _pickAge('18–30', 25)),
          ('31–50', () => _pickAge('31–50', 40)),
          ('51–65', () => _pickAge('51–65', 58)),
          ('65+', () => _pickAge('65+', 70)),
        ]);
      case _Stage.symptoms:
        return _MultiSelectPanel(
          title: 'Symptoms',
          options: _symptomLabels,
          selected: _session.symptoms,
          onToggle: (k) => setState(
            () => _session.symptoms.contains(k)
                ? _session.symptoms.remove(k)
                : _session.symptoms.add(k),
          ),
          onContinue: _submitSymptoms,
        );
      case _Stage.riskFactors:
        return _MultiSelectPanel(
          title: 'Risk factors',
          options: _riskLabels,
          selected: _session.riskFactors,
          onToggle: (k) => setState(
            () => _session.riskFactors.contains(k)
                ? _session.riskFactors.remove(k)
                : _session.riskFactors.add(k),
          ),
          onContinue: _submitRiskFactors,
        );
      case _Stage.complete:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: AppColors.border, width: 0.6),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/scan'),
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Continue to Body Scan'),
            ),
          ),
        );
    }
  }

  Widget _chipRow(List<(String, VoidCallback)> items) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((e) {
          return ActionChip(
            label: Text(e.$1),
            onPressed: e.$2,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border),
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _freeText,
              onSubmitted: (_) => _handleFreeText(),
              decoration: InputDecoration(
                hintText: 'Ask Ava anything...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: _isTyping ? null : _handleFreeText,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _MultiSelectPanel extends StatelessWidget {
  final String title;
  final Map<String, String> options;
  final Set<String> selected;
  final void Function(String key) onToggle;
  final VoidCallback onContinue;

  const _MultiSelectPanel({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  '${selected.length} selected',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shrinkWrap: true,
              children: options.entries.map((e) {
                return CheckboxListTile(
                  dense: true,
                  value: selected.contains(e.key),
                  onChanged: (_) => onToggle(e.key),
                  title: Text(e.value, style: const TextStyle(fontSize: 13)),
                  activeColor: AppColors.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
