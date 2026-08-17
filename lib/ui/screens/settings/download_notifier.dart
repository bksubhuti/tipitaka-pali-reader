import 'package:flutter/material.dart';

class DownloadNotifier extends ChangeNotifier {
  String _message = "Select Item";
  bool connectionChecking = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

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
