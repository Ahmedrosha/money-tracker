import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';

/// Listens to one spoken sentence and returns it (null = cancelled).
Future<String?> showVoiceSheet(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _VoiceSheet(),
    );

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _stt = SpeechToText();
  String _lang = 'en';
  String _text = '';
  String? _error;
  bool _listening = false;
  bool _ready = false;
  List<LocaleName> _locales = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final state = AppScope.read(context);
    _lang = await state.db.getSetting('voice_lang') ?? (isArabic ? 'ar' : 'en');
    try {
      _ready = await _stt.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') setState(() => _listening = false);
        },
        onError: (SpeechRecognitionError e) {
          if (mounted) setState(() {
            _listening = false;
            if (_text.isEmpty) _error = tr('Didn\'t catch that. Tap the microphone and try again.');
          });
        },
      );
      if (_ready) _locales = await _stt.locales();
    } catch (_) {
      _ready = false;
    }
    if (!mounted) return;
    if (!_ready) {
      setState(() => _error = tr('Speech recognition isn\'t available. Allow the microphone and speech recognition for the app in the phone settings.'));
      return;
    }
    setState(() {});
    _listen();
  }

  String? _localeId() {
    String norm(String s) => s.replaceAll('-', '_').toLowerCase();
    final want = _lang == 'ar' ? ['ar_eg', 'ar_sa', 'ar'] : ['en_us', 'en_gb', 'en'];
    for (final w in want) {
      for (final l in _locales) {
        final id = norm(l.localeId);
        if (id == w || (w.length == 2 && id.startsWith('${w}_'))) return l.localeId;
      }
    }
    return null;
  }

  Future<void> _listen() async {
    if (!_ready) return;
    setState(() {
      _error = null;
      _text = '';
      _listening = true;
    });
    await _stt.listen(
      localeId: _localeId(),
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() => _text = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          Navigator.pop(context, r.recognizedWords);
        }
      },
    );
  }

  Future<void> _setLang(String l) async {
    await _stt.stop();
    _lang = l;
    await AppScope.read(context).db.setSetting('voice_lang', l);
    _listen();
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'ar', label: Text('عربي')),
              ],
              selected: {_lang},
              onSelectionChanged: (s) => _setLang(s.first),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _listening ? _stt.stop() : _listen(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: _listening ? 96 : 84,
                height: _listening ? 96 : 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
                child: Icon(_listening ? Icons.mic : Icons.mic_none,
                    color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _error ??
                  (_text.isNotEmpty
                      ? _text
                      : (_listening
                          ? tr('Listening… e.g. "Spent 450 on fuel with the CIB card"')
                          : tr('Tap the microphone to speak'))),
              textAlign: TextAlign.center,
              style: _text.isNotEmpty
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: _error != null ? theme.colorScheme.error : null),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Cancel')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _text.trim().isEmpty ? null : () => Navigator.pop(context, _text),
                  child: Text(tr('Use')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
