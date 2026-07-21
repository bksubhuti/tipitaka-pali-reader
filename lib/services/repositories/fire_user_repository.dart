import 'package:firedart/auth/user_gateway.dart';
import 'package:flutter/material.dart';
import 'package:firedart/firedart.dart';
import '../../../env/env.dart';
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
      Prefs.isSignedIn = false;
      Prefs.email = "";
      Prefs.password = "";
      //rethrow; // Optionally rethrow to handle the error on the UI side.
    }
  }

  Future<bool> signIn(String email, String password) async {
    try {
      const projectId = "tipitaka-pali-reader-firestore";
      final apiKey = Env.firebaseApiKey;

      if (!FirebaseAuth.initialized) {
        // ensure the app is initialized.
        FirebaseAuth.initialize(apiKey!, VolatileStore());
        Firestore.initialize(projectId);
      }

      var auth = FirebaseAuth.instance;
      await auth.signIn(email, password);
      debugPrint('Successfully signed in!');

      // Check if user's email is verified
      User user = await auth.getUser();
      if (!(user.emailVerified ?? false)) {
        await sendUserVerificationRequest(); // Resend verification email
        throw Exception('Email_not_verified');
      }

      Prefs.email = email;
      Prefs.password = password;
      notifier.setSignedIn(true);
      notifier.message = "Successfully Signed in";
      return true;
    } catch (e) {
      notifier.setSignedIn(false);
      notifier.message = e.toString();
      debugPrint('Error during sign-in: $e');
      rethrow;
    }
  }

  Future<void> register(String email, String password) async {
    try {
      var auth = FirebaseAuth.instance;
      await auth.signUp(email, password);
      // need to send automatic verification
      await sendUserVerificationRequest();

      debugPrint('Successfully registered!');
      Prefs.email = "";
      Prefs.password = "";
    } catch (e) {
      debugPrint('Error during registration: $e');
      rethrow; // Optionally rethrow to handle the error on the UI side.
    }
  }

  resetPassword(String userEmail) async {
    var auth = FirebaseAuth.instance;
    await auth.resetPassword(userEmail);
  }

  // Function to send a verification email
  Future<void> sendUserVerificationRequest() async {
    try {
      var auth = FirebaseAuth.instance;
      if (auth.isSignedIn) {
        await auth.requestEmailVerification();
        debugPrint('Verification email sent!');
      }
    } catch (e) {
      debugPrint('Error during email verification request: $e');
      rethrow;
    }
  }

  // Function to check if the user's email is verified
  Future<bool> isVerified() async {
    try {
      var auth = FirebaseAuth.instance;
      if (auth.isSignedIn) {
        User user = await auth.getUser();
        return user.emailVerified ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('Error during email verification check: $e');
      rethrow;
    }
  }
}
