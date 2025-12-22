import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';

import '../../screens/store/data/chip_data.dart';
import '../game/offline/ai_logic.dart';
import '../game/smart_deck/deck_manager.dart';
import '../../sounds/sound_manager.dart';
import '../../database/online_service.dart';
import '../account/data/avatar_data.dart';
import 'arranged_board.dart';

class GameBoard extends StatefulWidget {
  final String difficulty;
  final bool isOnline;
  const GameBoard({super.key, this.difficulty = "Easy", this.isOnline = false});

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> with TickerProviderStateMixin {
  // Game State
  // FIX: removed 'late' and assigned default to prevent crash if load is slow
  GameChip myChip = allGameChips[0];
  bool isLoading = true;
  String opponentName = "@Opponent";
  String opponentAvatarId = "avatar_1";
  String opponentFlag = "🏳️"; // Default Flag

  List<String> deck = [];
  final List<String> playerHand = [];
  final List<String> opponentHand = [];
  final List<int> boardState = List.filled(100, 0); // 0:Empty, 1:P1, 2:P2
  List<String> boardLayout = [];
  final Set<int> cornerIndices = {0, 9, 90, 99};

  // Win Logic
  bool isPlayerTurn = true;
  bool isGameOver = false;
  List<List<int>> winningSequences = [];

  // Interaction
  String? selectedCard;
  int? lastPlacedChipIndex;

  // Online
  OnlineService? _onlineService;
  int myPlayerValue = 1; // 1 = Me, 2 = Enemy

  // Searching UI State
  late AnimationController _textPulseController;
  Timer? _searchTimer;
  int _seconds = 0;
  int _statusIndex = 0;
  final List<String> _statusMessages = [
    "Connecting...",
    "Finding Opponent...",
    "Shuffling Deck...",
    "Starting Match..."
  ];
  late ConfettiController _confettiController;

  // --- NEW: TURN TIMER ---
  Timer? _turnTimer;
  int _turnTimeRemaining = 60;

  @override
  void initState() {
    super.initState();
    _loadMyChip();
    _loadManualBoard();

    _textPulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));

    if (widget.isOnline) {
      _startSearchAnimation();
      _startOnlineGame();
    } else {
      _startOfflineGame();
    }
  }

  @override
  void dispose() {
    _textPulseController.dispose();
    _confettiController.dispose();
    _searchTimer?.cancel();
    _turnTimer?.cancel(); // Kill game timer
    _onlineService?.leaveGame();
    super.dispose();
  }

  void _loadManualBoard() {
    setState(() {
      boardLayout = List.from(ArrangedBoard.layout);
    });
  }

  Future<void> _loadMyChip() async {
    final prefs = await SharedPreferences.getInstance();
    String chipId = prefs.getString('selected_chip_id') ?? "default_blue";
    if (mounted) {
      setState(() {
        myChip = allGameChips.firstWhere((c) => c.id == chipId, orElse: () => allGameChips[0]);
      });
    }
  }

  // --- TIMER LOGIC ---
  void _startTurnTimer() {
    _turnTimer?.cancel();
    setState(() => _turnTimeRemaining = 60);

    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_turnTimeRemaining > 0) {
          _turnTimeRemaining--;
        } else {
          _handleTimeout();
        }
      });
    });
  }

  void _handleTimeout() {
    _turnTimer?.cancel();
    if (isGameOver) return;

    // Timeout Logic: Who lost?
    // If it's my turn and I timed out -> I lose.
    // If it's enemy turn and they timed out -> They lose (I win).

    // Note: In a real server-authoritative game, the server decides this.
    // For this client-side logic, we just handle local state.

    bool iLost = isPlayerTurn;
    isGameOver = true;

    _showGameOverDialog(!iLost, isTimeout: true);
  }

  // --- ONLINE LOGIC ---
  Future<void> _startOnlineGame() async {
    _onlineService = OnlineService();
    _onlineService!.onGameStateChanged = (data) {
      if (!mounted) return;
      if (data['status'] == 'playing') {
        _stopSearchAnimation();

        String myRole = _onlineService!.myRole;
        int newPlayerValue = (myRole == 'host') ? 1 : 2;

        setState(() {
          isLoading = false;
          myPlayerValue = newPlayerValue;

          bool wasPlayerTurn = isPlayerTurn;
          isPlayerTurn = (data['turn'] == myRole);

          // Reset Timer on Turn Change
          if (wasPlayerTurn != isPlayerTurn) {
            _startTurnTimer();
          }

          if (myRole == 'host') {
            opponentAvatarId = data['guest_avatar'] ?? "avatar_1";
            opponentName = data['guest_name'] ?? "Guest";
            // opponentFlag = data['guest_flag'] ?? "🏳️"; // If you added flags to DB
          } else {
            opponentAvatarId = data['host_avatar'] ?? "avatar_1";
            opponentName = data['host_name'] ?? "Host";
            // opponentFlag = data['host_flag'] ?? "🏳️";
          }

          if (data['board'] != null) {
            List<dynamic> cloudBoard = data['board'];
            for(int i=0; i<100; i++) {
              if (cloudBoard[i] is int) boardState[i] = cloudBoard[i];
            }
          }
          if (data['last_move'] != null) lastPlacedChipIndex = data['last_move']['index'];

          checkForWin();
        });

        if (playerHand.isEmpty) {
          _dealInitialHands();
          _startTurnTimer(); // Start first timer
        }
      }
    };
    await _onlineService!.findMatch();
  }

  void _dealInitialHands() {
    deck = DeckManager.createFullDeck();
    deck.shuffle();
    for (int i = 0; i < 7; i++) {
      playerHand.add(deck.removeLast());
    }
  }

  void _startOfflineGame() {
    _dealInitialHands();
    setState(() {
      isLoading = false;
      isPlayerTurn = true;
      opponentName = "Offline AI";
      opponentFlag = "🤖";
    });
    _startTurnTimer();
  }

  // --- SEARCH UI ANIMATION ---
  void _startSearchAnimation() {
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _seconds++;
        if (_seconds % 3 == 0) _statusIndex = (_statusIndex + 1) % _statusMessages.length;
      });
    });
  }

  void _stopSearchAnimation() { _searchTimer?.cancel(); }

  void _cancelSearch() {
    _onlineService?.cancelSearch();
    Navigator.pop(context);
  }

  // --- GAMEPLAY LOGIC ---
  void _onBoardTap(int index) {
    if (!isPlayerTurn || isGameOver || selectedCard == null) return;
    if (cornerIndices.contains(index)) return;

    String targetCard = boardLayout[index];
    bool isTwoEyed = DeckManager.isTwoEyedJack(selectedCard!);
    bool isOneEyed = DeckManager.isOneEyedJack(selectedCard!);
    bool success = false;

    if (isTwoEyed) {
      if (boardState[index] == 0) success = true;
    } else if (isOneEyed) {
      if (boardState[index] != 0 && boardState[index] != myPlayerValue) {
        if (!_isChipLocked(index)) { _executeMove(index, 0); return; }
        else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot remove completed sequence!"))); return; }
      }
    } else {
      if (targetCard == selectedCard && boardState[index] == 0) success = true;
    }

    if (success) _executeMove(index, myPlayerValue);
  }

  void _executeMove(int index, int value) {
    HapticFeedback.lightImpact();

    if (widget.isOnline) {
      _onlineService?.sendMove(index, selectedCard!, value);
      setState(() {
        playerHand.remove(selectedCard);
        selectedCard = null;
        if (deck.isNotEmpty) playerHand.add(deck.removeLast());
        isPlayerTurn = false;
      });
      _startTurnTimer(); // Restart for opponent
    } else {
      setState(() {
        boardState[index] = value;
        lastPlacedChipIndex = value == 0 ? null : index;
        playerHand.remove(selectedCard);
        selectedCard = null;
        if (deck.isNotEmpty) playerHand.add(deck.removeLast());
      });
      _finishTurn(isPlayer: true);
    }
  }

  bool _isChipLocked(int index) {
    for (var seq in winningSequences) if (seq.contains(index)) return true;
    return false;
  }

  void _finishTurn({required bool isPlayer}) {
    checkForWin();
    if (isGameOver) return;

    if (isPlayer) {
      setState(() { isPlayerTurn = false; _startAiTurn(); });
    } else {
      setState(() { isPlayerTurn = true; });
    }
    _startTurnTimer(); // Restart timer for next turn
  }

  Future<void> _startAiTurn() async {
    // AI thinks for random time (1-3s)
    int thinkTime = 1000 + Random().nextInt(2000);
    await Future.delayed(Duration(milliseconds: thinkTime));
    if(!mounted) return;

    AiMove? move = AiLogic.findBestMove(
        ["AC", "KD", "2H", "5S", "JC", "JD", "9H"],
        boardState, boardLayout, widget.difficulty, 2
    );

    if (move != null) {
      setState(() {
        if (move.isRemoval) {
          boardState[move.index] = 0;
          lastPlacedChipIndex = null;
        } else {
          boardState[move.index] = 2;
          lastPlacedChipIndex = move.index;
        }
      });
    }
    _finishTurn(isPlayer: false);
  }

  void checkForWin() {
    winningSequences.clear();
    for (int i=0; i<100; i++) {
      if (i%10 <= 5) _checkLine(i, 1);
      if (i < 50) _checkLine(i, 10);
      if (i%10 <= 5 && i<50) _checkLine(i, 11);
      if (i%10 >= 4 && i<50) _checkLine(i, 9);
    }

    int p1Count = 0;
    int p2Count = 0;

    for (var seq in winningSequences) {
      int owner = 0;
      for (int idx in seq) {
        if (!cornerIndices.contains(idx)) {
          owner = boardState[idx];
          break;
        }
      }
      if (owner == 1) p1Count++;
      if (owner == 2) p2Count++;
    }

    if (p1Count >= 2 || p2Count >= 2) {
      isGameOver = true;
      _turnTimer?.cancel();
      bool iWon = (myPlayerValue == 1 && p1Count >= 2) || (myPlayerValue == 2 && p2Count >= 2);
      if (iWon) _confettiController.play();
      if (widget.isOnline) _onlineService?.recordGameEnd(won: iWon, opponentName: opponentName);
      _showGameOverDialog(iWon);
    }
  }

  void _checkLine(int start, int step) {
    List<int> currentSeq = [];
    int? seqOwner;
    for (int k=0; k<5; k++) {
      int idx = start + (k * step);
      int owner = boardState[idx];
      bool isCorner = cornerIndices.contains(idx);
      if (isCorner) { currentSeq.add(idx); continue; }
      if (owner == 0) return;
      if (seqOwner == null) { seqOwner = owner; } else if (owner != seqOwner) { return; }
      currentSeq.add(idx);
    }
    winningSequences.add(currentSeq);
  }

  void _showGameOverDialog(bool iWon, {bool isTimeout = false}) {
    String title = iWon ? "VICTORY!" : (isTimeout ? "TIME'S UP!" : "DEFEAT");
    String message = isTimeout
        ? (iWon ? "Opponent ran out of time!" : "You ran out of time!")
        : (iWon ? "You are the master of Lines!" : "Better luck next time.");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(title, style: TextStyle(color: iWon ? Colors.amber : Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iWon) ConfettiWidget(confettiController: _confettiController) else const Icon(Icons.timer_off, size: 40, color: Colors.white54),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("EXIT"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOnline && isLoading) return _buildSearchScreen();
    // AvatarItem opponentAvatar = getAvatarById(opponentAvatarId);

    return Scaffold(
      backgroundColor: const Color(0xFF151515),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildGameHeader(), // REPLACED TURN INDICATOR WITH HEADER
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 0.70,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 10,
                            childAspectRatio: 0.70,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                          ),
                          itemCount: 100,
                          itemBuilder: (context, index) => _buildBoardSquare(index),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 120), // More space for the fanned hand
              ],
            ),

            // --- FANNED HAND (CURVED DECK) ---
            Positioned(
              bottom: -30,
              left: 0,
              right: 0,
              height: 160,
              child: _buildFannedHand(),
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW HEADER: Player vs Opponent + Timer ---
  Widget _buildGameHeader() {
    AvatarItem opponentAvatar = getAvatarById(opponentAvatarId);
    bool isUrgent = _turnTimeRemaining <= 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Opponent Info
          Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(radius: 20, backgroundColor: opponentAvatar.color, child: Icon(opponentAvatar.icon, size: 20, color: Colors.white)),
                  if (widget.isOnline) Text(opponentFlag, style: const TextStyle(fontSize: 14)), // Small Flag
                ],
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(opponentName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(isPlayerTurn ? "Waiting..." : "Playing", style: TextStyle(color: isPlayerTurn ? Colors.grey : Colors.greenAccent, fontSize: 10)),
                ],
              ),
            ],
          ),

          // TIMER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isUrgent ? Colors.red.withOpacity(0.2) : Colors.black54,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: isUrgent ? Colors.red : Colors.white24),
            ),
            child: Row(
              children: [
                Icon(Icons.timer, size: 16, color: isUrgent ? Colors.red : Colors.white70),
                const SizedBox(width: 5),
                Text(
                    "$_turnTimeRemaining",
                    style: TextStyle(color: isUrgent ? Colors.red : Colors.white, fontWeight: FontWeight.bold)
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- NEW: FANNED HAND BUILDER ---
  Widget _buildFannedHand() {
    if (playerHand.isEmpty) return const SizedBox();

    double totalWidth = MediaQuery.of(context).size.width;
    double cardWidth = 60;
    double cardHeight = 90;
    int count = playerHand.length;

    int selectedIdx = -1;
    if (selectedCard != null) {
      selectedIdx = playerHand.indexOf(selectedCard!);
    }

    double centerX = totalWidth / 2;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: List.generate(count, (index) {
        String card = playerHand[index];
        bool isSelected = (index == selectedIdx);

        // Standard Fan Logic
        double relativeIndex = index - (count - 1) / 2;
        double angle = relativeIndex * 0.08;
        double xOffset = relativeIndex * 35; // Default spacing
        double yOffset = (relativeIndex * relativeIndex) * 2.0; // Arch

        // --- PART THE SEA LOGIC ---
        // Pushes cards away from the selected card
        if (selectedIdx != -1) {
          if (index < selectedIdx) {
            xOffset -= 40; // Push left group WAY left
          } else if (index > selectedIdx) {
            xOffset += 40; // Push right group WAY right
          }
        }

        // --- SELECTED CARD LOGIC ---
        if (isSelected) {
          yOffset = 0;   // Don't go up too high, just stay at base level
          angle = 0;     // Straighten up
          // xOffset stays relative to keep its place in the "hole" we made
        }

        return Positioned(
          left: centerX + xOffset - (cardWidth / 2),
          bottom: 50 - yOffset,
          child: Transform.rotate(
            angle: angle,
            child: GestureDetector(
              onTap: () {
                if(!isPlayerTurn) return;
                setState(() => selectedCard = card);
                HapticFeedback.selectionClick();
              },
              child: _buildRealCard(
                  card,
                  width: cardWidth,
                  height: cardHeight,
                  isSelected: isSelected,
                  suitSize: 24,
                  rankSize: 14
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildRealCard(String cardStr, {
    double width = 50,
    double height = 70,
    bool isSelected = false,
    double suitSize = 26,
    double rankSize = 14
  }) {
    if (cardStr == "CORNER") return const SizedBox();
    if (cardStr == "") return const SizedBox();

    bool isRed = cardStr.contains('H') || cardStr.contains('D');
    String suit = "";
    if (cardStr.contains('H')) suit = "♥";
    else if (cardStr.contains('D')) suit = "♦";
    else if (cardStr.contains('C')) suit = "♣";
    else if (cardStr.contains('S')) suit = "♠";

    String rank = cardStr.substring(0, cardStr.length - 1);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? Colors.amber : Colors.grey[400]!, width: isSelected ? 3 : 1),
        boxShadow: isSelected
            ? [const BoxShadow(color: Colors.amberAccent, blurRadius: 10, spreadRadius: 1)]
            : [const BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(2,2))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 2, top: 2,
            child: Column(
              children: [
                Text(rank, style: TextStyle(color: isRed ? Colors.red[800] : Colors.black, fontWeight: FontWeight.bold, fontSize: rankSize - 2)),
                Text(suit, style: TextStyle(color: isRed ? Colors.red[800] : Colors.black, fontSize: rankSize - 4)),
              ],
            ),
          ),
          Center(
            child: Text(suit, style: TextStyle(color: isRed ? Colors.red[800] : Colors.black, fontSize: suitSize)),
          ),
          Positioned(
            right: 2, bottom: 2,
            child: Transform.rotate(
              angle: pi,
              child: Column(
                children: [
                  Text(rank, style: TextStyle(color: isRed ? Colors.red[800] : Colors.black, fontWeight: FontWeight.bold, fontSize: rankSize - 2)),
                  Text(suit, style: TextStyle(color: isRed ? Colors.red[800] : Colors.black, fontSize: rankSize - 4)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBoardSquare(int index) {
    String cardStr = boardLayout[index];
    int owner = boardState[index];
    bool isCorner = cornerIndices.contains(index);

    // NO HIGHLIGHT LOGIC ANYMORE (Visual only)

    Color chipColor = Colors.transparent;
    // THIS IS THE FIX: USE CUSTOM CHIP DATA
    if (owner != 0) {
      if (owner == myPlayerValue) {
        // Use the loaded chip's color
        chipColor = myChip.color;
      } else {
        chipColor = Colors.red;
      }
    }

    return GestureDetector(
      onTap: () => _onBoardTap(index),
      child: Container(
        decoration: BoxDecoration(
          color: isCorner ? const Color(0xFF222222) : Colors.transparent,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (!isCorner) _buildRealCard(
                cardStr,
                width: 200,
                height: 300,
                isSelected: false,
                suitSize: 14,
                rankSize: 10
            ),

            if (isCorner) const Icon(Icons.stars, size: 24, color: Colors.amber),

            if (owner != 0)
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                    color: chipColor,
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black54, offset: Offset(1,1), blurRadius: 2)],
                    border: index == lastPlacedChipIndex ? Border.all(color: Colors.white, width: 2) : null
                ),
                // If the chip has an icon, use it. Otherwise, simple checkmark for last move.
                child: (owner == myPlayerValue && myChip.icon != Icons.circle)
                    ? Icon(myChip.icon, size: 16, color: Colors.white)
                    : (index == lastPlacedChipIndex ? const Center(child: Icon(Icons.check, size: 14, color: Colors.white)) : null),
              ),
            for (var seq in winningSequences)
              if (seq.contains(index))
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.greenAccent, width: 3)),
                )
          ],
        ),
      ),
    );
  }

  Widget _buildSearchScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(animation: _textPulseController, builder: (context, child) {
            return Container(
              width: 200, height: 200,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.cyanAccent.withOpacity(0.1 * _textPulseController.value)),
            );
          }),
          const Icon(Icons.public, color: Colors.white, size: 50),
          Positioned(
            bottom: 150,
            child: FadeTransition(
              opacity: Tween(begin: 0.6, end: 1.0).animate(_textPulseController),
              child: Column(
                children: [
                  Text(_statusMessages[_statusIndex], style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  Text("Time Elapsed: $_seconds s", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            child: TextButton(
              onPressed: _cancelSearch,
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.2),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: const BorderSide(color: Colors.redAccent)),
              ),
              child: const Text("CANCEL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}