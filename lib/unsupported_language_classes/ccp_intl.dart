import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_custom.dart' as date_symbol_data_custom;
import 'package:intl/date_symbols.dart' as intl;
import 'package:intl/intl.dart' as intl;

/// A custom set of date patterns for the `nn` locale.
///
/// These are not accurate and are just a clone of the date patterns for the
/// `no` locale to demonstrate how one would write and use custom date patterns.
// #docregion Date
const ccpLocaleDatePatterns = {
  'd': 'd.',
  'E': 'ccc',
  'EEEE': 'cccc',
  'LLL': 'LLL',
// #enddocregion Date
  'LLLL': 'LLLL',
  'M': 'L.',
  'Md': 'd.M.',
  'MEd': 'EEE d.M.',
  'MMM': 'LLL',
  'MMMd': 'd. MMM',
  'MMMEd': 'EEE d. MMM',
  'MMMM': 'LLLL',
  'MMMMd': 'd. MMMM',
  'MMMMEEEEd': 'EEEE d. MMMM',
  'QQQ': 'QQQ',
  'QQQQ': 'QQQQ',
  'y': 'y',
  'yM': 'M.y',
  'yMd': 'd.M.y',
  'yMEd': 'EEE d.MM.y',
  'yMMM': 'MMM y',
  'yMMMd': 'd. MMM y',
  'yMMMEd': 'EEE d. MMM y',
  'yMMMM': 'MMMM y',
  'yMMMMd': 'd. MMMM y',
  'yMMMMEEEEd': 'EEEE d. MMMM y',
  'yQQQ': 'QQQ y',
  'yQQQQ': 'QQQQ y',
  'H': 'HH',
  'Hm': 'HH:mm',
  'Hms': 'HH:mm:ss',
  'j': 'HH',
  'jm': 'HH:mm',
  'jms': 'HH:mm:ss',
  'jmv': 'HH:mm v',
  'jmz': 'HH:mm z',
  'jz': 'HH z',
  'm': 'm',
  'ms': 'mm:ss',
  's': 's',
  'v': 'v',
  'z': 'z',
  'zzzz': 'zzzz',
  'ZZZZ': 'ZZZZ',
};

/// A custom set of date symbols for the `nn` locale.
///
/// These are not accurate and are just a clone of the date symbols for the
/// `no` locale to demonstrate how one would write and use custom date symbols.
// #docregion Date2
const ccpDateSymbols = {
  'NAME': 'ccp',
  'ERAS': <dynamic>[
    'f.Kr.',
    'e.Kr.',
  ],
// #enddocregion Date2
  'ERANAMES': <dynamic>[
    'før Kristus',
    'etter Kristus',
  ],
  'NARROWMONTHS': <dynamic>[
    'J',
    'F',
    'M',
    'A',
    'M',
    'J',
    'J',
    'A',
    'S',
    'O',
    'N',
    'D',
  ],
  'STANDALONENARROWMONTHS': <dynamic>[
    'J',
    'F',
    'M',
    'A',
    'M',
    'J',
    'J',
    'A',
    'S',
    'O',
    'N',
    'D',
  ],
  'MONTHS': <dynamic>[
    'januar',
    'februar',
    'mars',
    'april',
    'mai',
    'juni',
    'juli',
    'august',
    'september',
    'oktober',
    'november',
    'desember',
  ],
  'STANDALONEMONTHS': <dynamic>[
    'januar',
    'februar',
    'mars',
    'april',
    'mai',
    'juni',
    'juli',
    'august',
    'september',
    'oktober',
    'november',
    'desember',
  ],
  'SHORTMONTHS': <dynamic>[
    'jan.',
    'feb.',
    'mar.',
    'apr.',
    'mai',
    'jun.',
    'jul.',
    'aug.',
    'sep.',
    'okt.',
    'nov.',
    'des.',
  ],
  'STANDALONESHORTMONTHS': <dynamic>[
    'jan',
    'feb',
    'mar',
    'apr',
    'mai',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'des',
  ],
  'WEEKDAYS': <dynamic>[
    'søndag',
    'mandag',
    'tirsdag',
    'onsdag',
    'torsdag',
    'fredag',
    'lørdag',
  ],
  'STANDALONEWEEKDAYS': <dynamic>[
    'søndag',
    'mandag',
    'tirsdag',
    'onsdag',
    'torsdag',
    'fredag',
    'lørdag',
  ],
  'SHORTWEEKDAYS': <dynamic>[
    'søn.',
    'man.',
    'tir.',
    'ons.',
    'tor.',
    'fre.',
    'lør.',
  ],
  'STANDALONESHORTWEEKDAYS': <dynamic>[
    'søn.',
    'man.',
    'tir.',
    'ons.',
    'tor.',
    'fre.',
    'lør.',
  ],
  'NARROWWEEKDAYS': <dynamic>[
    'S',
    'M',
    'T',
    'O',
    'T',
    'F',
    'L',
  ],
  'STANDALONENARROWWEEKDAYS': <dynamic>[
    'S',
    'M',
    'T',
    'O',
    'T',
    'F',
    'L',
  ],
  'SHORTQUARTERS': <dynamic>[
    'K1',
    'K2',
    'K3',
    'K4',
  ],
  'QUARTERS': <dynamic>[
    '1. kvartal',
    '2. kvartal',
    '3. kvartal',
    '4. kvartal',
  ],
  'AMPMS': <dynamic>[
    'a.m.',
    'p.m.',
  ],
  'DATEFORMATS': <dynamic>[
    'EEEE d. MMMM y',
    'd. MMMM y',
    'd. MMM y',
    'dd.MM.y',
  ],
  'TIMEFORMATS': <dynamic>[
    'HH:mm:ss zzzz',
    'HH:mm:ss z',
    'HH:mm:ss',
    'HH:mm',
  ],
  'AVAILABLEFORMATS': null,
  'FIRSTDAYOFWEEK': 0,
  'WEEKENDRANGE': <dynamic>[
    5,
    6,
  ],
  'FIRSTWEEKCUTOFFDAY': 3,
  'DATETIMEFORMATS': <dynamic>[
    '{1} {0}',
    '{1} \'kl\'. {0}',
    '{1}, {0}',
    '{1}, {0}',
  ],
};

// #docregion Delegate
class _CcpMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _CcpMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ccp';

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    final String localeName = intl.Intl.canonicalizedLocale(locale.toString());

    // The locale (in this case `nn`) needs to be initialized into the custom
    // date symbols and patterns setup that Flutter uses.
    date_symbol_data_custom.initializeDateFormattingCustom(
      locale: localeName,
      patterns: ccpLocaleDatePatterns,
      symbols: intl.DateSymbols.deserializeFromMap(ccpDateSymbols),
    );

    return SynchronousFuture<MaterialLocalizations>(
      CcpMaterialLocalizations(
        localeName: localeName,
        // The `intl` library's NumberFormat class is generated from CLDR data
        // (see https://github.com/dart-lang/intl/blob/master/lib/number_symbols_data.dart).
        // Unfortunately, there is no way to use a locale that isn't defined in
        // this map and the only way to work around this is to use a listed
        // locale's NumberFormat symbols. So, here we use the number formats
        // for 'en_US' instead.
        decimalFormat: intl.NumberFormat('#,##0.###', 'en'),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'en'),
        // DateFormat here will use the symbols and patterns provided in the
        // `date_symbol_data_custom.initializeDateFormattingCustom` call above.
        // However, an alternative is to simply use a supported locale's
        // DateFormat symbols, similar to NumberFormat above.
        fullYearFormat: intl.DateFormat('y', localeName),
        compactDateFormat: intl.DateFormat('yMd', localeName),
        shortDateFormat: intl.DateFormat('yMMMd', localeName),
        mediumDateFormat: intl.DateFormat('EEE, MMM d', localeName),
        longDateFormat: intl.DateFormat('EEEE, MMMM d, y', localeName),
        yearMonthFormat: intl.DateFormat('MMMM y', localeName),
        shortMonthDayFormat: intl.DateFormat('MMM y', localeName),
      ),
    );
  }

  @override
  bool shouldReload(_CcpMaterialLocalizationsDelegate old) => false;
}
// #enddocregion Delegate

/// A custom set of localizations for the 'nn' locale. In this example, only
/// the value for openAppDrawerTooltip was modified to use a custom message as
/// an example. Everything else uses the American English (en_US) messages
/// and formatting.
class CcpMaterialLocalizations extends GlobalMaterialLocalizations
    implements CupertinoLocalizations {
  const CcpMaterialLocalizations({
    super.localeName = 'ccp',
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

// #docregion Getters
  @override
  String get moreButtonTooltip => r'More';

  @override
  String get aboutListTileTitleRaw => r'About $applicationName';

  @override
  String get alertDialogLabel => r'Alert';

// #enddocregion Getters

  @override
  String get anteMeridiemAbbreviation => r'AM';

  @override
  String get backButtonTooltip => r'Back';

  @override
  String get cancelButtonLabel => r'CANCEL';

  @override
  String get closeButtonLabel => r'CLOSE';

  @override
  String get closeButtonTooltip => r'Close';

  @override
  String get collapsedIconTapHint => r'Expand';

  @override
  String get continueButtonLabel => r'CONTINUE';

  @override
  String get copyButtonLabel => r'COPY';

  @override
  String get cutButtonLabel => r'CUT';

  @override
  String get deleteButtonTooltip => r'Delete';

  @override
  String get dialogLabel => r'Dialog';

  @override
  String get drawerLabel => r'Navigation menu';

  @override
  String get expandedIconTapHint => r'Collapse';

  @override
  String get firstPageTooltip => r'First page';

  @override
  String get hideAccountsLabel => r'Hide accounts';

  @override
  String get lastPageTooltip => r'Last page';

  @override
  String get licensesPageTitle => r'Licenses';

  @override
  String get modalBarrierDismissLabel => r'Dismiss';

  @override
  String get nextMonthTooltip => r'Next month';

  @override
  String get nextPageTooltip => r'Next page';

  @override
  String get okButtonLabel => r'OK';

  @override
  // A custom drawer tooltip message.
  String get openAppDrawerTooltip => r'Custom Navigation Menu Tooltip';

// #docregion Raw
  @override
  String get pageRowsInfoTitleRaw => r'$firstRow–$lastRow of $rowCount';

  @override
  String get pageRowsInfoTitleApproximateRaw =>
      r'$firstRow–$lastRow of about $rowCount';
// #enddocregion Raw

  @override
  String get pasteButtonLabel => r'PASTE';

  @override
  String get popupMenuLabel => r'Popup menu';

  @override
  String get menuBarMenuLabel => r'Menu Bar Label';

  @override
  String get postMeridiemAbbreviation => r'PM';

  @override
  String get previousMonthTooltip => r'Previous month';

  @override
  String get previousPageTooltip => r'Previous page';

  @override
  String get refreshIndicatorSemanticLabel => r'Refresh';

  @override
  String? get remainingTextFieldCharacterCountFew => null;

  @override
  String? get remainingTextFieldCharacterCountMany => null;

  @override
  String get remainingTextFieldCharacterCountOne => r'1 character remaining';

  @override
  String get remainingTextFieldCharacterCountOther =>
      r'$remainingCount characters remaining';

  @override
  String? get remainingTextFieldCharacterCountTwo => null;

  @override
  String get remainingTextFieldCharacterCountZero => r'No characters remaining';

  @override
  String get reorderItemDown => r'Move down';

  @override
  String get reorderItemLeft => r'Move left';

  @override
  String get reorderItemRight => r'Move right';

  @override
  String get reorderItemToEnd => r'Move to the end';

  @override
  String get reorderItemToStart => r'Move to the start';

  @override
  String get reorderItemUp => r'Move up';

  @override
  String get rowsPerPageTitle => r'Rows per page:';

  @override
  ScriptCategory get scriptCategory => ScriptCategory.englishLike;

  @override
  String get searchFieldLabel => r'Search';

  @override
  String get selectAllButtonLabel => r'SELECT ALL';

  @override
  String? get selectedRowCountTitleFew => null;

  @override
  String? get selectedRowCountTitleMany => null;

  @override
  String get selectedRowCountTitleOne => r'1 item selected';

  @override
  String get selectedRowCountTitleOther => r'$selectedRowCount items selected';

  @override
  String? get selectedRowCountTitleTwo => null;

  @override
  String get selectedRowCountTitleZero => r'No items selected';

  @override
  String get showAccountsLabel => r'Show accounts';

  @override
  String get showMenuTooltip => r'Show menu';

  @override
  String get signedInLabel => r'Signed in';

  @override
  String get tabLabelRaw => r'Tab $tabIndex of $tabCount';

  @override
  TimeOfDayFormat get timeOfDayFormatRaw => TimeOfDayFormat.h_colon_mm_space_a;

  @override
  String get timePickerHourModeAnnouncement => r'Select hours';

  @override
  String get timePickerMinuteModeAnnouncement => r'Select minutes';

  @override
  String get viewLicensesButtonLabel => r'VIEW LICENSES';

  @override
  List<String> get narrowWeekdays =>
      const <String>['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  int get firstDayOfWeekIndex => 0;

  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _CcpMaterialLocalizationsDelegate();

  @override
  String get calendarModeButtonLabel => r'Switch to calendar';

  @override
  String get dateHelpText => r'mm/dd/yyyy';

  @override
  String get dateInputLabel => r'Enter Date';

  @override
  String get dateOutOfRangeLabel => r'Out of range.';

  @override
  String get datePickerHelpText => r'SELECT DATE';

  @override
  String get dateRangeEndDateSemanticLabelRaw => r'End date $fullDate';

  @override
  String get dateRangeEndLabel => r'End Date';

  @override
  String get dateRangePickerHelpText => 'SELECT RANGE';

  @override
  String get dateRangeStartDateSemanticLabelRaw => 'Start date \$fullDate';

  @override
  String get dateRangeStartLabel => 'Start Date';

  @override
  String get dateSeparator => '/';

  @override
  String get dialModeButtonLabel => 'Switch to dial picker mode';

  @override
  String get inputDateModeButtonLabel => 'Switch to input';

  @override
  String get inputTimeModeButtonLabel => 'Switch to text input mode';

  @override
  String get invalidDateFormatLabel => 'Invalid format.';

  @override
  String get invalidDateRangeLabel => 'Invalid range.';

  @override
  String get invalidTimeLabel => 'Enter a valid time';

  @override
  String get licensesPackageDetailTextOther => '\$licenseCount licenses';

  @override
  String get saveButtonLabel => 'SAVE';

  @override
  String get selectYearSemanticsLabel => 'Select year';

  @override
  String get timePickerDialHelpText => 'SELECT TIME';

  @override
  String get timePickerHourLabel => 'Hour';

  @override
  String get timePickerInputHelpText => 'ENTER TIME';

  @override
  String get timePickerMinuteLabel => 'Minute';

  @override
  String get unspecifiedDate => 'Date';

  @override
  String get unspecifiedDateRange => 'Date Range';

  @override
  String get keyboardKeyAlt => 'Alt';

  @override
  String get keyboardKeyAltGraph => 'AltGraph';

  @override
  String get keyboardKeyBackspace => 'Backspace';

  @override
  String get keyboardKeyCapsLock => 'Caps Lock';

  @override
  String get keyboardKeyChannelDown => 'Channel Down';

  @override
  String get keyboardKeyChannelUp => 'Channel Up';

  @override
  String get keyboardKeyControl => 'Control';

  @override
  String get keyboardKeyDelete => 'Delete';

  String get keyboardKeyEisu => 'Eisu';

  @override
  String get keyboardKeyEject => 'Eject';

  @override
  String get keyboardKeyEnd => 'End';

  @override
  String get keyboardKeyEscape => 'Escape';

  @override
  String get keyboardKeyFn => 'Fn';

  @override
  String get keyboardKeyHome => 'Home';

  @override
  String get keyboardKeyInsert => 'Insert';

  @override
  String get keyboardKeyMeta => 'Meta';

  @override
  String get keyboardKeyMetaMacOs => 'Command';

  @override
  String get keyboardKeyMetaWindows => 'Windows';

  @override
  String get keyboardKeyNumLock => 'Num Lock';

  @override
  String get keyboardKeyNumpad0 => 'Numpad 0';

  @override
  String get keyboardKeyNumpad1 => 'Numpad 1';

  @override
  String get keyboardKeyNumpad2 => 'Numpad 2';

  @override
  String get keyboardKeyNumpad3 => 'Numpad 3';

  @override
  String get keyboardKeyNumpad4 => 'Numpad 4';

  @override
  String get keyboardKeyNumpad5 => 'Numpad 5';

  @override
  String get keyboardKeyNumpad6 => 'Numpad 6';

  @override
  String get keyboardKeyNumpad7 => 'Numpad 7';

  @override
  String get keyboardKeyNumpad8 => 'Numpad 8';

  @override
  String get keyboardKeyNumpad9 => 'Numpad 9';

  @override
  String get keyboardKeyNumpadAdd => 'Numpad Add';

  @override
  String get keyboardKeyNumpadComma => 'Numpad Comma';

  @override
  String get keyboardKeyNumpadDecimal => 'Numpad Decimal';

  @override
  String get keyboardKeyNumpadDivide => 'Numpad Divide';

  @override
  String get keyboardKeyNumpadEnter => 'Numpad Enter';

  @override
  String get keyboardKeyNumpadEqual => 'Numpad Equal';

  @override
  String get keyboardKeyNumpadMultiply => 'Numpad Multiply';

  @override
  String get keyboardKeyNumpadParenLeft => 'Numpad (';

  @override
  String get keyboardKeyNumpadParenRight => 'Numpad )';

  @override
  String get keyboardKeyNumpadSubtract => 'Numpad Subtract';

  @override
  String get keyboardKeyPageDown => 'Page Down';

  @override
  String get keyboardKeyPageUp => 'Page Up';

  @override
  String get keyboardKeyPower => 'Power';

  @override
  String get keyboardKeyPowerOff => 'Power Off';

  @override
  String get keyboardKeyPrintScreen => 'Print Screen';

  @override
  String get keyboardKeyScrollLock => 'Scroll Lock';

  @override
  String get keyboardKeySelect => 'Select';

  @override
  String get keyboardKeySpace => 'Space';

// For the following methods, if you don't need specific functionality,
// simply return a placeholder string or null.

  @override
  String get scrimOnTapHintRaw => 'Tap to dismiss';

  @override
  String get bottomSheetLabel => 'Bottom sheet';

  @override
  String get currentDateLabel => 'Current date';

  @override
  String get keyboardKeyShift => 'Shift';

  @override
  String get scrimLabel => 'Dismiss modal barrier';

  @override
  DatePickerDateOrder get datePickerDateOrder => DatePickerDateOrder.mdy;

  @override
  DatePickerDateTimeOrder get datePickerDateTimeOrder =>
      DatePickerDateTimeOrder.date_time_dayPeriod;

  @override
  String datePickerDayOfMonth(int dayIndex, [int? weekDay]) =>
      dayIndex.toString();

  @override
  String datePickerHour(int hour) => hour.toString();

  @override
  String? datePickerHourSemanticsLabel(int hour) => '$hour o\'clock';

  @override
  String datePickerMediumDate(DateTime date) =>
      intl.DateFormat.yMd().format(date); // Using intl package for formatting

  @override
  String datePickerMinute(int minute) => minute.toString();

  @override
  String? datePickerMinuteSemanticsLabel(int minute) => '$minute minutes';

  @override
  String datePickerMonth(int monthIndex) =>
      intl.DateFormat.MMMM().format(DateTime(0, monthIndex));

  @override
  String datePickerYear(int yearIndex) => yearIndex.toString();

  @override
  String get noSpellCheckReplacementsLabel => 'No replacements';

  @override
  String get searchTextFieldPlaceholderLabel => 'Search';

  @override
  String tabSemanticsLabel({required int tabIndex, required int tabCount}) =>
      'Tab $tabIndex of $tabCount';

  @override
  String timerPickerHour(int hour) => hour.toString();

  @override
  String? timerPickerHourLabel(int hour) => '$hour hours';

  @override
  List<String> get timerPickerHourLabels =>
      List.generate(24, (index) => index.toString());

  @override
  String timerPickerMinute(int minute) => minute.toString();

  @override
  String? timerPickerMinuteLabel(int minute) => '$minute minutes';

  @override
  List<String> get timerPickerMinuteLabels =>
      List.generate(60, (index) => index.toString());

  @override
  String timerPickerSecond(int second) => second.toString();

  @override
  String? timerPickerSecondLabel(int second) => '$second seconds';

  @override
  List<String> get timerPickerSecondLabels =>
      List.generate(60, (index) => index.toString());

  @override
  String get todayLabel => 'Today';

  @override
  String get collapsedHint => 'Collapsed';

  @override
  String get expandedHint => 'Expanded';

  @override
  String get expansionTileCollapsedHint => 'Tap to expand';

  @override
  String get expansionTileCollapsedTapHint => 'Collapsed, tap to expand';

  @override
  String get expansionTileExpandedHint => 'Tap to collapse';

  @override
  String get expansionTileExpandedTapHint => 'Expanded, tap to collapse';

  @override
  String get scanTextButtonLabel => 'Scan text';

  @override
  String datePickerStandaloneMonth(int monthIndex) =>
      intl.DateFormat.MMMM().format(DateTime(0, monthIndex));

  @override
  String get lookUpButtonLabel => 'Look up';

  @override
  String get menuDismissLabel => 'Dismiss menu';

  @override
  String get searchWebButtonLabel => 'Search web';

  @override
  String get shareButtonLabel => 'Share';

  @override
  // TODO: implement clearButtonLabel
  String get clearButtonLabel => throw UnimplementedError();

  @override
  // TODO: implement clearButtonTooltip
  String get clearButtonTooltip => throw UnimplementedError();

  @override
  // TODO: implement selectedDateLabel
  String get selectedDateLabel => throw UnimplementedError();

  @override
  // TODO: implement backButtonLabel
  String get backButtonLabel => throw UnimplementedError();
}
