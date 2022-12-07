import 'dart:convert';
import 'package:flutter/material.dart';

/////////////////////////////////
// usage
/*    String dbQuery =
        '''Select residentDetails.id_code, residentDetails.dhamma_name, residentDetails.passport_name,residentDetails.kuti, residentDetails.country, interviews.stime, interviews.teacher, interviews.pk
          FROM residentDetails, interviews
          WHERE residentDetails.id_code = interviews.id_code
          ORDER BY interviews.stime DESC''';

    List<Map> list = await _db.rawQuery(dbQuery);
    return list
        .map((interviewdetails) => InterviewDetails.fromJson(interviewdetails))
        .toList();

    /// alternative from original tutorial
    //return list.map((trail) => Trail.fromJson(trail)).toList();
*/

List<Dictionary> dictionaryFromJson(String str) =>
    List<Dictionary>.from(json.decode(str).map((x) => Dictionary.fromJson(x)));

String dictionaryToJson(List<Dictionary> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class Dictionary {
  String? word;
  String definition;
  int bookID;

  Dictionary({this.word = "", this.definition = "", this.bookID = 0});

  factory Dictionary.fromJson(Map<dynamic, dynamic> json) {
    return Dictionary(
      word: json["word"] ?? "n/a",
      definition: json["definition"] ?? "n/a",
      bookID: json['book_id'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        "word": word,
        "definition": definition,
        "book_id": bookID,
      };

  @override
  String toString() {
    return 'word: $this.word';
  }
}
