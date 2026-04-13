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
  static final List<List<int>> _allLines = _generateAllLines();

  static List<List<int>> _generateAllLines() {
    List<List<int>> lines = [];
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        if (c <= 5) lines.add([for (int i = 0; i < 5; i++) r * 10 + c + i]); // Horizontal
        if (r <= 5) lines.add([for (int i = 0; i < 5; i++) (r + i) * 10 + c]); // Vertical
        if (r <= 5 && c <= 5) lines.add([for (int i = 0; i < 5; i++) (r + i) * 10 + c + i]); // Diagonal 1
        if (r >= 4 && c <= 5) lines.add([for (int i = 0; i < 5; i++) (r - i) * 10 + c + i]); // Diagonal 2
      }
    }
    return lines;
  }

  static AiMove? findBestMove(
    List<String> aiHand,
    List<int> boardState,
    List<String> boardLayout,
    String difficulty,
    int aiPlayerId,
    [Set<int>? lockedIndices,
      BotPersonality personality = BotPersonality.balanced])
  {
    //bool isHard = difficulty == "Hard";
    bool isMedium = difficulty == "Medium";

    List<AiMove> possibleMoves = [];
    Set<int> cornerIndices = {0, 9, 90, 99};
    int oppId = (aiPlayerId == 1) ? 2 : 1;

    for (String card in aiHand) {
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
        else if (isJack && isRedJack && owner != 0 && owner != aiPlayerId) {
          if (lockedIndices != null && lockedIndices.contains(i)) {
            continue;
          }
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

    if (difficulty == "Easy") {
      return possibleMoves[Random().nextInt(possibleMoves.length)];
    }

    AiMove? bestMove;
    double bestScore = -double.infinity;
    bool isHard = difficulty == "Hard";

    for (var move in possibleMoves) {
      double score = _evaluateMove(move, boardState, aiPlayerId, oppId, isHard);


      if (!isHard) {
        score += Random().nextInt(1500) - 750;
      }

      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
    }

    return bestMove;
  }

  static double _evaluateMove(AiMove move, List<int> boardState, int aiId, int oppId, bool isHard) {
    double score = 0;
    Set<int> corners = {0, 9, 90, 99};

    for (var line in _allLines) {
      if (!line.contains(move.index)) continue; // Only score lines this move actually affects

      int actualAi = 0;
      int actualOpp = 0;
      int cornersInLine = 0;

      for (int idx in line) {
        if (corners.contains(idx)) cornersInLine++;
        else if (boardState[idx] == aiId) actualAi++;
        else if (boardState[idx] == oppId) actualOpp++;
      }

      int totalAi = actualAi + cornersInLine;
      int totalOpp = actualOpp + cornersInLine;
      bool aiCanUse = actualOpp == 0;
      bool oppCanUse = actualAi == 0;

      if (!move.isRemoval) {
        // --- PLACING A CHIP ---
        if (oppCanUse) {
          if (totalOpp == 4) score += 20000; // CRITICAL: Block opponent win
          else if (totalOpp == 3) score += 1000;
          else if (totalOpp == 2) score += 100;
        }
        if (aiCanUse) {
          if (totalAi == 4) score += 25000; // CRITICAL: Take the win (overrides block)
          else if (totalAi == 3) score += 1200;
          else if (totalAi == 2) score += 120;
          else if (totalAi == 1) score += 10;
        }
      } else {
        // --- REMOVING A CHIP (Red Jack) ---
        if (oppCanUse) {
          if (totalOpp == 4) score += 15000; // CRITICAL: Break their winning line
          else if (totalOpp == 3) score += 800;
          else if (totalOpp == 2) score += 80;
        }
        // If removing the opponent's chip unblocks the AI's own potential sequence
        if (actualOpp == 1 && actualAi > 0) {
          if (totalAi == 4) score += 5000;
          else if (totalAi == 3) score += 500;
        }
      }
    }

    // --- JACK CONSERVATION PENALTIES ---
    // The AI must pay a "tax" to use a Jack. This stops it from using them on useless plays.
    if (move.cardUsed.contains('J')) {
      if (isHard) {
        score -= 9000; // Hard AI will ONLY use a Jack to secure a win or block a 4-in-a-row
      } else {
        score -= 2000; // Medium AI is more trigger-happy and might waste them on 3-in-a-rows
      }
    }

    // Center board preference (helps build intersecting lines)
    if (!move.isRemoval) {
      int r = move.index ~/ 10;
      int c = move.index % 10;
      if (r >= 3 && r <= 6 && c >= 3 && c <= 6) {
        score += 20;
      }
    }

    return score;
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
