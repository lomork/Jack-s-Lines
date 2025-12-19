import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../../screens/store/data/chip_data.dart';
import '../game/offline/ai_logic.dart';
import '../game/smart_deck/deck_manager.dart';
import '../../sounds/sound_manager.dart';
import '../../database/online_service.dart';


class GameBoard extends StatefulWidget {
  final String difficulty;
  final bool isOnline;
  const GameBoard({super.key, this.difficulty = "Easy", this.isOnline = false});

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> with TickerProviderStateMixin {
  late GameChip myChip;
  bool isLoading = true;
  String opponentName = "@Opponent";

  // Game State
  List<String> deck = [];
  final List<String> playerHand = [];
  final List<String> opponentHand = [];
  final List<int> boardState = List.filled(100, 0);
  List<String> boardLayout = [];

  // Win Logic
  int playerScore = 0;
  int aiScore = 0;
  List<List<int>> lockedSequences = [];

  bool isGameOver = false;
  bool isPlayerTurn = true;

  String? selectedCard;
  String? lastPlayedCard;
  String? lastAiPlayedCard;
  int? lastPlacedChipIndex;

  final List<int> cornerIndices = [0, 9, 90, 99];
  Timer? _turnTimer;
  int _secondsRemaining = 60;
  String aiStatus = "Waiting...";

  //database
  OnlineService? _onlineService;

  @override
  void initState() {
    super.initState();
    _generateRandomBoard();
    if (widget.isOnline) {
      _startOnlineGame();
    } else {
      _initializeGame(); // Normal offline start
    }
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeGame() async {
    final prefs = await SharedPreferences.getInstance();
    String chipId = prefs.getString('selected_chip_id') ?? "default_blue";
    myChip = allGameChips.firstWhere((c) => c.id == chipId, orElse: () => allGameChips[0]);

    // Board is already generated in initState
    deck = DeckManager.buildDeck();
    _dealInitialHands();

    if (mounted) {
      setState(() => isLoading = false); // Show Board
      _startTimer();
    }
  }

  Future<void> _cancelOnlineSearch() async {
    await _onlineService?.cancelSearch();
    if(mounted) Navigator.pop(context); // Go back to menu
  }

  Future<void> _startOnlineGame() async {
    final prefs = await SharedPreferences.getInstance();
    String chipId = prefs.getString('selected_chip_id') ?? "default_blue";
    myChip = allGameChips.firstWhere((c) => c.id == chipId, orElse: () => allGameChips[0]);

    deck = DeckManager.buildDeck();

    _onlineService = OnlineService();
    _onlineService!.onGameStateChanged = (data) {
      if (!mounted) return;

      // 1. Update Board
      if (data['board'] != null) {
        List<dynamic> cloudBoard = data['board'];
        for(int i=0; i<100; i++) boardState[i] = cloudBoard[i];
      }

      // 2. Check Turn
      String turn = data['turn'];
      String myRole = _onlineService!.myRole;
      bool isMyTurn = (turn == myRole);

      // 3. Game Started?
      if (data['status'] == 'playing') {
        setState(() {
          isLoading = false; // Match Found! Show Board.
          isPlayerTurn = isMyTurn;
          opponentName = (myRole == 'host') ? (data['guest_name'] ?? "Guest") : data['host_name'];

          if (isMyTurn && _secondsRemaining == 60) {
            _startTimer();
          }
        });
      }
    };

    // Start Searching (This might take time)
    await _onlineService!.findMatch();
  }

  void _generateRandomBoard() {
    List<String> boardCards = [];
    List<String> suits = ["S", "C", "H", "D"];
    List<String> boardRanks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "Q", "K", "A"];
    for (int i = 0; i < 2; i++) {
      for (var s in suits) { for (var r in boardRanks) { boardCards.add("$r$s"); } }
    }
    boardCards.shuffle();
    boardLayout = List.filled(100, "");
    int cardIndex = 0;
    for (int i = 0; i < 100; i++) {
      if (cornerIndices.contains(i)) boardLayout[i] = "FREE";
      else { boardLayout[i] = boardCards[cardIndex]; cardIndex++; }
    }
  }

  void _dealInitialHands() {
    playerHand.clear();
    opponentHand.clear();
    for (int i = 0; i < 7; i++) {
      playerHand.add(deck.removeLast());
      opponentHand.add(deck.removeLast());
    }
  }

  void _startTimer() {
    _turnTimer?.cancel();
    if (isGameOver) return;
    setState(() => _secondsRemaining = 60);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) _secondsRemaining--;
        else {
          _turnTimer?.cancel();
          if (isPlayerTurn) _triggerDisqualification();
        }
      });
    });
  }

  void _triggerDisqualification() {
    setState(() => isGameOver = true);
    _showEndGameDialog("TIME'S UP!", "You ran out of time.", false);
  }

  // --- PLAYER MOVE ---
  void _onCardTap(String card) {
    if (!isPlayerTurn || isGameOver) return;
    HapticFeedback.selectionClick();
    SoundManager.click(); // <--- NEW SOUND
    setState(() => selectedCard = (selectedCard == card) ? null : card);
  }

  void _onBoardTap(int index) {
    if (!isPlayerTurn || isGameOver || selectedCard == null) return;
    if (cornerIndices.contains(index)) return;

    bool isJack = selectedCard!.startsWith("J");
    bool isRedJack = isJack && (selectedCard!.contains("H") || selectedCard!.contains("D"));
    bool isBlackJack = isJack && (selectedCard!.contains("C") || selectedCard!.contains("S"));

    String targetCard = boardLayout[index];
    bool moveSuccessful = false;

    if (!isJack) {
      if (targetCard == selectedCard && boardState[index] == 0) {
        setState(() { boardState[index] = 1; lastPlacedChipIndex = index; });
        moveSuccessful = true;
      }
    } else if (isBlackJack) {
      if (boardState[index] == 0) {
        setState(() { boardState[index] = 1; lastPlacedChipIndex = index; });
        moveSuccessful = true;
      }
    } else if (isRedJack) {
      if (boardState[index] == 2) {
        if (_isChipLocked(index)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot remove a completed sequence!")));
          return;
        }
        setState(() { boardState[index] = 0; lastPlacedChipIndex = null; });
        moveSuccessful = true;
        HapticFeedback.heavyImpact();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Red Jacks remove OPPONENT chips!")));
      }
    }

    if (moveSuccessful) {
      HapticFeedback.lightImpact();
      SoundManager.place();
      _finishTurn(isPlayer: true);
    }
  }

  void _finishTurn({required bool isPlayer}) {
    setState(() {
      if (isPlayer) {
        lastPlayedCard = selectedCard;
        playerHand.remove(selectedCard);
        selectedCard = null;
        playerHand.add(DeckManager.drawSmartCard(deck, boardState, boardLayout, widget.difficulty, 1));
        _checkScores(1);
        if (playerScore >= 2) { _handleWin(true); return; }

        isPlayerTurn = false;
        aiStatus = "Thinking...";
        _startAiTurn();
      } else {
        _checkScores(2);
        if (aiScore >= 2) { _handleWin(false); return; }

        isPlayerTurn = true;
        aiStatus = "Your Turn";
        _startTimer();
      }
    });
  }

  Future<void> _startAiTurn() async {
    _turnTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    Map<String, dynamic> aiMove = AiLogic.getMove(widget.difficulty, opponentHand, boardState, boardLayout, cornerIndices, lockedSequences);

    if (aiMove.isEmpty) {
      setState(() {
        aiStatus = "Trading card...";
        opponentHand.removeAt(0);
        opponentHand.add(DeckManager.drawSmartCard(deck, boardState, boardLayout, widget.difficulty, 2));
      });
    } else {
      String card = aiMove['card'];
      int index = aiMove['index'];

      setState(() {
        lastAiPlayedCard = card;
        if (aiMove['type'] == 'remove') {
          boardState[index] = 0;
          aiStatus = "Blocked you!";
          SoundManager.place();
        } else {
          boardState[index] = 2;
          lastPlacedChipIndex = index;
          aiStatus = "My move.";
          SoundManager.place();
        }
        opponentHand.remove(card);
        opponentHand.add(DeckManager.drawSmartCard(deck, boardState, boardLayout, widget.difficulty, 2));
      });
      HapticFeedback.mediumImpact();
    }

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _finishTurn(isPlayer: false);
  }

  void _checkScores(int playerId) {
    for (int r = 0; r < 10; r++) _verifyLine(r*10, 1, 10, playerId);
    for (int c = 0; c < 10; c++) _verifyLine(c, 10, 10, playerId);
    for (int r=0; r<=5; r++) for (int c=0; c<=5; c++) _verifyLine((r*10)+c, 11, 5, playerId);
    for (int r=0; r<=5; r++) for (int c=4; c<10; c++) _verifyLine((r*10)+c, 9, 5, playerId);
  }

  void _verifyLine(int start, int step, int count, int playerId) {
    List<int> sequence = [];
    for (int i = 0; i < count; i++) {
      int index = start + (step * i);
      if (index >= 100) break;

      if (boardState[index] == playerId || cornerIndices.contains(index)) {
        sequence.add(index);
      } else {
        _processPotentialSequence(sequence, playerId);
        sequence = [];
      }
    }
    _processPotentialSequence(sequence, playerId);
  }

  void _processPotentialSequence(List<int> sequence, int playerId) {
    if (sequence.length >= 5) {
      String id = sequence.take(5).join(",");
      bool alreadyLocked = false;
      for (var seq in lockedSequences) {
        if (seq.join(",") == id) alreadyLocked = true;
      }

      if (!alreadyLocked) {
        lockedSequences.add(sequence.take(5).toList());
        if (playerId == 1) playerScore++;
        else aiScore++;
        HapticFeedback.vibrate();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${playerId == 1 ? 'You' : 'AI'} scored a sequence!"), backgroundColor: Colors.amber));
      }
    }
  }

  bool _isChipLocked(int index) {
    for (var seq in lockedSequences) {
      if (seq.contains(index)) return true;
    }
    return false;
  }

  void _handleWin(bool playerWon) {
    setState(() => isGameOver = true);

    // --- NEW: SAVE TO DATABASE ---
    if (widget.isOnline && _onlineService != null) {
      _onlineService!.recordGameEnd(
          won: playerWon,
          opponentName: opponentName
      );
    }
    // -----------------------------

    if (playerWon) SoundManager.win();

    _showEndGameDialog(
        playerWon ? "VICTORY!" : "DEFEAT",
        playerWon ? "You got 2 Sequences! (+100 Coins)" : "AI got 2 Sequences. (+20 Coins)",
        playerWon
    );
  }

  void _showEndGameDialog(String title, String message, bool victory) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text(title, style: TextStyle(color: victory ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("EXIT"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    if (isLoading || boardLayout.isEmpty) {
      if (widget.isOnline) {
        return FindingMatchView(
          onCancel: _cancelOnlineSearch,
          onTimeout: () {
            _cancelOnlineSearch();
            _showEndGameDialog("Error", "Umm, I don't know what happened.\nTry again later.", false);
          },
        );
      } else {
        return const Scaffold(backgroundColor: Color(0xFF1E1E1E), body: Center(child: CircularProgressIndicator()));
      }
    }

    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF1E1E1E), body: Center(child: CircularProgressIndicator()));

    Color timerColor = Colors.green;
    if (_secondsRemaining <= 20) timerColor = Colors.orange;
    if (_secondsRemaining <= 10) timerColor = Colors.red;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)]),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // --- LAYER 1: MAIN GAME AREA ---
              Column(
                children: [
                  // HEADER
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white70), onPressed: () => Navigator.pop(context)),
                        Column(
                          children: [
                            Text("@Opponent (${widget.difficulty})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text("AI Score: $aiScore | You: $playerScore", style: const TextStyle(color: Colors.amber, fontSize: 12)),
                            Text(aiStatus, style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green)),
                          child: Text("$_secondsRemaining s", style: const TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                  ),

                  // OPPONENT HAND + AI LAST MOVE
                  SizedBox(
                    height: 50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if(lastAiPlayedCard != null)
                          Padding(padding: const EdgeInsets.only(right: 15), child: _buildPlayingCard(lastAiPlayedCard!, scale: 0.5)),
                        SizedBox(
                          width: 200,
                          child: Center(
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal, shrinkWrap: true, itemCount: opponentHand.length,
                              itemBuilder: (context, index) => Align(widthFactor: 0.5, child: _buildCardBack(scale: 0.6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 5),

                  // --- THE BOARD (RECTANGULAR ASPECT RATIO) ---
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(8), boxShadow: [const BoxShadow(color: Colors.black45, blurRadius: 15, offset: Offset(0, 10))]),
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 10,
                              childAspectRatio: 0.65, // Tall rectangles
                              crossAxisSpacing: 1,
                              mainAxisSpacing: 1
                          ),
                          itemCount: 100,
                          itemBuilder: (context, index) => _buildBoardSquare(index),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 120),
                ],
              ),

              // --- LAYER 2: BOTTOM CONTROLS (Floating on top) ---
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 140, // Height for the arc
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      // Discard Pile (Far Left)
                      Positioned(
                        left: 20, bottom: 20,
                        child: Column(
                          children: [
                            const Text("Played", style: TextStyle(color: Colors.white54, fontSize: 10)),
                            const SizedBox(height: 4),
                            lastPlayedCard == null ? Container(width: 45, height: 65, decoration: BoxDecoration(border: Border.all(color: Colors.white12))) : _buildPlayingCard(lastPlayedCard!, scale: 0.7, isFlat: true),
                          ],
                        ),
                      ),

                      // PLAYER HAND (CURVED / FANNED & ON TOP)
                      Positioned(
                        bottom: -20, // Push down slightly so they pop up nicely
                        child: SizedBox(
                          height: 150,
                          width: MediaQuery.of(context).size.width,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: playerHand.asMap().entries.map((entry) {
                              int idx = entry.key;
                              int total = playerHand.length;
                              String card = entry.value;
                              bool isSelected = card == selectedCard;

                              // ARC MATH
                              double center = (total - 1) / 2;
                              double relativePos = idx - center;
                              double rotation = relativePos * 0.12;
                              double yOffset = (relativePos.abs() * relativePos.abs()) * 3.0; // Arch curve
                              double xOffset = relativePos * 35;

                              return Positioned(
                                bottom: 40 - yOffset + (isSelected ? 50 : 0), // POP UP Logic
                                left: (MediaQuery.of(context).size.width / 2) + xOffset - 30,
                                child: GestureDetector(
                                  onTap: () => _onCardTap(card),
                                  child: Transform.rotate(
                                    angle: rotation,
                                    child: _buildPlayingCard(card, scale: 1.1),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- VISUALS ---
  Widget _buildPlayingCard(String card, {double scale = 1.0, bool isFlat = false}) {
    Color suitColor = (card.contains("H") || card.contains("D")) ? Colors.red[700]! : Colors.black;
    String rank = card.substring(0, card.length - 1);
    IconData suitIcon = _getSuitIcon(card);

    return Container(
      width: 50 * scale,
      height: 75 * scale,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isFlat ? [] : [const BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(2, 2))],
        border: selectedCard == card && !isFlat ? Border.all(color: Colors.amber, width: 3) : Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Stack(
        children: [
          // Top Left
          Positioned(
              left: 2, top: 2,
              child: Column(
                  children: [
                    Text(rank, style: TextStyle(color: suitColor, fontWeight: FontWeight.bold, fontSize: 12 * scale, height: 1)),
                    Icon(suitIcon, color: suitColor, size: 10 * scale)
                  ]
              )
          ),
          // Bottom Right (Rotated)
          Positioned(
              right: 2, bottom: 2,
              child: Transform.rotate(
                  angle: pi,
                  child: Column(
                      children: [
                        Text(rank, style: TextStyle(color: suitColor, fontWeight: FontWeight.bold, fontSize: 12 * scale, height: 1)),
                        Icon(suitIcon, color: suitColor, size: 10 * scale)
                      ]
                  )
              )
          ),
          // Center Big Suit
          Center(child: Icon(suitIcon, color: suitColor, size: 28 * scale)),
        ],
      ),
    );
  }

  Widget _buildBoardSquare(int index) {
    bool isCorner = cornerIndices.contains(index);
    int owner = boardState[index];
    String cardName = boardLayout[index];
    bool isWinningChip = false;
    for(var seq in lockedSequences) if(seq.contains(index)) isWinningChip = true;

    Color suitColor = _getSuitColor(cardName);
    String rank = isCorner ? "" : cardName.substring(0, cardName.length - 1);
    IconData suitIcon = isCorner ? Icons.star : _getSuitIcon(cardName);

    Color bgColor = const Color(0xFFF5F5F5);
    if (isCorner) bgColor = const Color(0xFFFFD700);

    // Highlight logic
    if(selectedCard != null && !isCorner && owner == 0) {
      bool isJack = selectedCard!.startsWith("J");
      bool isBlackJack = isJack && (selectedCard!.contains("C") || selectedCard!.contains("S"));
      if (cardName == selectedCard || isBlackJack) bgColor = const Color(0xFF66BB6A);
    }

    bool isLastPlaced = (index == lastPlacedChipIndex);

    return GestureDetector(
      onTap: () => _onBoardTap(index),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
          border: isWinningChip ? Border.all(color: Colors.greenAccent, width: 2) : Border.all(color: Colors.grey[400]!, width: 0.5),
        ),
        child: Stack(
          children: [
            // CARD FACE (Corners like reference image)
            if(!isCorner) ...[
              Positioned(left: 1, top: 1, child: Text(rank, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: suitColor))),
              Positioned(left: 1, top: 10, child: Icon(suitIcon, size: 8, color: suitColor)),

              Positioned(right: 1, bottom: 1, child: Transform.rotate(angle: pi, child: Text(rank, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: suitColor)))),
              Positioned(right: 1, bottom: 10, child: Transform.rotate(angle: pi, child: Icon(suitIcon, size: 8, color: suitColor))),

              // Center Suit (Large & Faded)
              Center(child: Icon(suitIcon, size: 24, color: suitColor.withOpacity(0.15))),
            ] else
              const Center(child: Icon(Icons.star, size: 20, color: Colors.black)),

            // CHIP OVERLAY (Centered)
            if (owner != 0)
              Center(
                child: AnimatedScale(
                  scale: 1.0, duration: const Duration(milliseconds: 300), curve: Curves.elasticOut,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: isWinningChip ? [BoxShadow(color: Colors.greenAccent, blurRadius: 10)] : (isLastPlaced ? [BoxShadow(color: Colors.cyanAccent, blurRadius: 8)] : [const BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(1, 1))]),
                      color: owner == 1 ? myChip.color : const Color(0xFFD32F2F),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: owner == 1 ? Icon(myChip.icon, color: Colors.white, size: 18) : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBack({double scale = 1.0}) {
    return Container(
        width: 45 * scale,
        height: 65 * scale,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
            color: const Color(0xFFB71C1C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [const BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 1))]
        ),
        child: Center(
            child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24, width: 1),
                    borderRadius: BorderRadius.circular(2)
                ),
                child: const Center(child: Icon(Icons.hub, color: Colors.white24, size: 16))
            )
        )
    );
  }
  Color _getSuitColor(String card) {
    // Hearts and Diamonds are Red, Spades and Clubs are Black
    if (card.contains("H") || card.contains("D")) {
      return Colors.red[800]!;
    }
    return Colors.black;
  }

  IconData _getSuitIcon(String card) {
    if (card.contains("H")) return CupertinoIcons.suit_heart_fill;
    if (card.contains("D")) return CupertinoIcons.suit_diamond_fill;
    if (card.contains("C")) return CupertinoIcons.suit_club_fill;
    return CupertinoIcons.suit_spade_fill;
  }
}

class FindingMatchView extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onTimeout;
  const FindingMatchView({required this.onCancel, required this.onTimeout, super.key});

  @override
  State<FindingMatchView> createState() => _FindingMatchViewState();
}

class _FindingMatchViewState extends State<FindingMatchView> with TickerProviderStateMixin {
  late AnimationController _radarController;
  late AnimationController _textPulseController;
  Timer? _searchTimer;
  int _seconds = 0;
  final List<String> _statusMessages = ["Scanning network...", "Pinging servers...", "Looking for opponent...", "Establishing connection..."];
  int _statusIndex = 0;

  @override
  void initState() {
    super.initState();
    // 1. Radar Animation
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    // 2. Text Pulse
    _textPulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

    // 3. Logic Timer (60s Limit)
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _seconds++;
        if (_seconds % 4 == 0) _statusIndex = (_statusIndex + 1) % _statusMessages.length; // Cycle text
      });

      if (_seconds >= 60) {
        timer.cancel();
        widget.onTimeout();
      }
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    _textPulseController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Cyber Blue
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // RADAR RINGS
            ...List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _radarController,
                builder: (context, child) {
                  double value = (_radarController.value + (index * 0.35)) % 1.0;
                  double size = value * 400;
                  double opacity = (1.0 - value).clamp(0.0, 1.0);

                  return Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.cyanAccent.withOpacity(opacity), width: 2),
                      boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(opacity * 0.5), blurRadius: 10)],
                    ),
                  );
                },
              );
            }),

            // CENTER ICON
            const Icon(Icons.public, color: Colors.white, size: 50),

            // TEXT STATUS
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

            // CANCEL BUTTON
            Positioned(
              bottom: 50,
              child: TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.2),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: const BorderSide(color: Colors.redAccent)),
                ),
                child: const Text("CANCEL SEARCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}