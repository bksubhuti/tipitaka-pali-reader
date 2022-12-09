import 'package:flutter/material.dart';
import '../../../business_logic/models/download_list_item.dart';
import 'download_service.dart';
import 'download_notifier.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;

class DownloadView extends StatelessWidget {
  const DownloadView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DownloadNotifier>(
        create: (context) => DownloadNotifier(),
        child: SafeArea(
          child: Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context)!.downloadTitle),
            ),
            body: Consumer<DownloadNotifier>(
                builder: (context, downloadModel, child) {
              return Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(
                      height: 60,
                    ),
                    Text(downloadModel.message),
                    const SizedBox(
                      height: 60,
                    ),
                    SizedBox(
                      // height: 400,
                      child: getFutureBuilder(context, downloadModel),
                    ),
                  ],
                ),
              );
            }),
          ),
        ));
  }

  getDownload(DownloadNotifier dn, DownloadListItem downloadListItem) async {
    DownloadService downloadService = DownloadService(
        downloadNotifier: dn, downloadListItem: downloadListItem);

    dn.downloading = true;
    await downloadService.installSqlZip();
  }

  getFutureBuilder(context, DownloadNotifier downloadModel) {
    if (downloadModel.downloading) {
      return const SizedBox.shrink();
    } else {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        width: MediaQuery.of(context).size.width * 0.65,
        child: FutureBuilder(
          future: http.get(Uri.parse(
              'https://github.com/bksubhuti/tpr_downloads/raw/master/download_source_files/download_list.json')),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            List<DownloadListItem> dlList =
                downloadListItemFromJson(snapshot.data!.body);
            // print(data);

            // return Text('see');
            return ListView.builder(
              scrollDirection: Axis.vertical,
              shrinkWrap: true,
              itemCount: dlList.length,
              itemBuilder: (context, index) {
                //      print(stores[index][index]['name']);
                return ListTile(
                  title: Text("${dlList[index].name} ${dlList[index].size}"),
                  leading: Text(dlList[index].releaseDate),
                  onTap: () async {
                    await getDownload(downloadModel, dlList[index]);
                  },
                );
              },
            );
          },
        ),
      );
    }
  }
}
