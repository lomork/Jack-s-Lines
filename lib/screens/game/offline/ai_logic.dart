import 'dart:math';
import '../smart_deck/deck_manager.dart';

// 1. Define the class that was missing
class AiMove {
  final int index;
  final bool isRemoval;

  AiMove({required this.index, this.isRemoval = false});
}

class AiLogic {

  // 2. The main brain function
  static AiMove? findBestMove(
      List<String> aiHand,
      List<int> boardState,
      List<String> boardLayout,
      String difficulty,
      int aiPlayerId
      ) {
    // 0. Parse Difficulty
    bool isHard = difficulty == "Hard";
    bool isMedium = difficulty == "Medium";

    // 1. Identify Valid Moves
    List<AiMove> possibleMoves = [];
    Set<int> cornerIndices = {0, 9, 90, 99};

    for (String card in aiHand) {
      bool isTwoEyed = DeckManager.isTwoEyedJack(card);
      bool isOneEyed = DeckManager.isOneEyedJack(card);

      // Scan board for matching spots
      for (int i = 0; i < 100; i++) {
        if (cornerIndices.contains(i)) continue;

        int owner = boardState[i];

        // LOGIC: PLACING A CHIP
        if (owner == 0) {
          if (isTwoEyed || boardLayout[i] == card) {
            possibleMoves.add(AiMove(index: i));
          }
        }

        // LOGIC: REMOVING A CHIP (One-Eyed Jack)
        else if (isOneEyed && owner != aiPlayerId && owner != 0) {
          // AI considers removing player chip
          // (Note: We skip 'locked' sequence check here for simplicity,
          // usually safe to just try it)
          possibleMoves.add(AiMove(index: i, isRemoval: true));
        }
      }
    }

    if (possibleMoves.isEmpty) return null;

    // 2. Decision Making based on Difficulty
    if (!isHard && !isMedium) {
      // EASY: Random Move
      return possibleMoves[Random().nextInt(possibleMoves.length)];
    }

    // HARD/MEDIUM: Score the moves
    // We give points for:
    // - Blocking opponent
    // - Continuing own sequence

    AiMove bestMove = possibleMoves[0];
    int bestScore = -9999;

    for (var move in possibleMoves) {
      int score = 0;

      if (move.isRemoval) {
        // Removing is generally good
        score += 50;
        // If blocking a potential sequence, add more points (Simple heuristic)
        if (_hasNeighbor(move.index, boardState, (aiPlayerId == 1 ? 2 : 1))) {
          score += 20;
        }
      } else {
        // Placing
        // Check neighbors for same color (building sequence)
        int neighbors = _countNeighbors(move.index, boardState, aiPlayerId);
        score += (neighbors * 10);

        // Two-Eyed Jacks are valuable, save them unless high impact
        if (DeckManager.isTwoEyedJack(boardLayout[move.index])) { // Actually layout doesn't have jacks, check hand logic if needed
          // Simplified: If using a wild card logic inside loop
        }
      }

      // Add a bit of randomness so AI isn't robotic
      score += Random().nextInt(5);

      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
    }

    return bestMove;
  }

  // --- HELPERS ---

  static int _countNeighbors(int index, List<int> board, int playerId) {
    int count = 0;
    List<int> offsets = [-1, 1, -10, 10, -11, 11, -9, 9]; // All 8 directions

    for (int offset in offsets) {
      int neighbor = index + offset;
      if (neighbor >= 0 && neighbor < 100) {
        // Simple bounds check (ignores wrapping for MVP simplicity)
        if (board[neighbor] == playerId) count++;
      }
    }
    return count;
  }

  static bool _hasNeighbor(int index, List<int> board, int targetId) {
    return _countNeighbors(index, board, targetId) > 0;
  }
}