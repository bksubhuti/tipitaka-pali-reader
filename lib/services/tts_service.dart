import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  FlutterTts? _flutterTts;
  
  bool _isPlaying = false;
  bool _isPaused = false;
  bool _isStopped = true;
  
  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  bool get isStopped => _isStopped;
  
  // Callback when a chunk/page finishes reading
  VoidCallback? onCompletion;

  TtsService() {
    _initTts();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    
    _flutterTts?.setStartHandler(() {
      _isPlaying = true;
      _isPaused = false;
      _isStopped = false;
      notifyListeners();
    });

    _flutterTts?.setCompletionHandler(() {
      _isPlaying = false;
      _isPaused = false;
      _isStopped = true;
      notifyListeners();
      onCompletion?.call();
    });

    _flutterTts?.setCancelHandler(() {
      _isPlaying = false;
      _isPaused = false;
      _isStopped = true;
      notifyListeners();
    });

    _flutterTts?.setPauseHandler(() {
      _isPlaying = false;
      _isPaused = true;
      _isStopped = false;
      notifyListeners();
    });

    _flutterTts?.setContinueHandler(() {
      _isPlaying = true;
      _isPaused = false;
      _isStopped = false;
      notifyListeners();
    });

    _flutterTts?.setErrorHandler((msg) {
      _isPlaying = false;
      _isPaused = false;
      _isStopped = true;
      debugPrint("TTS error: $msg");
      notifyListeners();
    });

    // Default configuration
    _flutterTts?.setLanguage("en-US");
    _flutterTts?.setSpeechRate(0.5);
    _flutterTts?.setVolume(1.0);
    _flutterTts?.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) {
      onCompletion?.call();
      return;
    }
    
    await _flutterTts?.speak(text);
  }

  Future<void> pause() async {
    await _flutterTts?.pause();
  }

  Future<void> stop() async {
    await _flutterTts?.stop();
  }
  
  @override
  void dispose() {
    _flutterTts?.stop();
    super.dispose();
  }
}
