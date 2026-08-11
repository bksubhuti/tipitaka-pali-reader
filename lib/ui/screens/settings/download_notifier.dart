import 'package:flutter/material.dart';

class DownloadNotifier extends ChangeNotifier {
  String _message = "Select Item";
  bool connectionChecking = false;

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

  int _totalSteps = 0;
  int get totalSteps => _totalSteps;

  set totalSteps(int val) {
    _totalSteps = val;
    notifyListeners();
  }

  int _stepsCompleted = 0;
  int get stepsCompleted => _stepsCompleted;

  set stepsCompleted(int val) {
    _stepsCompleted = val;
    notifyListeners();
  }
}
