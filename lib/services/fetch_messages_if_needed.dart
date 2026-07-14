import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/tpr_message.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/get_database_status.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

Future<bool> _isInternetAvailable() async {
  return await InternetConnection().hasInternetAccess;
}

/// Checks whether the Abhidhammatthasangaha (annya_bi_05) DB fix is needed.
/// Returns true if extra pages exist and need to be removed.
/// Does NOT perform the fix — the caller should prompt the user first.
Future<bool> checkSangahaFixNeeded() async {
  if (Prefs.sangahaFixed) return false;

  try {
    final db = await DatabaseHelper().database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM pages WHERE bookid = 'annya_bi_05' AND page = 69",
    );
    final count = result.first['cnt'] as int;
    return count > 0;
  } catch (e) {
    debugPrint('SangahaFix: error checking — $e');
    return false;
  }
}

/// Runs all one-time startup checks and fetches the daily message.
Future<TprMessage> generalStartupChecks() async {

  DateTime currentDate = DateTime.now();
  String formattedCurrentDate =
      "${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}";

  // separate logic for each instead of combining
  // to make easier.  Sending constructor sends empty message
  // no display

  // don't show on first time updating database
  DatabaseStatus databaseStatus = getDatabaseStatus();
  if (databaseStatus != DatabaseStatus.uptoDate) {
    return TprMessage();
  }

  // user settings Don't Show Whats new
  if (!Prefs.showWhatsNew) {
    return TprMessage();
  }

  // only fetch one time per day
  // Check if the message has already been fetched today
  DateTime lastCheckedDate = DateTime.parse(Prefs.lastDateCheckedMessage);
  if (lastCheckedDate.year == currentDate.year &&
      lastCheckedDate.month == currentDate.month &&
      lastCheckedDate.day == currentDate.day) {
    // Message was already fetched today
    return TprMessage();
  }

  // If there is no internet, use the stored message.
  // no need to prompt.. be silent
  if (!await _isInternetAvailable()) {
    return TprMessage();
  }

  // Fetch the message from the internet
  // and see if we should display
  try {
    final response = await http.get(Uri.parse(
        'https://github.com/bksubhuti/tipitaka-pali-reader/raw/master/messages.json'));

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);

      // get the data into the message
      TprMessage newMessage = TprMessage.fromJson(data);

      // because we went online write the date
      Prefs.lastDateCheckedMessage = formattedCurrentDate;

      // message the same?  no need to display
      if (Prefs.message == newMessage.generalMessage) {
        //return empty
        return TprMessage();
      }
      // Store the fetched message and date for comparing later
      Prefs.message = newMessage.generalMessage;

      // ...rest of your logic, like storing messages or comparing dates...

      return newMessage; // return the object
    } else {
      debugPrint('Failed to load message');
      return TprMessage();
    }
  } catch (e) {
    return TprMessage();
  }
}

