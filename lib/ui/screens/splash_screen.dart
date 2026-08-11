import 'package:flutter/material.dart';
import 'package:tipitaka_pali/services/get_database_status.dart';

import 'home/home_container.dart';
import 'initial_setup.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final databaseStatus = getDatabaseStatus();
    late final Widget child;

    switch (databaseStatus) {
      case DatabaseStatus.notExist:
        child = const InitialSetup();
        break;
      case DatabaseStatus.outOfDate:
        child = const InitialSetup(isUpdateMode: true);
        break;
      case DatabaseStatus.uptoDate:
        child = const Home();
        break;
      default:
        child = const Home();
        break;
    }

    return Material(child: child);
  }
}
