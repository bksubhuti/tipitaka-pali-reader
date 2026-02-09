//do reset stuff
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:tipitaka_pali/data/constants.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import '../../services/prefs.dart';
import 'confirm_dialog.dart';
import 'package:path/path.dart';

doResetDialog(BuildContext context) async {
  final result = await _getConfirmataion(context);
  if (result == OkCancelAction.ok) {
    Prefs.instance.clear();

    // more than clearning the prefs is needed.
    // if the db is still present, it will think it is updatemode.
    // if the db is corrupted, then it can fail when it does a migration.

    final DatabaseHelper databaseHelper = DatabaseHelper();
    late String databasesDirPath;

    final docDirPath = await getApplicationSupportDirectory();
    databasesDirPath = docDirPath.path;

    // final databasesDirPath = await getApplicationDocumentsDirectory();
    final dbFilePath = join(databasesDirPath, DatabaseInfo.fileName);

    await databaseHelper.close();
    // deleting database file
    await deleteDatabase(dbFilePath);

    await _showMyDialog(context);
  }
}

Future<OkCancelAction?> _getConfirmataion(BuildContext context) async {
  String msg =
      "${AppLocalizations.of(context)!.areYouSureReset}\n\nDir=${Prefs.databaseDirPath}";
  return await showDialog<OkCancelAction>(
      context: context,
      builder: (context) {
        return ConfirmDialog(
          title: AppLocalizations.of(context)!.confirmation,
          message: msg,
          okLabel: AppLocalizations.of(context)!.delete,
          cancelLabel: AppLocalizations.of(context)!.cancel,
        );
      });
}

// A function that shows an alert dialog with a message
Future<void> _showMyDialog(BuildContext context) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // user must tap button!
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(AppLocalizations.of(context)!.alert),
        content: Text(AppLocalizations.of(context)!.pleaseCloseRestart),
        actions: <Widget>[
          TextButton(
            child: Text(AppLocalizations.of(context)!.ok),
            onPressed: () {
              // Dismiss the dialog
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
