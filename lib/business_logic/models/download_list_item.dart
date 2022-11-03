import 'dart:convert';

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

List<DownloadListItem> downloadListItemFromJson(String str) =>
    List<DownloadListItem>.from(
        json.decode(str).map((x) => DownloadListItem.fromJson(x)));

String downloadListItemToJson(List<DownloadListItem> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class DownloadListItem {
  String name;
  String releaseDate;
  String type;
  String url;
  String filename;
  String size;

  DownloadListItem(
      {this.name = "",
      this.releaseDate = "",
      this.type = "",
      this.url = "",
      this.filename = "",
      this.size = ""});

  factory DownloadListItem.fromJson(Map<dynamic, dynamic> json) {
    return DownloadListItem(
      name: json["name"] ?? "n/a",
      releaseDate: json["release_date"] ?? "n/a",
      type: json['type'] ?? "n/a",
      url: json['url'] ?? "n/a",
      filename: json['filename'] ?? "n/a",
      size: json['size'] ?? "n/a",
    );
  }

  Map<String, dynamic> toJson() => {
        "name": name,
        "relase_date": releaseDate,
        "type": type,
        "url": url,
        "filename": filename,
        "size": size,
      };

  @override
  String toString() {
    return 'word: $this.name';
  }
}
