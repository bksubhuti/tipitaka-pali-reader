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
  String category;
  String url;
  String filename;
  String size;

  /// The lowest app build number (the n of 3.1.8+n) that can use this item;
  /// older apps leave it out of the list. 0 = any. Apps before build 139
  /// don't know the field and show every item.
  int compatibilityVer;

  /// The highest app build that should see this item (an item only for old
  /// apps, such as "Update TPR"); 0 = no limit.
  int maxCompatibilityVer;

  DownloadListItem(
      {this.name = "",
      this.releaseDate = "",
      this.type = "",
      this.category = "",
      this.url = "",
      this.filename = "",
      this.size = "",
      this.compatibilityVer = 0,
      this.maxCompatibilityVer = 0});

  factory DownloadListItem.fromJson(Map<dynamic, dynamic> json) {
    return DownloadListItem(
      name: json["name"] ?? "n/a",
      releaseDate: json["release_date"] ?? "n/a",
      type: json['type'] ?? "n/a",
      category: json['category'] ?? "n/a",
      url: json['url'] ?? "n/a",
      filename: json['filename'] ?? "n/a",
      size: json['size'] ?? "n/a",
      compatibilityVer:
          int.tryParse('${json['compatibility_ver'] ?? 0}') ?? 0,
      maxCompatibilityVer:
          int.tryParse('${json['max_compatibility_ver'] ?? 0}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        "name": name,
        "relase_date": releaseDate,
        "type": type,
        "url": url,
        "filename": filename,
        "size": size,
        "compatibility_ver": compatibilityVer,
        "max_compatibility_ver": maxCompatibilityVer,
      };

  @override
  String toString() {
    return 'word: $this.name';
  }
}
