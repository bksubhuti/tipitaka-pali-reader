import 'package:tipitaka_pali/utils/pali_script_converter.dart';

class DictionaryBook {
  /// English DPD is book 11; each DPD translation package installs its rows
  /// in the dpd table as its own book, numbered 111–199.
  static bool isDpd(int bookID) =>
      bookID == 11 || (bookID >= 111 && bookID <= 199);

  /// The language of a DPD translation book (111 'si' …), else null.
  static String? dpdLang(int bookID) =>
      const {111: 'si', 112: 'th', 113: 'hi', 114: 'my'}[bookID];

  /// The script its Pāḷi is shown in, else null (English DPD).
  static Script? dpdScript(int bookID) => const {
        111: Script.sinhala,
        112: Script.thai,
        113: Script.devanagari,
        114: Script.myanmar,
      }[bookID];

  int bookID;
  String name;
  int order;
  bool userChoice;

  DictionaryBook(
      {required this.bookID,
      required this.name,
      required this.order,
      required this.userChoice});

  DictionaryBook copyWith(
      {int? bookID, String? name, int? order, bool? userChoice}) {
    return DictionaryBook(
        bookID: bookID ?? this.bookID,
        name: name ?? this.name,
        order: order ?? this.order,
        userChoice: userChoice ?? this.userChoice);
  }
}
