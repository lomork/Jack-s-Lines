import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

enum NotificationType { friendRequest, gameInvite, system }

class GameNotification {
  final String id;
  final String fromId;
  final String fromName;
  final String type;
  final int timestamp;
  final Map<dynamic, dynamic>? payload;

  GameNotification({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.type,
    required this.timestamp,
    this.payload,
  });

  factory GameNotification.fromMap(String id, Map<dynamic, dynamic> map) {
    return GameNotification(
      id: id,
      fromId: map['fromId'] ?? '',
      fromName: map['fromName'] ?? 'Someone',
      type: map['type'] ?? 'system',
      timestamp: map['timestamp'] ?? 0,
      payload: map['payload'] as Map<dynamic, dynamic>?,
    );
  }
}

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;
  NotificationManager._internal();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription? _notifSubscription;

  final List<GameNotification> _notifications = [];
  List<GameNotification> get notifications => List.unmodifiable(_notifications);

  // Callback for UI updates
  Function? onNotificationUpdate;

  void init() {
    final user = _auth.currentUser;
    if (user == null) return;

    _notifSubscription?.cancel();
    _notifSubscription = _db.child('notifications/${user.uid}').onValue.listen((event) {
      _notifications.clear();
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        data.forEach((key, value) {
          _notifications.add(GameNotification.fromMap(key, value));
        });
        // Sort newest first
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      onNotificationUpdate?.call();
    });
  }

  Future<void> sendFriendRequest(String targetUid, String myName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.child('notifications/$targetUid').push().set({
      'fromId': user.uid,
      'fromName': myName,
      'type': 'friendRequest',
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> sendGameInvite(String targetUid, String myName, String gameId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.child('notifications/$targetUid').push().set({
      'fromId': user.uid,
      'fromName': myName,
      'type': 'gameInvite',
      'timestamp': ServerValue.timestamp,
      'payload': {'gameId': gameId},
    });
  }

  Future<void> dismissNotification(String notifId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.child('notifications/${user.uid}/$notifId').remove();
  }

  void dispose() {
    _notifSubscription?.cancel();
  }
}