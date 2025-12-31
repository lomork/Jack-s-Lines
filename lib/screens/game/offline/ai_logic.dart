import 'dart:math';
import '../smart_deck/deck_manager.dart';

enum BotPersonality { aggressive, builder, balanced }

class AiMove {
  final int index;
  final bool isRemoval;
  final bool isDiscard;
  final String cardUsed;

  AiMove({
    required this.index,
    required this.cardUsed,
    this.isRemoval = false,
    this.isDiscard = false,
  });
}

class AiLogic {
  static AiMove? findBestMove(
    List<String> aiHand,
    List<int> boardState,
    List<String> boardLayout,
    String difficulty,
    int aiPlayerId,
      {BotPersonality personality = BotPersonality.balanced})
  {
    bool isHard = difficulty == "Hard";
    bool isMedium = difficulty == "Medium";

    List<AiMove> possibleMoves = [];
    Set<int> cornerIndices = {0, 9, 90, 99};

    for (String card in aiHand) {
      // JACK LOGIC: Check Suits for Jack types
      bool isJack = card.contains('J');
      bool isRedJack = card.contains('H') || card.contains('D');
      bool isBlackJack = card.contains('C') || card.contains('S');

      for (int i = 0; i < 100; i++) {
        if (cornerIndices.contains(i)) continue;
        int owner = boardState[i];

        // PLACING LOGIC
        if (owner == 0) {
          bool canPlace = false;
          if (isJack && isBlackJack) {
            canPlace = true; // Black Jack: Anywhere empty
          } else if (!isJack && boardLayout[i] == card) {
            canPlace = true; // Matching card
          }

          if (canPlace) {
            possibleMoves.add(
              AiMove(index: i, cardUsed: card, isRemoval: false),
            );
          }
        }
        // REMOVAL LOGIC
        else if (isJack && isRedJack && owner != 0 && owner != aiPlayerId) {
          // AI checks if this chip is part of a sequence before trying to remove
          // Note: GameBoard logic prevents sequence removal, but AI should be smart enough not to try.
          possibleMoves.add(AiMove(index: i, cardUsed: card, isRemoval: true));
        }
      }
    }

    if (possibleMoves.isEmpty) {
      // If no moves, check for a dead card to discard
      for (String card in aiHand) {
        if (card.contains('J')) continue;
        List<int> pos = [];
        for (int i = 0; i < 100; i++) if (boardLayout[i] == card) pos.add(i);

        if (pos.isNotEmpty && pos.every((idx) => boardState[idx] != 0)) {
          return AiMove(index: -1, cardUsed: card, isDiscard: true);
        }
      }
      return null;
    }

    AiMove? bestMove;
    double bestScore = -1000;

    for (var move in possibleMoves) {
      double score = 0;
      int oppId = (aiPlayerId == 1) ? 2 : 1;

      if (move.isRemoval) {
        // AGGRESSIVE bots love removing your chips
        score += (personality == BotPersonality.aggressive) ? 50 : 30;
        int oppNeighbors = _countNeighbors(move.index, boardState, oppId);
        score += (oppNeighbors * 20);
      } else {
        int neighbors = _countNeighbors(move.index, boardState, aiPlayerId);
        int oppNeighbors = _countNeighbors(move.index, boardState, oppId);

        if (personality == BotPersonality.builder) {
          score += (neighbors * 25);
          score += (oppNeighbors * 5); // Cares less about blocking
        }

        else if (personality == BotPersonality.aggressive) {
          score += (neighbors * 10);
          score += (oppNeighbors * 40);
        }

        // Wild card conservation
        if (move.cardUsed.contains('J')) {
          score -= 10; // Try to save Jacks unless they are very useful
        }
        else { // Balanced
          score += (neighbors * 15);
          score += (oppNeighbors * 20);
        }
      }

      // Randomness based on difficulty
      if (!isHard) {
        score += Random().nextInt(isMedium ? 10 : 30);
      }

      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
    }

    return bestMove;
  }

  static int _countNeighbors(int index, List<int> board, int playerId) {
    int count = 0;
    List<int> offsets = [-1, 1, -10, 10, -11, 11, -9, 9];
    for (int offset in offsets) {
      int neighbor = index + offset;
      if (neighbor >= 0 && neighbor < 100) {
        // Check grid boundary for horizontal
        if ((offset.abs() == 1 || offset.abs() == 11 || offset.abs() == 9)) {
          int row = index ~/ 10;
          int nRow = neighbor ~/ 10;
          if ((row - nRow).abs() > 1) continue;
        }
        if (board[neighbor] == playerId) count++;
      }
    }
    return count;
  }
}
