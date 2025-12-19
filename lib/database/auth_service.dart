import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final GoogleSignIn _googleSignIn = GoogleSignIn(); // Google Provider

  // 1. GOOGLE LOGIN (NEW)
  Future<User?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User canceled

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google User
      UserCredential result = await _auth.signInWithCredential(credential);

      // Create/Sync User Data
      // We use the Google Display Name as the handle initially
      await _initializeUserData(result.user!, handle: googleUser.displayName);

      return result.user;
    } catch (e) {
      print("Google Sign-In Error: $e");
      return null;
    }
  }

  // 2. GUEST LOGIN
  Future<User?> signInGuest() async {
    try {
      UserCredential result = await _auth.signInAnonymously();
      await _initializeUserData(result.user!, isGuest: true);
      return result.user;
    } catch (e) {
      print("Guest Error: $e");
      return null;
    }
  }

  // 3. REGISTER (Email)
  Future<User?> register(String email, String password, String handle) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await _initializeUserData(result.user!, handle: handle);
      return result.user;
    } catch (e) {
      print("Register Error: $e");
      return null;
    }
  }

  // 4. LOGIN (Email)
  Future<User?> login(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      await _syncCloudToLocal(result.user!.uid);
      return result.user;
    } catch (e) {
      print("Login Error: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut(); // Sign out of Google too
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // --- DATABASE SETUP ---
  Future<void> _initializeUserData(User user, {String? handle, bool isGuest = false}) async {
    final prefs = await SharedPreferences.getInstance();

    // Generate Unique ID
    String uniqueId = "#${Random().nextInt(900000) + 100000}";
    // Logic: If handle is null, use Guest_ID. If Google gives a name, use it.
    String finalHandle = handle ?? (isGuest ? "Guest_${uniqueId.substring(1)}" : "Player");

    final snapshot = await _db.child('users/${user.uid}').get();

    if (!snapshot.exists) {
      // Create new entry
      Map<String, dynamic> initialData = {
        'uid': user.uid,
        'handle': finalHandle,
        'unique_id': uniqueId,
        'email': user.email ?? "guest",
        'coins': 1000,
        'lives': 5,
        'matches_played': 0,
        'matches_won': 0,
        'streak': 0,
        'national_rank': 9999,
        'owned_chips': ['default_blue'],
        'chips_purchased': 0,
        'created_at': DateTime.now().toIso8601String(),
        'match_history': []
      };

      await _db.child('users/${user.uid}').set(initialData);

      // Save Local
      await prefs.setString('unique_handle', finalHandle);
      await prefs.setString('unique_id', uniqueId);
      await prefs.setInt('user_coins', 1000);
    } else {
      await _syncCloudToLocal(user.uid);
    }
  }

  Future<void> _syncCloudToLocal(String uid) async {
    final snapshot = await _db.child('users/$uid').get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('unique_handle', data['handle']);
      await prefs.setString('unique_id', data['unique_id']);
      await prefs.setInt('user_coins', data['coins']);
    }
  }
}