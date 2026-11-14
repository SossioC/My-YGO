import 'package:audioplayers/audioplayers.dart';

import 'debug_log.dart';

class Sounds {
  final AudioPlayer _ok = AudioPlayer();
  final AudioPlayer _ko = AudioPlayer();

  Future<void> playOk() async {
    try {
      await _ok.stop();
      await _ok.play(AssetSource('sounds/ok.wav'));
    } catch (e) {
      DebugLog.add('Audio: $e');
    }
  }

  Future<void> playError() async {
    try {
      await _ko.stop();
      await _ko.play(AssetSource('sounds/error.wav'));
    } catch (e) {
      DebugLog.add('Audio: $e');
    }
  }

  void dispose() {
    _ok.dispose();
    _ko.dispose();
  }
}
