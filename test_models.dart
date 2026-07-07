import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  String jsonStr = '{"error": {"code": 429, "message": "You exceeded your current quota... limit: 0"}}';
  print(jsonStr.contains('limit: 0'));
}
