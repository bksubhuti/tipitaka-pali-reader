import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CountryService {
  /// Fetches the ISO 3166-1 alpha-2 country code of the client.
  /// Returns null if the request fails or times out.
  static Future<String?> getCountryCode() async {
    try {
      final response = await http
          .get(Uri.parse('https://api.country.is/'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['country'] as String?;
      } else {
        debugPrint(
            'Failed to fetch country code. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting country code: $e');
    }
    return null;
  }
}
