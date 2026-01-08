import 'dart:async';
import 'dart:math';
import 'dart:ui'; // Added for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../screens/store/data/chip_data.dart';
import '../game/offline/ai_logic.dart';
import '../game/smart_deck/deck_manager.dart';
import '../../sounds/sound_manager.dart';
import '../../database/online_service.dart';
import '../account/data/avatar_data.dart';
import 'arranged_board.dart';

class GameBoard extends StatefulWidget {
  final String difficulty;
  final int playerCount;
  final bool isTeamMode;
  final bool isOnline;
  final String? chipId;
  const GameBoard({
    super.key,
    this.difficulty = "Easy",
    this.isOnline = false,
    this.chipId,
    this.playerCount = 1,
    this.isTeamMode = false,
  });

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> with TickerProviderStateMixin {
  // Game State
  GameChip myChip = allGameChips[0];
  GameChip aiChip = allGameChips[1];
  bool isLoading = true;
  String opponentName = "@Opponent";
  String _myHandle = "Player";
  String opponentAvatarId = "avatar_1";
  String _avatarId = "avatar_1";
  String opponentFlag = "🤖";
  int totalCoins = 0;
  bool _isOpponentOffline = false;

  List<String> deck = [];
  final List<String> playerHand = [];
  final List<String> opponentHand = [];
  final List<int> boardState = List.filled(100, 0);
  List<String> boardLayout = [];
  final Set<int> cornerIndices = {0, 9, 90, 99};

  int? _partnerHoverIndex;
  Timer? _botTimer;
  bool _showAddBotButton = false;

  List<Map<String, dynamic>> moveLog = [];

  int currentTurnIndex = 0;
  List<List<String>> allHands = [];
  List<Map<String, dynamic>> playersInfo = [];

  // Win Logic
  bool isPlayerTurn = true;
  bool isGameOver = false;
  bool isSuddenDeath = false;
  List<List<int>> winningSequences = [];
  late String currentAiDifficulty;

  // New: Track who won to highlight their header
  int? winningPlayerIndex;

  // Interaction
  String? selectedCard;
  String? opponentSelectedCard;
  String? lastUsedCard;
  int? lastPlacedChipIndex;
  Offset? hoverPosition;
  Offset? aiCursorPosition;

  List<String> burningCards = [];
  List<_AshParticle> particles = [];
  Timer? particleTimer;

  // Matchmaking & Chat
  int playersSearching = 0;
  int playersOnline = 0;
  StreamSubscription? _matchmakingSubscription;
  StreamSubscription? _presenceSubscription;
  StreamSubscription? _chatSubscription;
  bool _isChatListenerActive = false;

  List<Map<dynamic, dynamic>> messages = [];
  bool isChatOpen = false;
  final TextEditingController _chatController = TextEditingController();

  // Sound Board State
  bool isSoundBoardOpen = false;
  bool isSoundPlaying = false;
  final List<String> soundBoardFiles = [
    "comment1.mp3",
    "comment2.mp3",
    "comment3.mp3",
    "comment4.mp3",
    "comment5.mp3",
    "comment6.mp3",
    "error.mp3",
    "fail.mp3",
    "win.mp3",
    "win2.mp3",
  ];

  List<int> shimmeringIndices = [];
  OnlineService? _onlineService;
  int myPlayerValue = 1;

  // UI State
  late AnimationController _textPulseController;
  late AnimationController _searchingRotateController;
  late AnimationController _avatarReactionController;
  Timer? _searchTimer;
  int _seconds = 0;
  int _statusIndex = 0;
  int _tipIndex = 0;

  final List<String> _statusMessages = [
    "Connecting...",
    "Scanning Lobby...",
    "Joining Queue...",
    "Syncing Deck...",
  ];
  final List<String> _proTips = [
    "Pro Tip: Red Jacks can remove any chip except those in a completed sequence.",
    "Trivia: A standard Jack's Lines deck has 104 cards.",
    "Strategy: Corners are wild! Use them to complete two lines at once.",
    "Pro Tip: Save your Two-Eyed Jacks for critical blocks.",
    "Strategy: Focus on blocking the opponent early if they're aggressive.",
  ];

  late ConfettiController _confettiController;
  Timer? _turnTimer;
  int _turnTimeRemaining = 60;

  @override
  void initState() {
    super.initState();
    currentAiDifficulty = widget.difficulty;
    _loadMyChip();
    _loadManualBoard();
    _consumeLife();

    _textPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _searchingRotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _avatarReactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    particleTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (particles.isNotEmpty)
        setState(() {
          for (var p in particles) p.update();
          particles.removeWhere((p) => p.life <= 0);
        });
    });

    if (widget.isOnline) {
      _setupPresence();
      _startSearchAnimation();
      _startOnlineMatchmaking();
    } else {
      _startOfflineGame();
    }
  }

  @override
  void dispose() {
    _textPulseController.dispose();
    _searchingRotateController.dispose();
    _avatarReactionController.dispose();
    _confettiController.dispose();
    _chatController.dispose();
    _searchTimer?.cancel();
    _turnTimer?.cancel();
    particleTimer?.cancel();
    _matchmakingSubscription?.cancel();
    _presenceSubscription?.cancel();
    _chatSubscription?.cancel();
    _onlineService?.leaveGame();
    super.dispose();
  }

  void _setupPresence() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseDatabase.instance.ref().child('presence').child(user.uid).set({
      'active': true,
      'last_seen': ServerValue.timestamp,
    });
    FirebaseDatabase.instance
        .ref()
        .child('presence')
        .child(user.uid)
        .onDisconnect()
        .remove();

    _presenceSubscription = FirebaseDatabase.instance
        .ref()
        .child('presence')
        .onValue
        .listen((event) {
          if (!mounted) return;
          final data = event.snapshot.value as Map?;
          setState(() => playersOnline = data?.length ?? 1);
        });

    _matchmakingSubscription = FirebaseDatabase.instance
        .ref()
        .child('lobby')
        .onValue
        .listen((event) {
          if (!mounted) return;
          final data = event.snapshot.value as Map?;
          setState(() => playersSearching = data?.length ?? 0);
        });
  }

  void _loadManualBoard() {
    setState(() => boardLayout = List.from(ArrangedBoard.layout));
  }

  Future<void> _loadMyChip() async {
    final prefs = await SharedPreferences.getInstance();
    String chipId =
        widget.chipId ??
        prefs.getString('selected_chip_id') ??
        allGameChips[0].id;
    int coins = prefs.getInt('total_coins') ?? 0;
    String avatarId = prefs.getString('selected_avatar_id') ?? "avatar_1";
    String handle = prefs.getString('unique_handle') ?? "Player";
    if (mounted) {
      setState(() {
        totalCoins = coins;
        _avatarId = avatarId;
        _myHandle = handle;
        myChip = allGameChips.firstWhere(
          (c) => c.id == chipId,
          orElse: () => allGameChips[0],
        );
        bool isPlayerRed = myChip.id.toLowerCase().contains("red");
        if (isPlayerRed) {
          aiChip = allGameChips.firstWhere(
            (c) => c.id.toLowerCase().contains("blue"),
            orElse: () => allGameChips[1],
          );
        } else {
          aiChip = allGameChips.firstWhere(
            (c) => c.id.toLowerCase().contains("red"),
            orElse: () => allGameChips[0],
          );
        }
      });
    }
  }

  Future<void> _consumeLife() async {
    final prefs = await SharedPreferences.getInstance();
    int currentHearts = prefs.getInt('heart_count') ?? 5;
    if (currentHearts > 0) {
      int newHearts = currentHearts - 1;
      await prefs.setInt('heart_count', newHearts);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null)
        FirebaseDatabase.instance.ref().child('users').child(user.uid).update({
          'heart_count': newHearts,
        });
    }
  }

  Future<void> _recordGameResult({required bool won}) async {
    final prefs = await SharedPreferences.getInstance();
    int wins = prefs.getInt('total_wins') ?? 0;
    int losses = prefs.getInt('total_losses') ?? 0;
    int totalMatches = prefs.getInt('total_matches') ?? 0;
    int currentXp = prefs.getInt('xp') ?? 0;
    int currentCoins = prefs.getInt('total_coins') ?? 0;

    int xpGain = won ? 20 : 5;

    // Logic: Increase streak, coins, and wins
    if (won) {
      wins += 1;
      currentXp += xpGain;
      currentCoins += 100; // Reward for winning
      await prefs.setInt('total_wins', wins);
      await prefs.setInt('total_coins', currentCoins);
      await prefs.setInt(
        'user_coins',
        currentCoins,
      ); // Sync key for OnlineService
    } else {
      losses += 1;
      currentXp += xpGain;
      await prefs.setInt('total_losses', losses);
    }

    totalMatches += 1;
    await prefs.setInt('total_matches', totalMatches);
    await prefs.setInt('xp', currentXp);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final dbRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid);

      // Update stats and coins on Firebase
      await dbRef.update({
        'total_wins': wins,
        'total_losses': losses,
        'total_matches': totalMatches,
        'xp': currentXp,
        'coins': currentCoins, // Update coins remotely
      });

      dbRef.child('matches').push().set({
        'result': won ? 'win' : 'loss',
        'mode': widget.isOnline ? 'Online' : 'Offline',
        'xp_gain': xpGain,
        'coins_gained': won ? 100 : 0,
        'timestamp': ServerValue.timestamp,
        'opponent_name': opponentName,
        'board_snapshot': boardState.join(','),
      });
    }

    // Update local state to reflect new coins immediately
    if (mounted) setState(() => totalCoins = currentCoins);
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    setState(() => _turnTimeRemaining = 60);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_turnTimeRemaining > 0) {
          _turnTimeRemaining--;
          if (_turnTimeRemaining <= 10) HapticFeedback.heavyImpact();
        } else {
          _handleTimeout();
        }
      });
    });
  }

  Future<void> _checkForDeadCards(
    List<String> hand, {
    bool isPlayer = true,
  }) async {
    List<String> deadCards = [];
    for (String card in hand) {
      if (card.contains('J')) continue; // Jacks are never dead
      List<int> pos = [];
      for (int i = 0; i < boardLayout.length; i++) {
        if (boardLayout[i] == card) pos.add(i);
      }
      // A card is dead if all its board positions are occupied
      if (pos.isNotEmpty && pos.every((idx) => boardState[idx] != 0)) {
        deadCards.add(card);
      }
    }

    if (deadCards.isNotEmpty) {
      setState(() => burningCards.addAll(deadCards));
      HapticFeedback.heavyImpact();
      // Use existing particle logic
      for (int i = 0; i < 20; i++) {
        particles.add(
          _AshParticle(Offset(MediaQuery.of(context).size.width / 2, 600)),
        );
      }

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      setState(() {
        for (String dead in deadCards) {
          hand.remove(dead);
          hand.add(_drawCard(isPlayer: isPlayer));
        }
        burningCards.clear();
      });
    }
  }

  void _handleTimeout() {
    _turnTimer?.cancel();
    if (isGameOver) return;

    // If time runs out, current player loses.
    // In Offline: If Player (Index 0) times out -> Winner is AI (Index 1)
    // In Online: If I time out -> Winner is Opponent

    bool iLost = isPlayerTurn;
    // If I lost, the winner is someone else.
    // Simplified: Just record result. For visual header we need index.
    // If I am P1 (Index 0) and I lose, Winner is Index 1.
    int mySlot = 0;
    if (widget.isOnline) {
      mySlot = int.parse(_onlineService?.myRole.split('_').last ?? "0");
    }
    int winnerIdx = iLost ? (mySlot == 0 ? 1 : 0) : mySlot;

    setState(() {
      isGameOver = true;
      winningPlayerIndex = winnerIdx;
    });

    _recordGameResult(won: !iLost);
    // Don't show dialog, show blur exit
  }

  void _handleExit() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "QUIT MATCH?",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Abandoning this match will count as an immediate LOSS and reset your streak. Are you sure?",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "STAY",
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Step 1: Close Dialog
              _recordGameResult(won: false);
              _onlineService?.sendForfeit(); // Step 2: Notify others
              _onlineService?.leaveGame(); // Step 3: Cleanup
              Navigator.pop(context); // Step 4: Return to Menu
            },
            child: const Text(
              "ABANDON",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startOnlineMatchmaking() async {
    _onlineService = OnlineService();

    _onlineService!.onGameStateChanged = (data) {
      if (!mounted) return;

      bool disconnected = false;
      if (data['players'] != null) {
        Map pMap = data['players'];
        pMap.forEach((key, val) {
          if (val['id'] != FirebaseAuth.instance.currentUser?.uid &&
              val['status'] == 'offline') {
            disconnected = true;
          }
        });
      }

      if (data['players'] != null) {
        setState(() {
          Map pMap = data['players'];
          var sortedKeys = pMap.keys.toList()..sort();
          playersInfo = sortedKeys
              .map((k) => Map<String, dynamic>.from(pMap[k]))
              .toList();
        });
      }
      // Monitor for other players going offline during the match
      if (data['status'] == 'playing' && !isGameOver) {
        for (var p in playersInfo) {
          if (p['id'] != FirebaseAuth.instance.currentUser?.uid &&
              p['status'] == 'offline') {
            // If an opponent goes offline, wait 5 seconds before declaring forfeit
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) _checkAndForfeit();
            });
          }
        }
      }

      if (data['status'] == 'forfeit' && !isGameOver) {
        _triggerVictoryByForfeit();
        return;
      }

      // 2. HANDLE MATCH START
      if (data['status'] == 'playing') {
        if (isLoading) {
          SoundManager.play('card_shuffle');
          _avatarReactionController.forward().then(
            (_) => _avatarReactionController.reverse(),
          );
        }

        setState(() {
          isLoading = false;
          _isOpponentOffline = disconnected;
          currentTurnIndex = data['turn_index'] ?? 0;

          String myRole = _onlineService!.myRole;
          int mySlotIndex = int.parse(myRole.split('_').last);
          myPlayerValue = _getPlayerChipValue(mySlotIndex);

          if (data['board'] != null) {
            List<dynamic> cloudBoard = data['board'];
            for (int i = 0; i < 100; i++) {
              if (cloudBoard[i] is int) boardState[i] = cloudBoard[i];
            }
          }

          if (data['last_move'] != null) {
            lastPlacedChipIndex = data['last_move']['index'];
            lastUsedCard = data['last_move']['card'];
          }

          _stopSearchAnimation();
          _startTurnTimer();
          checkForWin();
        });

        if (allHands.isEmpty) _dealInitialHands();
        _setupChatListener();
      }

      // Handle Forfeit
      if (data['status'] == 'forfeit' && !isGameOver) {
        _triggerVictoryByForfeit();
      }
    };

    _botTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && isLoading) setState(() => _showAddBotButton = true);
    });

    await _onlineService!.findMultiplayerMatch(
      targetPlayers: widget.playerCount,
      isTeam: widget.isTeamMode,
      chipId: myChip.id,
    );
  }

  void _triggerVictoryByForfeit() {
    if (isGameOver) return;

    // I win if they forfeit
    int mySlot = 0;
    if (widget.isOnline) {
      mySlot = int.parse(_onlineService?.myRole.split('_').last ?? "0");
    }

    setState(() {
      isGameOver = true;
      winningPlayerIndex = mySlot; // I am the winner
      _turnTimer?.cancel();
    });

    _recordGameResult(won: true);
    _confettiController.play();
    SoundManager.play('win');
  }

  void _checkAndForfeit() {
    if (isGameOver) return;

    // Check if any opponent is offline
    bool opponentGone = false;
    for (var p in playersInfo) {
      if (p['id'] != FirebaseAuth.instance.currentUser?.uid &&
          p['status'] == 'offline') {
        opponentGone = true;
        break;
      }
    }

    if (opponentGone) {
      _triggerVictoryByForfeit();
    }
  }

  void _setupChatListener() {
    if (_isChatListenerActive) return;
    final gameId = _onlineService?.currentGameId;
    if (gameId == null) return;
    _isChatListenerActive = true;
    _chatSubscription = FirebaseDatabase.instance
        .ref()
        .child('games')
        .child(gameId)
        .child('chats')
        .onChildAdded
        .listen((event) {
          if (!mounted) return;
          final data = event.snapshot.value as Map?;
          if (data != null)
            setState(() {
              messages.add(data);
              if (!isChatOpen &&
                  data['sender'] != FirebaseAuth.instance.currentUser?.uid)
                _showQuickMessageOverlay(data['text']);
            });
        });
  }

  void _showQuickMessageOverlay(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$opponentName: $text"),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sendChatMessage(String text) {
    if (text.trim().isEmpty) return;
    _onlineService?.sendChatMessage(text);
    _chatController.clear();
  }

  void _dealInitialHands() {
    deck = DeckManager.createFullDeck()..shuffle();

    allHands = List.generate(max(2, widget.playerCount), (_) => []);
    playerHand.clear();
    opponentHand.clear();

    for (int i = 0; i < 7; i++) {
      for (int p = 0; p < allHands.length; p++) {
        String card = deck.removeLast();
        allHands[p].add(card);
        // Ensure offline hands are filled too
        if (p == 0) playerHand.add(card);
        if (p == 1) opponentHand.add(card);
      }
    }
  }

  int _getPlayerChipValue(int playerIndex) {
    if (!widget.isTeamMode) return playerIndex + 1;
    // Team 1: 0 & 2 -> Value 1. Team 2: 1 & 3 -> Value 2.
    return (playerIndex % 2) + 1;
  }

  void _startOfflineGame() {
    _dealInitialHands();
    setState(() {
      isLoading = false;
      isPlayerTurn = true;
      currentTurnIndex = 0;
      opponentName = "Offline";
      opponentFlag = "🤖";
    });
    _startTurnTimer();
  }

  void _startSearchAnimation() {
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _seconds++;
        if (_seconds % 3 == 0)
          _statusIndex = (_statusIndex + 1) % _statusMessages.length;
        if (_seconds % 5 == 0) _tipIndex = (_tipIndex + 1) % _proTips.length;
      });
    });
  }

  void _stopSearchAnimation() {
    _searchTimer?.cancel();
  }

  void _cancelSearch() {
    _onlineService?.cancelSearch();
    Navigator.pop(context);
  }

  void _onBoardTap(int index) {
    int mySlotIndex = int.parse(_onlineService?.myRole.split('_').last ?? "0");

    // Ensure we only act on our turn
    if (currentTurnIndex != mySlotIndex || isGameOver || selectedCard == null)
      return;

    int myChipValue = _getPlayerChipValue(mySlotIndex);
    if (cornerIndices.contains(index)) return;

    String targetCard = boardLayout[index];
    bool isJack = selectedCard!.contains('J');
    bool isRedJack =
        isJack && (selectedCard!.contains('H') || selectedCard!.contains('D'));
    bool isBlackJack =
        isJack && (selectedCard!.contains('C') || selectedCard!.contains('S'));

    bool success = false;

    if (isJack) {
      if (isBlackJack && boardState[index] == 0)
        success = true; // Anywhere empty
      else if (isRedJack &&
          boardState[index] != 0 &&
          boardState[index] != myChipValue) {
        if (!_isChipLocked(index)) {
          _executeMove(index, 0); // Red Jacks remove chips
          return;
        }
      }
    } else {
      if (targetCard == selectedCard && boardState[index] == 0) success = true;
    }

    if (success) {
      if (widget.isOnline) {
        // ONLINE: Send to server and let the listener update the board
        int nextTurn = (currentTurnIndex + 1) % widget.playerCount;
        _onlineService?.sendMultiplayerMove(
          index,
          selectedCard!,
          myChipValue,
          nextTurn,
        );

        setState(() {
          allHands[mySlotIndex].remove(selectedCard);
          allHands[mySlotIndex].add(_drawCard(isPlayer: true));
          selectedCard = null;
        });
      } else {
        // OFFLINE: Execute locally and finish the turn to trigger AI
        setState(() {
          boardState[index] = myChipValue;
          lastPlacedChipIndex = index;
          lastUsedCard = selectedCard;
          playerHand.remove(selectedCard);
          if (deck.isNotEmpty) playerHand.add(_drawCard(isPlayer: true));
          selectedCard = null;
        });
        _finishTurn(isPlayer: true);
      }
    }
  }

  void _executeMove(int index, int value) {
    HapticFeedback.lightImpact();
    moveLog.add({
      'index': index,
      'value': value,
      'card': selectedCard,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (widget.isOnline) {
      _onlineService?.sendMove(index, selectedCard!, value);
      setState(() {
        lastUsedCard = selectedCard;
        playerHand.remove(selectedCard);
        selectedCard = null;
        if (deck.isNotEmpty) playerHand.add(_drawCard(isPlayer: true));
        isPlayerTurn = false;
      });
      _startTurnTimer();
    } else {
      setState(() {
        boardState[index] = value;
        lastPlacedChipIndex = value == 0 ? null : index;
        lastUsedCard = selectedCard;
        playerHand.remove(selectedCard);
        selectedCard = null;
        if (deck.isNotEmpty) playerHand.add(_drawCard(isPlayer: true));
      });
      _finishTurn(isPlayer: true);
    }
  }

  String _drawCard({required bool isPlayer}) {
    if (deck.isEmpty) return "";
    if (isPlayer && !widget.isOnline) {
      int pSeqs = 0, aSeqs = 0;
      for (var seq in winningSequences) {
        bool p1 = false;
        for (int idx in seq) {
          if (!cornerIndices.contains(idx)) {
            if (boardState[idx] == 1) p1 = true;
            break;
          }
        }
        if (p1)
          pSeqs++;
        else
          aSeqs++;
      }
      if (aSeqs > pSeqs && Random().nextDouble() < 0.25) {
        int jIdx = deck.indexWhere((c) => c.contains('J'));
        if (jIdx != -1) return deck.removeAt(jIdx);
      }
    }
    return deck.removeLast();
  }

  bool _isChipLocked(int index) {
    for (var seq in winningSequences) if (seq.contains(index)) return true;
    return false;
  }

  void _finishTurn({required bool isPlayer}) async {
    checkForWin();
    if (isGameOver) return;

    // Trigger the dead card check for the player who just finished
    await _checkForDeadCards(
      isPlayer ? playerHand : opponentHand,
      isPlayer: isPlayer,
    );

    if (isPlayer) {
      setState(() {
        isPlayerTurn = false;
        _startAiTurn();
      });
    } else {
      setState(() {
        isPlayerTurn = true;
      });
    }
    _startTurnTimer();
  }

  Offset _getBoardCellCenter(int index) {
    double sw = MediaQuery.of(context).size.width;
    double cellSide = (sw - 16.0) / 10;
    double x = 8.0 + (index % 10) * cellSide + (cellSide / 2);
    double y =
        140.0 + (index ~/ 10) * (cellSide / 0.70) + ((cellSide / 0.70) / 2);
    return Offset(x, y);
  }

  Future<void> _startAiTurn() async {
    //
    await Future.delayed(const Duration(milliseconds: 1000)); //
    if (!mounted) return; //

    AiMove? move = AiLogic.findBestMove(
      opponentHand,
      boardState,
      boardLayout,
      currentAiDifficulty,
      2,
    );

    if (move != null) {
      if (move.isDiscard) {
        //
        // AI "burns" the card - update the UI so the player sees what happened
        setState(() {
          lastUsedCard = move.cardUsed;
          opponentSelectedCard = move.cardUsed;
        });
        await Future.delayed(
          const Duration(milliseconds: 800),
        ); // Give player time to see it
      } else {
        // Normal move logic
        Offset target = _getBoardCellCenter(move.index); //
        setState(() {
          opponentSelectedCard = move.cardUsed;
          aiCursorPosition = Offset(
            MediaQuery.of(context).size.width / 2,
            40,
          ); //
        });

        await Future.delayed(const Duration(milliseconds: 50)); //
        setState(() => aiCursorPosition = target); //
        await Future.delayed(const Duration(milliseconds: 800)); //

        if (!mounted) return;
        setState(() {
          if (move.isRemoval) {
            //
            boardState[move.index] = 0; //
          } else {
            boardState[move.index] = 2; //
            lastPlacedChipIndex = move.index; //
          }
          lastUsedCard = move.cardUsed; //
          opponentHand.remove(move.cardUsed); //
          opponentSelectedCard = null; //
          aiCursorPosition = null; //
          if (deck.isNotEmpty) opponentHand.add(deck.removeLast()); //
        });
      }
    }

    // Ensure this is called AFTER the if(move != null) block concludes
    _finishTurn(isPlayer: false); //
  }

  void checkForWin() {
    int winTarget = (widget.playerCount == 3) ? 1 : 2;
    Map<int, int> teamSequences = {1: 0, 2: 0, 3: 0};
    List<List<int>> potential = [];

    for (int i = 0; i < 100; i++) {
      if (i % 10 <= 5) _checkLine(i, 1, potential);
      if (i < 60) _checkLine(i, 10, potential);
      if (i % 10 <= 5 && i < 60) _checkLine(i, 11, potential);
      if (i % 10 >= 4 && i < 60) _checkLine(i, 9, potential);
    }

    winningSequences.clear();

    for (var seq in potential) {
      int firstChipIdx = seq.firstWhere(
        (idx) => !cornerIndices.contains(idx),
        orElse: () => -1,
      );
      if (firstChipIdx == -1) continue;

      int ownerValue = boardState[firstChipIdx];
      if (ownerValue == 0) continue;

      // Fix for overlapping sequences
      bool isDistinct = true;
      for (var existingSeq in winningSequences) {
        int sharedCount = 0;
        for (int idx in seq) {
          if (existingSeq.contains(idx)) {
            sharedCount++;
          }
        }
        if (sharedCount > 1) {
          isDistinct = false;
          break;
        }
      }

      if (isDistinct) {
        winningSequences.add(seq);
        teamSequences[ownerValue] = (teamSequences[ownerValue] ?? 0) + 1;
      }
    }

    teamSequences.forEach((owner, count) {
      if (count >= winTarget && !isGameOver) {
        _triggerVictory(owner);
      }
    });
  }

  int _getWinnerIndex(int winnerValue) {
    if (!widget.isOnline) {
      // Offline: 0 is Player (Val 1), 1 is Bot (Val 2)
      return (winnerValue == 1) ? 0 : 1;
    }
    // Online: Iterate slots to find who holds this chip value
    for (int i = 0; i < widget.playerCount; i++) {
      if (_getPlayerChipValue(i) == winnerValue) return i;
    }
    return 0; // Fallback
  }

  void _triggerVictory(int winnerValue) {
    if (isGameOver) return;

    setState(() {
      isGameOver = true;
      _turnTimer?.cancel();
      winningPlayerIndex = _getWinnerIndex(winnerValue);
    });

    bool iWon = (myPlayerValue == winnerValue);

    if (iWon) {
      _confettiController.play();
      SoundManager.play('win');
    } else {
      SoundManager.play('fail');
    }

    _recordGameResult(won: iWon);
    // Dialog removed. Confetti and Blur/Exit button handle the end state.
  }

  void _checkLine(int start, int step, List<List<int>> target) {
    List<int> curr = [];
    int? owner;
    for (int k = 0; k < 5; k++) {
      int idx = start + (k * step);
      int bOwner = boardState[idx];
      if (cornerIndices.contains(idx)) {
        curr.add(idx);
        continue;
      }
      if (bOwner == 0) return;
      if (owner == null)
        owner = bOwner;
      else if (bOwner != owner)
        return;
      curr.add(idx);
    }
    target.add(curr);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOnline && isLoading) return _buildSearchScreen();

    return Scaffold(
      backgroundColor: Colors.transparent,

      body: LayoutBuilder(
        builder: (context, constraints) {
          double screenH = constraints.maxHeight;
          double screenW = constraints.maxWidth;

          return AnimatedContainer(
            duration: const Duration(seconds: 1),
            color: isSuddenDeath
                ? const Color(0xFF350505)
                : const Color(0xFF151515),
            child: SafeArea(
              child: Stack(
                children: [
                  ...particles.map(
                    (p) => Positioned(
                      left: p.pos.dx,
                      top: p.pos.dy,
                      child: Opacity(
                        opacity: p.life,
                        child: Container(
                          width: 4,
                          height: 4,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      _buildGameHeader(),
                      if (!widget.isOnline) _buildAiHand(),
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 0.70,
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              child: GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 10,
                                      childAspectRatio: 0.70,
                                      crossAxisSpacing: 2,
                                      mainAxisSpacing: 2,
                                    ),
                                itemCount: 100,
                                itemBuilder: (context, index) =>
                                    _buildBoardSquare(index),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: screenH * 0.15),
                    ],
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IconButton(
                      icon: const Icon(
                        Icons.logout,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: _handleExit,
                    ),
                  ),

                  // Fanned Hand Area with Blur Overlay if Game Over
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: screenH * 0.22,
                    child: Stack(
                      children: [
                        GestureDetector(
                          onPanUpdate: (details) => setState(
                            () => hoverPosition = details.localPosition,
                          ),
                          onPanEnd: (_) => setState(() => hoverPosition = null),
                          child: _buildFannedHand(),
                        ),

                        // NEW: Blur Overlay and Exit Button on Game Over
                        if (isGameOver)
                          Positioned.fill(
                            child: ClipRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  color: Colors.black.withOpacity(0.4),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        (winningPlayerIndex != null &&
                                                ((!widget.isOnline &&
                                                        winningPlayerIndex ==
                                                            0) ||
                                                    (widget.isOnline &&
                                                        winningPlayerIndex ==
                                                            int.parse(
                                                              _onlineService
                                                                      ?.myRole
                                                                      .split(
                                                                        '_',
                                                                      )
                                                                      .last ??
                                                                  "0",
                                                            ))))
                                            ? "VICTORY!"
                                            : "DEFEAT",
                                        style: TextStyle(
                                          color:
                                              (winningPlayerIndex != null &&
                                                  ((!widget.isOnline &&
                                                          winningPlayerIndex ==
                                                              0) ||
                                                      (widget.isOnline &&
                                                          winningPlayerIndex ==
                                                              int.parse(
                                                                _onlineService
                                                                        ?.myRole
                                                                        .split(
                                                                          '_',
                                                                        )
                                                                        .last ??
                                                                    "0",
                                                              ))))
                                              ? Colors.amber
                                              : Colors.redAccent,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 32,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.pop(
                                            context,
                                          ); // Go back to Menu
                                          _onlineService?.leaveGame();
                                        },
                                        child: const Text(
                                          "EXIT MATCH",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Positioned(
                    right: 20,
                    bottom: screenH * 0.12,
                    child: _buildDecks(),
                  ),
                  if (aiCursorPosition != null)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOutCirc,
                      left: aiCursorPosition!.dx - 12,
                      top: aiCursorPosition!.dy - 12,
                      child: Opacity(
                        opacity: 0.6,
                        child: _buildChipWidget(aiChip),
                      ),
                    ),

                  Positioned(
                    bottom: 110,
                    left: 16,
                    child: Column(
                      children: [
                        if (isSoundBoardOpen) _buildSoundBoardOverlay(),
                        const SizedBox(height: 10),
                        FloatingActionButton(
                          mini: true,
                          backgroundColor: Colors.white10,
                          child: Icon(
                            isSoundPlaying ? Icons.volume_up : Icons.music_note,
                            color: isSoundPlaying
                                ? Colors.amber
                                : Colors.white70,
                          ),
                          onPressed: () => setState(
                            () => isSoundBoardOpen = !isSoundBoardOpen,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (widget.isOnline)
                    Positioned(
                      top: 70,
                      right: 16,
                      child: IconButton(
                        icon: Icon(
                          isChatOpen ? Icons.close : Icons.chat_bubble,
                          color: Colors.white70,
                        ),
                        onPressed: () =>
                            setState(() => isChatOpen = !isChatOpen),
                      ),
                    ),
                  if (isChatOpen) _buildChatOverlay(),

                  if (_isOpponentOffline && !isGameOver)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              "OPPONENT RECONNECTING...",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const Text(
                              "Waiting for a stable connection",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSoundBoardOverlay() {
    final Map<String, String> friendlyNames = {
      "comment1.mp3": "Bruh!",
      "comment2.mp3": "Fuck",
      "comment3.mp3": "Among Us",
      "comment4.mp3": "Get out",
      "comment5.mp3": "Dun Dunn Dunnnnnn",
      "comment6.mp3": "Fart",
      "error.mp3": "Buzzer",
      "fail.mp3": "Spongbob",
      "win2.mp3": "Yaaaaa!",
    };

    return Container(
      height: 200,
      width: 120,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: soundBoardFiles.length,
        separatorBuilder: (c, i) =>
        const Divider(color: Colors.white10, height: 1),
        itemBuilder: (c, i) {
          String fileName = soundBoardFiles[i];

          // 1. Determine the name to show
          String displayName = friendlyNames[fileName] ??
              fileName.split('.').first.toUpperCase();

          return GestureDetector(
            onTap: () {
              setState(() {
                isSoundPlaying = true;
                isSoundBoardOpen = false;
              });
              SoundManager.play(fileName);
              if (widget.isOnline) _onlineService?.sendSound(fileName);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => isSoundPlaying = false);
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                // 2. FIX: Use 'displayName' here, not 'fileName'
                displayName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatOverlay() {
    return Positioned(
      bottom: 160,
      left: 16,
      right: 16,
      child: Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[messages.length - 1 - index];
                  bool isMe =
                      msg['sender'] == FirebaseAuth.instance.currentUser?.uid;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Colors.blueAccent.withOpacity(0.3)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        msg['text'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(color: Colors.white10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: "Say something...",
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.send,
                    color: Colors.blueAccent,
                    size: 20,
                  ),
                  onPressed: () => _sendChatMessage(_chatController.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiHand() {
    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: opponentHand
            .map(
              (c) => AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isPlayerTurn ? 0.3 : 1.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _buildRealCard(
                    c,
                    width: 35,
                    height: 50,
                    isSelected: opponentSelectedCard == c,
                    rankSize: 8,
                    suitSize: 12,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDecks() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only the Discard Pile
        if (lastUsedCard != null)
          Transform.rotate(
            angle: 0.05,
            child: _buildRealCard(
              lastUsedCard!,
              width: 45,
              height: 60,
              rankSize: 14,
              suitSize: 24,
            ),
          )
        else
          Container(
            width: 55,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: const Center(
              child: Icon(Icons.history, color: Colors.white10),
            ),
          ),
        const SizedBox(height: 5),
        const Text(
          "DISCARD",
          style: TextStyle(
            color: Colors.white30,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildGameHeader() {
    int displayCount = widget.isOnline ? widget.playerCount : 2;
    double sw = MediaQuery.of(context).size.width;
    double slotWidth = sw / displayCount;

    Color indicatorColor = Colors.amber; // Default
    if (widget.isTeamMode && widget.playerCount == 4) {
      indicatorColor = (currentTurnIndex % 2 == 0)
          ? Colors.redAccent
          : Colors.blueAccent;
    }

    return Container(
      height: 65,
      color: const Color(0xFF252525),
      child: Stack(
        children: [
          // 1. DYNAMIC TIMER BAR (At the very top)
          Container(
            height: 3,
            width: sw * (_turnTimeRemaining / 60),
            color: _turnTimeRemaining < 10 ? Colors.red : indicatorColor,
          ),

          // 2. ANIMATED TURN INDICATOR (The shifting bar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            bottom: 0,
            left: currentTurnIndex * slotWidth,
            child: Container(
              height: 3,
              width: slotWidth,
              color: indicatorColor,
            ),
          ),

          // 3. PLAYER SLOTS
          Row(
            children: List.generate(displayCount, (index) {
              bool isCurrent = (currentTurnIndex == index);
              // NEW: Check if this player is the winner
              bool isWinner = isGameOver && (index == winningPlayerIndex);

              var p = playersInfo.length > index ? playersInfo[index] : null;

              // Resolve Avatar Data
              String avatarId =
                  p?['avatars'] ?? (index == 0 ? _avatarId : opponentAvatarId);
              AvatarItem avatar = allAvatars.firstWhere(
                (a) => a.id == avatarId,
                orElse: () => allAvatars[0],
              );

              bool isOffline = p?['status'] == 'offline';
              Color statusColor = isOffline ? Colors.red : Colors.greenAccent;

              String displayName =
                  p?['name'] ?? (index == 0 ? _myHandle : opponentName);

              return Expanded(
                child: Container(
                  // NEW: Green glow for the winner's slot
                  decoration: isWinner
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.greenAccent.withOpacity(0.1),
                              Colors.transparent,
                            ],
                          ),
                        )
                      : null,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Confetti specifically for the winner
                      if (isWinner)
                        ConfettiWidget(
                          confettiController: _confettiController,
                          blastDirection: pi / 2, // Down
                          emissionFrequency: 0.05,
                          numberOfParticles: 20,
                          gravity: 0.2,
                        ),

                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isCurrent)
                            Text(
                              "$_turnTimeRemaining",
                              style: TextStyle(
                                color: indicatorColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),

                          // AVATAR PULSE & CONNECTION STATUS
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              // IDEA 1: Avatar Pulse using TweenAnimationBuilder
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: 1.0,
                                  end: isCurrent ? 1.2 : 1.0,
                                ),
                                duration: const Duration(milliseconds: 500),
                                builder: (context, scale, child) {
                                  return Transform.scale(
                                    scale: scale,
                                    child: Container(
                                      decoration: isWinner
                                          ? BoxDecoration(
                                              shape: BoxShape.circle,
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Colors.greenAccent,
                                                  blurRadius: 20,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            )
                                          : null,
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: avatar.color
                                            .withOpacity(0.2),
                                        child: ClipOval(
                                          child: Image.asset(
                                            avatar.assetPath,
                                            width: 28,
                                            height: 28,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // IDEA 2: Connection Status Dot
                              if (widget.isOnline)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF252525),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 2),
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 10,
                              color: isWinner
                                  ? Colors.greenAccent
                                  : (isCurrent ? Colors.white : Colors.white38),
                              fontWeight: isWinner || isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              shadows: isWinner
                                  ? [
                                      const Shadow(
                                        color: Colors.greenAccent,
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFannedHand() {
    List<String> currentHand = widget.isOnline
        ? (allHands.isNotEmpty
              ? allHands[int.parse(_onlineService!.myRole.split('_').last)]
              : [])
        : playerHand;

    if (currentHand.isEmpty) return const SizedBox();

    double sw = MediaQuery.of(context).size.width;
    int sIdx = (selectedCard != null) ? currentHand.indexOf(selectedCard!) : -1;
    int totalCards = currentHand.length;

    double cardWidth = sw * 0.12; // Dynamic width (12% of screen)
    double cardHeight = cardWidth * 1.5;
    double radius = sw * 0.6;
    double angleStep = 0.15;

    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: List.generate(totalCards, (i) {
        String c = currentHand[i];
        bool isS = (i == sIdx);

        double relativeIndex = i - (totalCards - 1) / 2.0;
        double angle = relativeIndex * angleStep;
        double xOffset = radius * sin(angle);
        double yOffset = radius * (1 - cos(angle));
        double lift = isS ? 40 : 0;

        return AnimatedPositioned(
          // FIXED: Added index to key to ensure uniqueness even if card is duplicate
          key: ValueKey("fan_card_${c}_$i"),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          left: (sw / 2) + xOffset - (cardWidth / 2),
          bottom: 30 + lift - yOffset,
          child: Transform.rotate(
            angle: angle,
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {
                if (isPlayerTurn) setState(() => selectedCard = isS ? null : c);
              },
              child: _buildRealCard(
                c,
                width: cardWidth,
                height: cardHeight,
                isSelected: isS,
                rankSize: cardWidth * 0.25,
                suitSize: cardWidth * 0.4,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildRealCard(
    String c, {
    double width = 50,
    double height = 70,
    bool isSelected = false,
    double suitSize = 26,
    double rankSize = 14,
    bool isBurning = false,
  }) {
    if (c == "" || c == "CORNER") return const SizedBox();
    bool isRed = c.contains('H') || c.contains('D');
    String suit = c.contains('H')
        ? "♥"
        : c.contains('D')
        ? "♦"
        : c.contains('C')
        ? "♣"
        : "♠";
    String rank = c.substring(0, c.length - 1);
    bool isGF = totalCoins > 5000 && c.contains('J');
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isBurning
            ? Colors.grey[800]
            : (isGF ? Colors.amber[50] : Colors.white),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected
              ? Colors.amber
              : (isGF ? Colors.amberAccent : Colors.grey[400]!),
          width: isSelected ? 3 : (isGF ? 2 : 1),
        ),
        boxShadow: [
          if (isSelected)
            BoxShadow(
              color: isGF ? Colors.amber : Colors.black.withOpacity(0.5),
              blurRadius: 15,
              offset: const Offset(10, 10),
            ),
          const BoxShadow(
            color: Colors.black26,
            blurRadius: 2,
            offset: Offset(1, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            left: 6,
            child: Column(
              children: [
                Text(
                  rank,
                  style: TextStyle(
                    color: isRed ? Colors.red[800] : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: rankSize,
                  ),
                ),
                Text(
                  suit,
                  style: TextStyle(
                    color: isRed ? Colors.red[800] : Colors.black,
                    fontSize: rankSize - 4,
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Text(
              suit,
              style: TextStyle(
                color: isRed ? Colors.red[800] : Colors.black,
                fontSize: suitSize * 0.6,
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            right: 6,
            child: RotatedBox(
              quarterTurns: 2,
              child: Column(
                children: [
                  Text(
                    rank,
                    style: TextStyle(
                      color: isRed ? Colors.red[800] : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: rankSize,
                    ),
                  ),
                  Text(
                    suit,
                    style: TextStyle(
                      color: isRed ? Colors.red[800] : Colors.black,
                      fontSize: rankSize - 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isGF)
            AnimatedBuilder(
              animation: _textPulseController,
              builder: (context, child) => Opacity(
                opacity: 0.1 * _textPulseController.value,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.amberAccent),
                ),
              ),
            ),

          if (isBurning)
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.redAccent,
                  size: 40,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChipWidget(GameChip chip, {int? lastIndex}) {
    bool isShim = shimmeringIndices.contains(lastIndex);
    // UI FIX: Check if this chip is part of a sequence
    bool isLocked = lastIndex != null && _isChipLocked(lastIndex);

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: chip.color,
        shape: BoxShape.circle,
        // UI FIX: Golden border for locked chips
        border: isLocked
            ? Border.all(color: Colors.amber, width: 3.0)
            : (lastPlacedChipIndex != null && lastPlacedChipIndex == lastIndex)
            ? Border.all(color: Colors.white, width: 2)
            : Border.all(color: Colors.black12, width: 1),
        boxShadow: [
          if (isShim || isLocked) // Add glow for locked chips too
            BoxShadow(
              color: Colors.amberAccent.withOpacity(isLocked ? 0.5 : 1.0),
              blurRadius: 12,
              spreadRadius: isLocked ? 2 : 4,
            ),
          const BoxShadow(
            color: Colors.black45,
            blurRadius: 4,
            offset: Offset(1, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          chip.icon,
          size: 16,
          color: (isShim || isLocked) ? Colors.amber : Colors.white,
        ),
      ),
    );
  }

  Widget _buildBoardSquare(int index) {
    String c = boardLayout[index];
    int ownerValue = boardState[index];
    bool isC = cornerIndices.contains(index);
    bool isPartnerHovering = index == _partnerHoverIndex;

    return MouseRegion(
      // Optional: to detect local hovers to send to partner
      onEnter: (_) => _onlineService?.sendHover(index),
      onExit: (_) => _onlineService?.sendHover(null),
      child: GestureDetector(
        onTap: () => _onBoardTap(index),
        child: Container(
          decoration: BoxDecoration(
            color: isC ? const Color(0xFF222222) : Colors.transparent,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!isC)
                _buildRealCard(
                  c,
                  width: sw * 0.1,
                  height: sw * 0.15,
                  rankSize: 10,
                  suitSize: 14,
                ),
              if (isC) const Icon(Icons.stars, size: 24, color: Colors.amber),

              // 1. Show the permanent chip if it exists
              if (ownerValue != 0)
                _buildChipWidget(
                  _getChipForValue(ownerValue),
                  lastIndex: index,
                ),

              // 2. NEW: Show the faint "Ghost Chip" for partner hover
              if (ownerValue == 0 && isPartnerHovering && widget.isTeamMode)
                Opacity(
                  opacity: 0.3,
                  child: _buildChipWidget(
                    myChip,
                  ), // Use your chip color for your partner
                ),
            ],
          ),
        ),
      ),
    );
  }

  GameChip _getChipForValue(int value) {
    if (value == myPlayerValue) return myChip;
    // Map value to a fallback from allGameChips based on its ID
    if (value == 1) return allGameChips[2]; // Ruby Red
    if (value == 2) return allGameChips[0]; // Classic Blue
    return allGameChips[6]; // Toxic Green
  }

  Widget _buildSearchScreen() {
    String modeTitle = widget.playerCount == 3
        ? "TRIPLE THREAT"
        : (widget.isTeamMode ? "2 v 2 TEAM BATTLE" : "1 v 1 DUEL");

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              modeTitle,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "WAITING FOR PLAYERS (${playersInfo.length}/${widget.playerCount})",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 50),

            // LOBBY SLOTS
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.playerCount, (index) {
                bool isFilled = playersInfo.length > index;
                var p = isFilled ? playersInfo[index] : null;

                AvatarItem? avatar;
                if (isFilled) {
                  avatar = allAvatars.firstWhere(
                    (a) => a.id == p!['avatars'],
                    orElse: () => allAvatars[0],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Slot Background
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isFilled
                                    ? (avatar?.color ?? Colors.blue)
                                    : Colors.white10,
                                width: 2,
                              ),
                              color: isFilled
                                  ? (avatar?.color.withOpacity(0.1))
                                  : Colors.black26,
                            ),
                            // UPDATED
                            child: isFilled
                                ? Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: ClipOval(
                                child: Image.asset(
                                  avatar!.assetPath,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                                : const Icon(
                              Icons.person_outline,
                              size: 30,
                              color: Colors.white10,
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isFilled ? p!['name'] : "Empty...",
                        style: TextStyle(
                          color: isFilled ? Colors.white : Colors.white24,
                          fontSize: 11,
                          fontWeight: isFilled
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (isFilled && index == 0)
                        const Text(
                          "HOST",
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),

            const SizedBox(height: 60),
            if (_showAddBotButton && _onlineService?.myRole == "player_0")
              CupertinoButton(
                color: Colors.orangeAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                onPressed: () =>
                    _onlineService?.fillWithBots(widget.playerCount),
                child: const Text(
                  "FILL WITH BOTS",
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const CircularProgressIndicator(
                color: Colors.cyanAccent,
                strokeWidth: 2,
              ),

            const SizedBox(height: 40),
            CupertinoButton(
              onPressed: _cancelSearch,
              child: const Text(
                "CANCEL",
                style: TextStyle(color: Colors.redAccent, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, color: Colors.greenAccent, size: 8),
              const SizedBox(width: 8),
              Text(
                "$playersOnline Players Online",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "$playersSearching Looking for match",
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 10),
          ),
        ],
      ),
    );
  }

  double get sw => MediaQuery.of(context).size.width;
}

class _AshParticle {
  Offset pos;
  double life = 1.0;
  final double vx = (Random().nextDouble() - 0.5) * 4;
  final double vy = -Random().nextDouble() * 5;
  _AshParticle(this.pos);
  void update() {
    pos = Offset(pos.dx + vx, pos.dy + vy);
    life -= 0.02;
  }
}
