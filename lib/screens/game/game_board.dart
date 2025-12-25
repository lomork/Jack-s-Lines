import 'dart:async';
import 'dart:math';
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
  final bool isOnline;
  final String? chipId;
  const GameBoard({
    super.key,
    this.difficulty = "Easy",
    this.isOnline = false,
    this.chipId,
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
  String opponentAvatarId = "avatar_1";
  String opponentFlag = "🤖";
  int totalCoins = 0;

  List<String> deck = [];
  final List<String> playerHand = [];
  final List<String> opponentHand = [];
  final List<int> boardState = List.filled(100, 0);
  List<String> boardLayout = [];
  final Set<int> cornerIndices = {0, 9, 90, 99};

  List<Map<String, dynamic>> moveLog = [];

  // Win Logic
  bool isPlayerTurn = true;
  bool isGameOver = false;
  bool isSuddenDeath = false;
  List<List<int>> winningSequences = [];
  late String currentAiDifficulty;

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
    "card_shuffle.mp3",
    "click.mp3",
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
    if (mounted) {
      setState(() {
        totalCoins = coins;
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

    int xpGain = won ? 20 : 5;
    if (won) {
      wins += 1;
      currentXp += xpGain;
      await prefs.setInt('total_wins', wins);
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
      await dbRef.update({
        'total_wins': wins,
        'total_losses': losses,
        'total_matches': totalMatches,
        'xp': currentXp,
      });
      dbRef.child('matches').push().set({
        'result': won ? 'win' : 'loss',
        'mode': widget.isOnline ? 'Online' : 'Offline',
        'xp_gain': xpGain,
        'timestamp': ServerValue.timestamp,
        'opponent_name': opponentName,
        'board_snapshot': boardState.join(','),
      });
    }
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

  Future<void> _checkForDeadCards() async {
    List<String> deadCards = [];
    for (String card in playerHand) {
      if (card.contains('J')) continue;
      List<int> pos = [];
      for (int i = 0; i < boardLayout.length; i++)
        if (boardLayout[i] == card) pos.add(i);
      if (pos.isNotEmpty && pos.every((idx) => boardState[idx] != 0))
        deadCards.add(card);
    }
    if (deadCards.isNotEmpty) {
      setState(() => burningCards.addAll(deadCards));
      HapticFeedback.heavyImpact();
      for (int i = 0; i < 20; i++)
        particles.add(
          _AshParticle(Offset(MediaQuery.of(context).size.width / 2, 600)),
        );
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() {
        for (String dead in deadCards) {
          playerHand.remove(dead);
          playerHand.add(_drawCard(isPlayer: true));
        }
        burningCards.clear();
      });
    }
  }

  void _handleTimeout() {
    _turnTimer?.cancel();
    if (isGameOver) return;
    bool iLost = isPlayerTurn;
    isGameOver = true;
    _recordGameResult(won: !iLost);
    _showGameOverDialog(!iLost, isTimeout: true);
  }

  void _handleExit() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          "Quit Game?",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Leaving now counts as a LOSS. Opponent wins by forfeit.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _recordGameResult(won: false);
              _onlineService?.sendForfeit();
              _onlineService?.leaveGame();
              Navigator.pop(context);
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
      if (data['status'] == 'forfeit' && !isGameOver) {
        isGameOver = true;
        _turnTimer?.cancel();
        _recordGameResult(won: true);
        _showOpponentLeftDialog();
        return;
      }
      if (data['status'] == 'playing') {
        if (isLoading) {
          SoundManager.play('click');
          _avatarReactionController.forward().then(
            (_) => _avatarReactionController.reverse(),
          );
        }

        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          _stopSearchAnimation();
          String myRole = _onlineService!.myRole;
          int newPlayerValue = (myRole == 'host') ? 1 : 2;
          setState(() {
            isLoading = false;
            myPlayerValue = newPlayerValue;
            bool wasPlayerTurn = isPlayerTurn;
            isPlayerTurn = (data['turn'] == myRole);
            if (wasPlayerTurn != isPlayerTurn) _startTurnTimer();
            if (myRole == 'host') {
              opponentAvatarId = data['guest_avatar'] ?? "avatar_1";
              opponentName = data['guest_name'] ?? "Guest";
              aiChip = allGameChips.firstWhere(
                (c) => c.id == (data['guest_chip_id'] ?? "default_red"),
                orElse: () => allGameChips[0],
              );
            } else {
              opponentAvatarId = data['host_avatar'] ?? "avatar_1";
              opponentName = data['host_name'] ?? "Host";
              aiChip = allGameChips.firstWhere(
                (c) => c.id == (data['host_chip_id'] ?? "default_blue"),
                orElse: () => allGameChips[1],
              );
            }
            if (data['board'] != null) {
              List<dynamic> cloudBoard = data['board'];
              for (int i = 0; i < 100; i++)
                if (cloudBoard[i] is int) boardState[i] = cloudBoard[i];
            }
            if (data['last_move'] != null) {
              lastPlacedChipIndex = data['last_move']['index'];
              if (data['last_move']['card'] != null)
                lastUsedCard = data['last_move']['card'];
            }
            checkForWin();
          });
          if (playerHand.isEmpty) {
            _dealInitialHands();
            _startTurnTimer();
          }
          _setupChatListener();
        });
      }
    };

    _onlineService!.onSoundReceived = (soundName) {
      if (!mounted) return;
      setState(() => isSoundPlaying = true);
      SoundManager.play(soundName);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => isSoundPlaying = false);
      });
    };

    await _onlineService!.findMatch(chipId: myChip.id);
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
    for (int i = 0; i < 7; i++) {
      playerHand.add(deck.removeLast());
      opponentHand.add(deck.removeLast());
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
    if (!isPlayerTurn || isGameOver || selectedCard == null) return;
    if (cornerIndices.contains(index)) return;
    String targetCard = boardLayout[index];
    bool isRedJack = selectedCard!.contains('H') || selectedCard!.contains('D');
    bool isBlackJack =
        selectedCard!.contains('C') || selectedCard!.contains('S');
    bool isJack = selectedCard!.contains('J');
    bool success = false;
    if (isJack) {
      if (isBlackJack) {
        if (boardState[index] == 0) success = true;
      } else if (isRedJack) {
        if (boardState[index] != 0 && boardState[index] != myPlayerValue) {
          if (!_isChipLocked(index)) {
            _executeMove(index, 0);
            return;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cannot remove sequence!")),
            );
            return;
          }
        }
      }
    } else {
      if (targetCard == selectedCard && boardState[index] == 0) success = true;
    }
    if (success) _executeMove(index, myPlayerValue);
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

  void _finishTurn({required bool isPlayer}) {
    checkForWin();
    if (isGameOver) return;
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
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    AiMove? move = AiLogic.findBestMove(
      opponentHand,
      boardState,
      boardLayout,
      currentAiDifficulty,
      2,
    );
    if (move != null) {
      Offset target = _getBoardCellCenter(move.index);
      setState(() {
        opponentSelectedCard = move.cardUsed;
        aiCursorPosition = Offset(MediaQuery.of(context).size.width / 2, 40);
      });
      await Future.delayed(const Duration(milliseconds: 50));
      setState(() => aiCursorPosition = target);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() {
        if (move.isRemoval)
          boardState[move.index] = 0;
        else {
          boardState[move.index] = 2;
          lastPlacedChipIndex = move.index;
        }
        lastUsedCard = move.cardUsed;
        opponentHand.remove(move.cardUsed);
        opponentSelectedCard = null;
        aiCursorPosition = null;
        if (deck.isNotEmpty) opponentHand.add(deck.removeLast());
      });
    }
    _finishTurn(isPlayer: false);
  }

  void checkForWin() {
    List<List<int>> potential = [];
    for (int i = 0; i < 100; i++) {
      if (i % 10 <= 5) _checkLine(i, 1, potential);
      if (i < 60) _checkLine(i, 10, potential);
      if (i % 10 <= 5 && i < 60) _checkLine(i, 11, potential);
      if (i % 10 >= 4 && i < 60) _checkLine(i, 9, potential);
    }
    winningSequences.clear();
    Set<int> p1Used = {}, p2Used = {};
    int p1Count = 0, p2Count = 0;
    for (var seq in potential) {
      int owner = 0;
      for (int idx in seq)
        if (!cornerIndices.contains(idx)) {
          owner = boardState[idx];
          break;
        }
      if (owner == 0) continue;
      Set<int> target = (owner == 1) ? p1Used : p2Used;
      int overlap = 0;
      for (int idx in seq) if (target.contains(idx)) overlap++;
      if (overlap <= 1) {
        winningSequences.add(seq);
        target.addAll(seq);
        if (owner == 1)
          p1Count++;
        else
          p2Count++;
      }
    }
    if (p2Count == 1 &&
        widget.difficulty == "Hard" &&
        currentAiDifficulty == "Hard")
      setState(() {
        currentAiDifficulty = "Medium";
        opponentFlag = Random().nextBool() ? "😵" : "🥴";
      });
    if ((p1Count == 1 || p2Count == 1) && !isGameOver) {
      if (!isSuddenDeath) {
        setState(() => isSuddenDeath = true);
        HapticFeedback.heavyImpact();
      }
    }
    if (p1Count >= 2 || p2Count >= 2) {
      isGameOver = true;
      _turnTimer?.cancel();
      bool iWon =
          (myPlayerValue == 1 && p1Count >= 2) ||
          (myPlayerValue == 2 && p2Count >= 2);
      if (iWon && widget.isOnline) {
        setState(() {
          for (var seq in winningSequences) {
            bool mine = false;
            for (int idx in seq) {
              if (!cornerIndices.contains(idx)) {
                if (boardState[idx] == myPlayerValue) mine = true;
                break;
              }
            }
            if (mine) shimmeringIndices.addAll(seq);
          }
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => shimmeringIndices.clear());
        });
      }
      if (iWon) _confettiController.play();
      if (widget.isOnline)
        _onlineService?.recordGameEnd(won: iWon, opponentName: opponentName);
      _recordGameResult(won: iWon);
      _showGameOverDialog(iWon);
    }
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

  void _showOpponentLeftDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          "VICTORY!",
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Opponent left. Win by forfeit!",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("EXIT"),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog(bool iWon, {bool isTimeout = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(
          iWon ? "VICTORY!" : (isTimeout ? "TIME'S UP!" : "DEFEAT"),
          style: TextStyle(
            color: iWon ? Colors.amber : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("EXIT"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOnline && isLoading) return _buildSearchScreen();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedContainer(
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
                    child: Container(width: 4, height: 4, color: Colors.grey),
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
                  const SizedBox(height: 120),
                ],
              ),
              Positioned(
                bottom: -30,
                left: 0,
                right: 0,
                height: 160,
                child: GestureDetector(
                  onPanUpdate: (details) =>
                      setState(() => hoverPosition = details.localPosition),
                  onPanEnd: (_) => setState(() => hoverPosition = null),
                  child: _buildFannedHand(),
                ),
              ),
              Positioned(right: 16, bottom: 110, child: _buildDecks()),
              if (aiCursorPosition != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOutCirc,
                  left: aiCursorPosition!.dx - 12,
                  top: aiCursorPosition!.dy - 12,
                  child: Opacity(opacity: 0.6, child: _buildChipWidget(aiChip)),
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
                        color: isSoundPlaying ? Colors.amber : Colors.white70,
                      ),
                      onPressed: () =>
                          setState(() => isSoundBoardOpen = !isSoundBoardOpen),
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
                    onPressed: () => setState(() => isChatOpen = !isChatOpen),
                  ),
                ),
              if (isChatOpen) _buildChatOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSoundBoardOverlay() {
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
          String name = soundBoardFiles[i];
          return GestureDetector(
            onTap: () {
              setState(() {
                isSoundPlaying = true;
                isSoundBoardOpen = false;
              });
              SoundManager.play(name);
              if (widget.isOnline) _onlineService?.sendSound(name);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => isSoundPlaying = false);
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                name.toUpperCase(),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lastUsedCard != null)
          Transform.rotate(
            angle: 0.1,
            child: _buildRealCard(
              lastUsedCard!,
              width: 50,
              height: 70,
              rankSize: 12,
              suitSize: 22,
            ),
          )
        else
          Container(
            width: 50,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Text(
                "Discard",
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGameHeader() {
    AvatarItem opponent = getAvatarById(opponentAvatarId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _handleExit,
              ),
              const SizedBox(width: 5),
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: opponent.color,
                    child: Icon(opponent.icon, size: 20, color: Colors.white),
                  ),
                  if (!widget.isOnline)
                    Text(opponentFlag, style: const TextStyle(fontSize: 14)),
                ],
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opponentName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    isPlayerTurn ? "Waiting..." : "Playing",
                    style: TextStyle(
                      color: isPlayerTurn ? Colors.grey : Colors.greenAccent,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Text(
            "$_turnTimeRemaining",
            style: TextStyle(
              color: _turnTimeRemaining <= 10 ? Colors.red : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFannedHand() {
    if (playerHand.isEmpty) return const SizedBox();
    double sw = MediaQuery.of(context).size.width;
    if (selectedCard != null && !playerHand.contains(selectedCard))
      selectedCard = null;
    int sIdx = (selectedCard != null) ? playerHand.indexOf(selectedCard!) : -1;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: List.generate(playerHand.length, (i) {
        String c = playerHand[i];
        bool isS = (i == sIdx);
        bool isB = burningCards.contains(c);
        double rel = i - (playerHand.length - 1) / 2;
        double t = hoverPosition != null
            ? (hoverPosition!.dx - ((sw / 2) + (rel * 35))).clamp(-20, 20) *
                  0.005
            : 0.0;
        double x = rel * 35;
        if (sIdx != -1) {
          if (i < sIdx) x -= 25;
          if (i > sIdx) x += 25;
        }
        return AnimatedPositioned(
          key: ValueKey("c_$i"),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          left: (sw / 2) + x - 30,
          bottom: isS ? 65 : 50 - (rel * rel * 2.0),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 1000),
            scale: isB ? 0.0 : 1.0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 800),
              opacity: isB ? 0.0 : 1.0,
              child: Transform.rotate(
                angle: isS ? 0 : (rel * 0.08) + t,
                child: GestureDetector(
                  onTap: () {
                    if (isPlayerTurn && !isB)
                      setState(() => selectedCard = isS ? null : c);
                  },
                  child: _buildRealCard(
                    c,
                    width: 60,
                    height: 90,
                    isSelected: isS,
                    suitSize: 32,
                    rankSize: 18,
                    isBurning: isB,
                  ),
                ),
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
            ? Colors.black87
            : (isGF ? Colors.amber[50] : Colors.white),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected
              ? Colors.amber
              : (isGF ? Colors.amberAccent : Colors.grey[300]!),
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
        ],
      ),
    );
  }

  Widget _buildChipWidget(GameChip chip, {int? lastIndex}) {
    bool isShim = shimmeringIndices.contains(lastIndex);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: chip.color,
        shape: BoxShape.circle,
        border:
            (lastPlacedChipIndex != null && lastPlacedChipIndex == lastIndex)
            ? Border.all(color: Colors.white, width: 2)
            : Border.all(color: Colors.black12, width: 1),
        boxShadow: [
          if (isShim)
            const BoxShadow(
              color: Colors.amberAccent,
              blurRadius: 12,
              spreadRadius: 4,
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
          color: isShim ? Colors.amber : Colors.white,
        ),
      ),
    );
  }

  Widget _buildBoardSquare(int index) {
    String c = boardLayout[index];
    int owner = boardState[index];
    bool isC = cornerIndices.contains(index);
    return GestureDetector(
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
                isSelected: false,
                rankSize: 10,
                suitSize: 14,
              ),
            if (isC) const Icon(Icons.stars, size: 24, color: Colors.amber),
            if (owner != 0)
              _buildChipWidget(
                owner == myPlayerValue ? myChip : aiChip,
                lastIndex: index,
              ),
            for (var seq in winningSequences)
              if (seq.contains(index))
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.greenAccent, width: 3),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _textPulseController,
            builder: (context, child) => Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.blue.withOpacity(0.05 * _textPulseController.value),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.3).animate(
                  CurvedAnimation(
                    parent: _avatarReactionController,
                    curve: Curves.elasticOut,
                  ),
                ),
                child: const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white10,
                  child: Icon(Icons.person, size: 60, color: Colors.white30),
                ),
              ),
              const SizedBox(height: 30),
              RotationTransition(
                turns: _searchingRotateController,
                child: const Icon(
                  Icons.blur_circular,
                  color: Colors.cyanAccent,
                  size: 100,
                ),
              ),
              const SizedBox(height: 40),
              FadeTransition(
                opacity: Tween(
                  begin: 0.5,
                  end: 1.0,
                ).animate(_textPulseController),
                child: Text(
                  _statusMessages[_statusIndex],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "ETA: ${max(1, 20 - _seconds)}s",
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 40),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white10),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Text(
                    _proTips[_tipIndex],
                    key: ValueKey(_tipIndex),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              _buildOnlineStatus(),
              const SizedBox(height: 50),
              CupertinoButton(
                color: Colors.redAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(30),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 12,
                ),
                onPressed: _cancelSearch,
                child: const Text(
                  "CANCEL",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
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
