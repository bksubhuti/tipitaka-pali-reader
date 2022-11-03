import 'package:flutter/material.dart';

class DownloadNotifier extends ChangeNotifier {
  String _message = "Select Item";

  set message(String val) {
    _message = val;
    notifyListeners();
  }

  String get message => _message;

  bool _downloading = false;
  bool get downloading => _downloading;

  set downloading(bool val) {
    _downloading = val;
    notifyListeners();
  }
}
