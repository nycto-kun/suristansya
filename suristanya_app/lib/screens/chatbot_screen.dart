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

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _hasStartedScan = false;

  @override
  void initState() {
    super.initState();
    // Initial greeting from Ava
    _messages.add(_ChatMessage(
      "Hi! I'm Ava 🌿 your nutritional screening assistant.\n\nBefore we begin the image scan, are you experiencing any of these common symptoms: fatigue, pale skin, dizziness, or shortness of breath?",
      ChatRole.bot,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

  /// Extracts symptoms from user input and saves them to the session
  void _processSymptoms(String text) {
    final lower = text.toLowerCase();
    final session = ScreeningSession.instance;

    if (lower.contains('fatigue') || lower.contains('tired') || lower.contains('weak')) {
      session.symptoms.add('fatigue');
    }
    if (lower.contains('pale') || lower.contains('pallor')) {
      session.symptoms.add('paleness');
    }
    if (lower.contains('dizzy') || lower.contains('lightheaded') || lower.contains('faint')) {
      session.symptoms.add('dizziness');
    }
    if (lower.contains('breath') || lower.contains('breathing')) {
      session.symptoms.add('shortness_of_breath');
    }
    if (lower.contains('cold')) {
      session.symptoms.add('cold_hands_feet');
    }
    if (lower.contains('headache')) {
      session.symptoms.add('headaches');
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text, ChatRole.user));
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    // Save symptoms locally
    _processSymptoms(text);

    try {
      // Call the RAG AI backend
      final reply = await ApiService.instance.chat(message: text);
      
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(reply.text, ChatRole.bot));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          "I'm having trouble connecting right now. Please try again.",
          ChatRole.bot,
        ));
      });
      _scrollToBottom();
    }
  }

  void _handleQuickReply(String value) {
    if (value == 'Start Scan') {
      if (!_hasStartedScan) {
        setState(() => _hasStartedScan = true);
      }
      Navigator.pushNamed(context, '/scan');
      return;
    }
    _sendMessage(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          },
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accent, AppColors.accentDark],
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                'A',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ava',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Online',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            icon: const Icon(Icons.person_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Messages ─────────────────────────────────────
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
                  final msg = _messages[index];
                  return ChatBubble(message: msg.text, role: msg.role);
                },
              ),
            ),

            // ── Quick replies ────────────────────────────────
            if (!_isTyping)
              Container(
                height: 44,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildChip('Fatigue', isPrimary: false),
                    _buildChip('Pale skin', isPrimary: false),
                    _buildChip('Dizziness', isPrimary: false),
                    _buildChip('Shortness of breath', isPrimary: false),
                    _buildChip('None', isPrimary: false),
                    const SizedBox(width: 12),
                    _buildChip('Start Scan', isPrimary: true),
                  ],
                ),
              ),

            // ── Text input ───────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type your symptoms or questions...',
                        hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(_controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, {required bool isPrimary}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        onPressed: () => _handleQuickReply(label),
        backgroundColor: isPrimary ? AppColors.primary : Colors.white,
        side: BorderSide(
          color: isPrimary ? AppColors.primary : AppColors.border,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isPrimary ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ── Data Classes ────────────────────────────────────────────────
class _ChatMessage {
  final String text;
  final ChatRole role;
  _ChatMessage(this.text, this.role);
}