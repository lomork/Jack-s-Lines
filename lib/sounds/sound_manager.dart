import 'package:audioplayers/audioplayers.dart';

class SoundManager {
  static final AudioPlayer _player = AudioPlayer();

  // Play a quick sound effect
  static Future<void> play(String fileName) async {
    // We use stop() to cut off previous sounds if spamming clicks
    await _player.stop();
    await _player.play(AssetSource('audio/$fileName'));
  }

  static void click() => play('click.mp3');
  static void place() => play('place.mp3');
  static void win() => play('win.mp3');
  static void error() => play('error.mp3');
}