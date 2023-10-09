import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firedart/firedart.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/user_notifier.dart';

class FireUserRepository {
  FireUserRepository({required this.notifier});
  UserNotifier notifier;

  get isSignedIn => FirebaseAuth.instance.isSignedIn;
  get isSignedOut => !FirebaseAuth.instance.isSignedIn;
  // Ensure user is signed in before any operation
  Future<void> ensureSignedIn() async {
    if (FirebaseAuth.instance.isSignedIn) return;

    await signIn(Prefs.email, Prefs.password);
  }

  Future<void> signOut() async {
    try {
      var auth = FirebaseAuth.instance;
      auth.signOut();
      debugPrint('Successfully signed out!');
      Prefs.isSignedIn = false;
      Prefs.email = "";
      Prefs.password = "";
      notifier.setSignedIn(false);
    } catch (e) {
      debugPrint('Error during sign-out: $e');
      throw e; // Optionally rethrow to handle the error on the UI side.
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      var auth = FirebaseAuth.instance;
      await auth.signIn(email, password);
      debugPrint('Successfully signed in!');
      Prefs.email = email;
      Prefs.password = password;
      notifier.setSignedIn(true);
      notifier.message = "SUccessfully Signed in";
      return Prefs.isSignedIn;
    } catch (e) {
      notifier.setSignedIn(false);
      notifier.message = e.toString();

      debugPrint('Error during sign-in: $e');
      throw e; // Optionally rethrow to handle the error on the UI side.
    }
  }

  Future<void> register(String email, String password) async {
    try {
      var auth = FirebaseAuth.instance;
      Random random = Random();
      //generate a password that is different from the one they want to use
      // so they can use it again when they reset
      await auth.signUp(email, "$password${random.nextInt(1000)}");

      debugPrint('Successfully registered!');
      Prefs.email = "";
      Prefs.password = "";
    } catch (e) {
      debugPrint('Error during registration: $e');
      throw e; // Optionally rethrow to handle the error on the UI side.
    }
  }
}