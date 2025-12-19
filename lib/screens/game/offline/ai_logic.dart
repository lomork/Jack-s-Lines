import 'dart:math';

class AiLogic {
  // Returns a Map with 'card', 'index', and 'type' ('place' or 'remove')
  static Map<String, dynamic> getMove(
      String difficulty,
      List<String> aiHand,
      List<int> boardState, // 0=Empty, 1=Player, 2=AI
      List<String> boardLayout,
      List<int> cornerIndices,
      List<List<int>> lockedSequences, // NEW: Know which lines are dead
      ) {
    // 1. EASY: Random
    if (difficulty == "Easy") {
      return _getRandomMove(aiHand, boardState, boardLayout, cornerIndices);
    }

    // 2. MEDIUM: 60% Smart, 40% Random (Human-like mistakes)
    if (difficulty == "Medium") {
      if (Random().nextDouble() > 0.6) {
        return _getRandomMove(aiHand, boardState, boardLayout, cornerIndices);
      }
    }

    // 3. HARD: Calculate the Best Mathematical Move
    return _getBestMove(aiHand, boardState, boardLayout, cornerIndices, lockedSequences);
  }

  // --- SMART LOGIC ---
  static Map<String, dynamic> _getBestMove(
      List<String> hand,
      List<int> state,
      List<String> layout,
      List<int> corners,
      List<List<int>> locked,
      ) {
    Map<String, dynamic>? bestMove;
    int highestScore = -999999;

    // Iterate through every card in hand
    for (String card in hand) {
      bool isJack = card.startsWith("J");
      bool isTwoEyed = isJack && (card.contains("C") || card.contains("S")); // Wild
      bool isOneEyed = isJack && (card.contains("H") || card.contains("D")); // Remove

      // Check every spot on the board
      for (int i = 0; i < 100; i++) {
        if (corners.contains(i)) continue; // Never play on corners

        // --- OPTION A: PLAY A CHIP ---
        if (state[i] == 0) { // Empty Spot
          if (layout[i] == card || isTwoEyed) {
            // Simulate the move
            state[i] = 2; // AI places chip
            int score = _evaluateBoardState(i, 2, state, corners, locked);

            // Defensive Check: Did we block the player?
            state[i] = 1; // Pretend Player placed it
            int blockScore = _evaluateBoardState(i, 1, state, corners, locked);
            // If blocking prevents a win/sequence, add huge bonus
            if (blockScore >= 1000) score += (blockScore * 0.8).toInt();

            state[i] = 0; // Reset

            if (score > highestScore) {
              highestScore = score;
              bestMove = {'card': card, 'index': i, 'type': 'place'};
            }
          }
        }

        // --- OPTION B: REMOVE A CHIP (One-Eyed Jack) ---
        else if (state[i] == 1 && isOneEyed) {
          // Can only remove if NOT part of a locked sequence
          bool isLocked = false;
          for(var seq in locked) { if(seq.contains(i)) isLocked = true; }

          if (!isLocked) {
            state[i] = 0; // Remove player chip
            // Check how bad this hurts the player
            // We evaluate "Player Score" before and after.
            // Simplified: If removing this breaks a line of 4, it's worth a lot.

            // Temporarily put it back to check value
            state[i] = 1;
            int valueDestroyed = _evaluateBoardState(i, 1, state, corners, locked);
            state[i] = 1; // Keep it there for now (loop logic)

            // The score is the value of destruction
            int score = valueDestroyed + 50; // Base value for using a jack

            if (score > highestScore) {
              highestScore = score;
              bestMove = {'card': card, 'index': i, 'type': 'remove'};
            }
          }
        }
      }
    }

    // If no good move found, pick random
    return bestMove ?? _getRandomMove(hand, state, layout, corners);
  }

  // Calculate value of a move at 'index' for 'player'
  static int _evaluateBoardState(int index, int player, List<int> state, List<int> corners, List<List<int>> locked) {
    int score = 0;

    // Check 4 directions: Horizontal, Vertical, Diag 1, Diag 2
    List<int> directions = [1, 10, 11, 9];

    for (int step in directions) {
      int lineLength = _countLine(index, step, player, state, corners);

      // Scoring Weights
      if (lineLength >= 5) score += 10000; // SEQUENCE!
      else if (lineLength == 4) score += 1000; // Almost there
      else if (lineLength == 3) score += 200; // Building
      else if (lineLength == 2) score += 20; // Started
    }

    // Center Board Bonus (Indices 44, 45, 54, 55 are prime real estate)
    if ([44, 45, 54, 55].contains(index)) score += 15;

    return score;
  }

  static int _countLine(int index, int step, int player, List<int> state, List<int> corners) {
    int count = 1; // The chip itself
    // Look Forward
    int curr = index + step;
    while (curr < 100 && curr >= 0 && (state[curr] == player || corners.contains(curr))) {
      // Handle wrap-around logic for horizontal checks
      if (step == 1 && curr % 10 == 0) break; // Wrapped to next row
      count++;
      curr += step;
    }
    // Look Backward
    curr = index - step;
    while (curr < 100 && curr >= 0 && (state[curr] == player || corners.contains(curr))) {
      if (step == 1 && (curr + 1) % 10 == 0) break;
      count++;
      curr -= step;
    }
    return count;
  }

  static Map<String, dynamic> _getRandomMove(List<String> hand, List<int> state, List<String> layout, List<int> corners) {
    List<String> shuffled = List.from(hand)..shuffle();
    for (String card in shuffled) {
      bool isJack = card.startsWith("J");
      bool isWild = isJack && (card.contains("C") || card.contains("S"));
      for (int i = 0; i < 100; i++) {
        if (corners.contains(i)) continue;
        if (state[i] == 0 && (layout[i] == card || isWild)) {
          return {'card': card, 'index': i, 'type': 'place'};
        }
      }
    }
    return {};
  }
}