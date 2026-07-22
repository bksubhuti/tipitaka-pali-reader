import 'package:firedart/auth/firebase_auth.dart';
import 'package:firedart/auth/token_store.dart';
import 'package:firedart/firestore/firestore.dart';
import 'package:flutter/material.dart';
import '../../env/env.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:tipitaka_pali/services/prefs.dart';

setupFirestore() async {
  const projectId = "tipitaka-pali-reader-firestore";
  final apiKey = Env.firebaseApiKey;
  //check for internet connection

  if (await InternetConnection().hasInternetAccess) {
    FirebaseAuth.initialize(apiKey, VolatileStore());
    Firestore.initialize(projectId);
    if (Prefs.isSignedIn) {
      try {
        await FirebaseAuth.instance.signIn(Prefs.email, Prefs.password);
        Prefs.isSignedIn = true;
        debugPrint('login success');
      } catch (e) {
        Prefs.isSignedIn = false;
        debugPrint(e.toString());
      }
    }
  } else {
    Prefs.isSignedIn = false;
  }
}
