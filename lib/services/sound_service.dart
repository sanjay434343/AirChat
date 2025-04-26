import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static const String sendSound = 'sfx/send.mp3';
  static const String receiveSound = 'sfx/rec.mp3';

  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  
  SoundService._internal();

  final AudioPlayer _sendPlayer = AudioPlayer();
  final AudioPlayer _receivePlayer = AudioPlayer();
  bool _isMuted = false;
  bool _isInitialized = false;

  Future<void> _initAudio() async {
    if (_isInitialized) return;
    
    try {
      await _sendPlayer.setReleaseMode(ReleaseMode.stop);
      await _receivePlayer.setReleaseMode(ReleaseMode.stop);
      await _sendPlayer.setVolume(1.0);  // Full volume for clearer sound
      await _receivePlayer.setVolume(1.0);
      
      // Pre-load sounds with correct paths
      await Future.wait([
        _sendPlayer.setSource(AssetSource(sendSound)),
        _receivePlayer.setSource(AssetSource(receiveSound)),
      ]);
      
      _isInitialized = true;
    } catch (e) {
      print('Error initializing audio: $e');
    }
  }

  Future<void> playMessageSent() async {
    if (_isMuted) return;
    
    try {
      await _initAudio();
      await _sendPlayer.seek(Duration.zero);
      await _sendPlayer.resume();
    } catch (e) {
      print('Error playing send sound: $e');
    }
  }

  Future<void> playMessageReceived() async {
    if (_isMuted) return;
    
    try {
      await _initAudio();
      await _receivePlayer.seek(Duration.zero);
      await _receivePlayer.resume();
    } catch (e) {
      print('Error playing receive sound: $e');
    }
  }

  void setMuted(bool muted) {
    _isMuted = muted;
  }

  void dispose() {
    _sendPlayer.dispose();
    _receivePlayer.dispose();
  }
}
