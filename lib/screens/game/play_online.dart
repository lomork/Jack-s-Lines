import '../../database/online_service.dart';
import 'play_mode_handler.dart';

class PlayOnlineHandler implements PlayModeHandler {
  final OnlineService service;
  final Function(int, String) onExternalMove;

  PlayOnlineHandler(this.service, this.onExternalMove);

  @override
  void onMoveMade(int index, String card, int playerValue) {
    service.sendMove(index, card, playerValue);
    PlayModeHandler.triggerVibration();
  }

  @override
  void onCardBurned(String card) {
    service.sendBurnAction(card);
    PlayModeHandler.triggerVibration();
  }

  @override
  void onGameEnd(bool won, String opponentName) {
    service.recordGameEnd(won: won, opponentName: opponentName);
  }

  @override
  void dispose() {
    service.leaveGame();
  }
}