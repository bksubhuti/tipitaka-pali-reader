/*import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';

class WelcomeContainer extends StatefulWidget {
  @override
  _WelcomeContainerState createState() => _WelcomeContainerState();
}

class _WelcomeContainerState extends State<WelcomeContainer> {
  Future<String>? _messageFuture;

  @override
  void initState() {
    super.initState();
    _messageFuture = _fetchMessageIfNeeded();
  }

  Future<String> _fetchMessageIfNeeded() async {
    String? storedMessage = Prefs.message;
    String? storedMessageDate = Prefs.messageDate;
    DateTime currentDate = DateTime.now();
    String formattedCurrentDate =
        "${currentDate.year}${currentDate.month.toString().padLeft(2, '0')}${currentDate.day.toString().padLeft(2, '0')}";

    // If message date is same as today's date or there is no internet, use the stored message.
    if (storedMessageDate == formattedCurrentDate || !_isInternetAvailable()) {
      return storedMessage;
    }

    // Fetch the message from the internet
    try {
      final response = await http.get(Uri.parse(
          'https://cdn.jsdelivr.net/gh/bksubhuti/tipitaka-pali-reader@master/messages.json'));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String message = data['general']['message'];
        String messageDate = data['general']['messageDate'];

        // Store the fetched message and date
        Prefs.message = message;
        Prefs.messageDate = messageDate;

        return message;
      } else {
        throw Exception('Failed to load message');
      }
    } catch (e) {
      return "Error fetching message";
    }
  }

  bool _isInternetAvailable() {
    // TODO: Implement the logic to check if the internet is available
    // This can be achieved by various methods like trying to ping a server
    // or using a connectivity plugin.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final script = context.watch<ScriptLanguageProvider>().currentScript;

    return Container(
      color: const Color(0xfffbf0da),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              PaliScript.getScriptOf(
                script: script,
                romanText: ('''
Sabbapāpassa akaraṇaṃ
Kusalassa upasampadā
Sacittapa⁠riyodāpanaṃ
Etaṃ buddhānasāsanaṃ
'''),
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                color: Colors.brown,
                fontWeight: FontWeight.bold,
              ),
            ),
            FutureBuilder<String>(
              future: _messageFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                } else if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                } else {
                  return Text(snapshot.data ?? 'No message');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
*/
