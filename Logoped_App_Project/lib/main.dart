import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const LogopedProApp());
}

class ExerciseItem {
  String text;
  String? audioPath;
  ExerciseItem({required this.text, this.audioPath});
}

class LogopedProApp extends StatelessWidget {
  const LogopedProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Логопед Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0284C7)),
        useMaterial3: true,
      ),
      home: const MainExerciseScreen(),
    );
  }
}

class MainExerciseScreen extends StatefulWidget {
  const MainExerciseScreen({super.key});

  @override
  State<MainExerciseScreen> createState() => _MainExerciseScreenState();
}

class _MainExerciseScreenState extends State<MainExerciseScreen> {
  final List<ExerciseItem> _exercises = [
    ExerciseItem(text: 'Трактор'),
    ExerciseItem(text: 'Червена шапка'),
    ExerciseItem(text: 'Слънчево зайче'),
  ];
  int _currentIndex = 0;

  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  bool _isTherapistRecording = false;

  late final stt.SpeechToText _speechToText;
  bool _isSpeechInitialized = false;
  bool _isChildListening = false;
  String _childSpokenText = '';

  int _similarityScore = 0;
  String _pedagogicalAdvice = 'Чуй внимателно как логопедът произнася думата.';
  String _syllableFeedback = '';

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    _speechToText = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _isSpeechInitialized = await _speechToText.initialize(
      onError: (_) => setState(() => _isChildListening = false),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isChildListening = false);
        }
      },
    );
    setState(() {});
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleTherapistRecording() async {
    if (!_isTherapistRecording) {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/ref_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        setState(() {
          _isTherapistRecording = true;
          _exercises[_currentIndex].audioPath = path;
        });
      }
    } else {
      final savedPath = await _audioRecorder.stop();
      setState(() {
        _isTherapistRecording = false;
        _exercises[_currentIndex].audioPath = savedPath;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Еталонният запис е запазен!')),
      );
    }
  }

  Future<void> _playReferenceAudio() async {
    final path = _exercises[_currentIndex].audioPath;
    if (path != null && File(path).existsSync()) {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Първо запишете гласа на логопеда!')),
      );
    }
  }

  Future<void> _toggleChildListening() async {
    if (!_isSpeechInitialized) await _initSpeech();

    if (!_isChildListening) {
      setState(() {
        _isChildListening = true;
        _childSpokenText = '';
      });

      await _speechToText.listen(
        localeId: 'bg_BG',
        onResult: (result) {
          setState(() {
            _childSpokenText = result.recognizedWords;
            if (result.finalResult) {
              _evaluateSpeech(_childSpokenText, _exercises[_currentIndex].text);
            }
          });
        },
      );
    } else {
      await _speechToText.stop();
      setState(() => _isChildListening = false);
    }
  }

  void _evaluateSpeech(String spoken, String target) {
    if (spoken.isEmpty) return;

    double similarity = _calculateSimilarity(spoken, target);
    int score = (similarity * 100).round();

    List<String> targetSyllables = _splitBulgarianSyllables(target);
    List<String> spokenSyllables = _splitBulgarianSyllables(spoken);

    String syllableAdvice = '';
    if (targetSyllables.length > 1) {
      syllableAdvice = 'Срички: [ ${targetSyllables.join(" - ")} ]';
      if (spokenSyllables.length < targetSyllables.length) {
        syllableAdvice += '\n👉 Внимавай: Пропусна сричка! Кажи думата на части.';
      }
    }

    String soundAdvice = _getArticulationTips(spoken, target);

    String mainFeedback = '';
    if (score >= 85) {
      mainFeedback = '🌟 Браво, шампион! Каза го кристално чисто и точно!';
    } else if (score >= 50) {
      mainFeedback = '👍 Много добър опит! $soundAdvice';
    } else {
      mainFeedback = '💪 Опитай пак бавно! $soundAdvice';
    }

    setState(() {
      _similarityScore = score;
      _pedagogicalAdvice = mainFeedback;
      _syllableFeedback = syllableAdvice;
    });
  }

  String _getArticulationTips(String spoken, String target) {
    target = target.toLowerCase();
    spoken = spoken.toLowerCase();

    if (target.contains('р') && !spoken.contains('р')) {
      return 'Натърти на звука "Р"! Сложи върха на езика горе зад зъбките и накарай езичето да вибрира като моторче.';
    }
    if ((target.contains('с') || target.contains('з')) && (!spoken.contains('с') && !spoken.contains('з'))) {
      return 'Внимавай със звука "С/З"! Събери зъбките и пусни студена въздушна струя през средата.';
    }
    if ((target.contains('ш') || target.contains('ж')) && (!spoken.contains('ш') && !spoken.contains('ж'))) {
      return 'Внимавай с "Ш/Ж"! Оформи устните като фунийка напред и пусни топла струя.';
    }
    if (target.contains('л') && !spoken.contains('л')) {
      return 'Натърти на "Л"! Опри широк език горе на небцето.';
    }
    return 'Чуй записа на логопеда още веднъж и повтори бавно всяка сричка.';
  }

  List<String> _splitBulgarianSyllables(String word) {
    const vowels = 'аъоуеиюяАЪОУЕИЮЯ';
    List<String> syllables = [];
    String current = '';

    for (int i = 0; i < word.length; i++) {
      current += word[i];
      if (vowels.contains(word[i])) {
        if (i + 2 < word.length && !vowels.contains(word[i + 1]) && vowels.contains(word[i + 2])) {
          syllables.add(current);
          current = '';
        }
      }
    }
    if (current.isNotEmpty) {
      if (syllables.isNotEmpty && !syllables.last.contains(RegExp(r'[аъоуеиюяАЪОУЕИЮЯ]'))) {
        syllables[syllables.length - 1] += current;
      } else {
        syllables.add(current);
      }
    }
    return syllables.isEmpty ? [word] : syllables;
  }

  double _calculateSimilarity(String s1, String s2) {
    s1 = s1.toLowerCase().trim();
    s2 = s2.toLowerCase().trim();
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    int distance = _levenshtein(s1, s2);
    int maxLen = s1.length > s2.length ? s1.length : s2.length;
    return (maxLen - distance) / maxLen;
  }

  int _levenshtein(String s, String t) {
    List<List<int>> d = List.generate(s.length + 1, (i) => List.filled(t.length + 1, 0));
    for (int i = 0; i <= s.length; i++) d[i][0] = i;
    for (int j = 0; j <= t.length; j++) d[0][j] = j;

    for (int i = 1; i <= s.length; i++) {
      for (int j = 1; j <= t.length; j++) {
        int cost = s[i - 1] == t[j - 1] ? 0 : 1;
        d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].reduce((a, b) => a < b ? a : b);
      }
    }
    return d[s.length][t.length];
  }

  @override
  Widget build(BuildContext context) {
    final currentTask = _exercises[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F9FF),
      appBar: AppBar(
        title: const Text('🗣️ AI Логопед Pro', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: _currentIndex > 0 ? () => setState(() => _currentIndex--) : null,
                    ),
                    Expanded(
                      child: Text(
                        'Задача ${_currentIndex + 1} от ${_exercises.length}:\n"${currentTask.text}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios),
                      onPressed: _currentIndex < _exercises.length - 1 ? () => setState(() => _currentIndex++) : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('👩‍⚕️ Панел на Логопеда', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isTherapistRecording ? Colors.red : const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                            ),
                            icon: Icon(_isTherapistRecording ? Icons.stop : Icons.mic),
                            label: Text(_isTherapistRecording ? 'Спри запис' : 'Запиши глас'),
                            onPressed: _toggleTherapistRecording,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D9488),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.volume_up),
                            label: const Text('Чуй еталон'),
                            onPressed: currentTask.audioPath != null ? _playReferenceAudio : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 4,
              color: const Color(0xFFFFF1F2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFFDA4AF), width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Text('🧒 Ред е на детето', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF9F1239))),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isChildListening ? Colors.red.shade700 : const Color(0xFFE11D48),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: Icon(_isChildListening ? Icons.hearing : Icons.mic),
                        label: Text(_isChildListening ? 'Слушам... Кажи я!' : 'Повтори думата', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        onPressed: _toggleChildListening,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Точност: $_similarityScore%',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _similarityScore >= 80 ? Colors.green : (_similarityScore >= 50 ? Colors.orange : Colors.red),
                                ),
                              ),
                              if (_childSpokenText.isNotEmpty)
                                Text('Чуто: "$_childSpokenText"', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(),
                          if (_syllableFeedback.isNotEmpty) ...[
                            Text(_syllableFeedback, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0369A1))),
                            const SizedBox(height: 6),
                          ],
                          Text(_pedagogicalAdvice, style: const TextStyle(fontSize: 15, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}