import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:tipitaka_pali/business_logic/models/download_list_item.dart';
import 'download_service.dart';
import 'download_notifier.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:tipitaka_pali/services/prefs.dart';

class DownloadView extends StatelessWidget {
  final bool showLocalRestores;
  const DownloadView({super.key, this.showLocalRestores = false});

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
                    Container(
                      height: 50,
                      alignment: Alignment.center,
                      child: Center(
                        child: Text(
                          downloadModel.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (downloadModel.downloading ||
                        downloadModel.connectionChecking)
                      const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    FutureBuilder<bool>(
                      future: checkInternetConnection(downloadModel),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        if (snapshot.hasData && snapshot.data!) {
                          return getFutureBuilder(context, downloadModel);
                        } else {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.signal_wifi_off,
                                    size: 80,
                                    color: (!Prefs.darkThemeOn)
                                        ? Theme.of(context)
                                            .appBarTheme
                                            .backgroundColor
                                        : null),
                                const SizedBox(height: 20),
                                Text(AppLocalizations.of(context)!
                                    .turnOnInternet),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<bool> checkInternetConnection(DownloadNotifier downloadModel) async {
    // 1. NEW: Bypass the internet check entirely if we are in local restore mode!
    if (showLocalRestores) {
      return true;
    }

    if (downloadModel.downloading) {
      return true;
    }

    downloadModel.connectionChecking = true;
    bool hasInternet = await InternetConnection().hasInternetAccess;
    downloadModel.connectionChecking = false;
    return hasInternet;
  }

  Future<void> getDownload(BuildContext context, DownloadNotifier dn,
      DownloadListItem downloadListItem) async {
    DownloadService downloadService = DownloadService(
        downloadNotifier: dn, downloadListItem: downloadListItem);

    dn.downloading = true;

    // Robust check: Remote URLs start with http/https. Local file paths do not.
    bool isLocalFile = !downloadListItem.url.startsWith('http');

    if (isLocalFile) {
      dn.message = "Preparing local restore...";
      await downloadService.installLocalSqlZip();
    } else {
      dn.message = AppLocalizations.of(context)!.checkingInternet;
      if (await checkInternetConnection(dn)) {
        await downloadService.installSqlZip();
      } else {
        dn.message = "No Internet";
        dn.downloading = false;
      }
    }
  }

  Widget getFutureBuilder(
      BuildContext context, DownloadNotifier downloadModel) {
    if (downloadModel.downloading) {
      return const SizedBox.shrink();
    } else {
      return Expanded(
        // Notice we changed the Future type here to List<DownloadListItem>
        child: FutureBuilder<List<DownloadListItem>>(
          future: _fetchDownloadItems(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.hasError) {
              return const Center(
                child: Text('Error fetching data or no files found.'),
              );
            }

            // Data is already parsed by our helper method!
            List<DownloadListItem> dlList = snapshot.data!;

            if (dlList.isEmpty) {
              return const Center(
                child: Text('No extensions found.'),
              );
            }

            // Group the items by category
            Map<String, List<DownloadListItem>> categorizedItems = {};
            for (var item in dlList) {
              String category = item.category ?? 'Uncategorized';
              if (!categorizedItems.containsKey(category)) {
                categorizedItems[category] = [];
              }
              categorizedItems[category]!.add(item);
            }

            // Convert the map entries to a list for indexed access
            final categories = categorizedItems.entries.toList();

            // Use a ScrollController if needed
            final ScrollController scrollController = ScrollController();

            return ListView.builder(
              controller: scrollController,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final GlobalKey expansionTileKey = GlobalKey();
                final entry = categories[index];
                String category = entry.key;
                List<DownloadListItem> items = entry.value;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 6,
                  ),
                  child: ExpansionTile(
                    key: expansionTileKey,
                    onExpansionChanged: (isExpanding) {
                      if (isExpanding) {
                        // Delay scrolling a bit to allow for the expansion animation to start.
                        Future.delayed(const Duration(milliseconds: 200))
                            .then((value) {
                          RenderObject? renderObject = expansionTileKey
                              .currentContext
                              ?.findRenderObject();
                          if (renderObject != null) {
                            renderObject.showOnScreen(
                              rect: renderObject.semanticBounds,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.ease,
                            );
                          }
                        });
                      }
                    },
                    initiallyExpanded: Prefs.expandedBookList,
                    title: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    childrenPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    children: items.map<Widget>((item) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 2.0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: ListTile(
                          title: Text("${item.name} (${item.size})"),
                          subtitle: Text(item.releaseDate),
                          onTap: () async {
                            await getDownload(context, downloadModel, item);
                          },
                          minVerticalPadding: 4,
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        ),
      );
    }
  }

  Future<List<DownloadListItem>> _fetchDownloadItems() async {
    final cacheFile = File('${Prefs.databaseDirPath}/download_list_cache.json');
    List<DownloadListItem> masterList = [];

    // ==========================================
    // NORMAL DOWNLOAD VIEW (Gets fresh online list & saves cache)
    // ==========================================
    if (!showLocalRestores) {
      try {
        final response = await http.get(Uri.parse(
            'https://github.com/bksubhuti/tpr_downloads/raw/master/download_source_files/download_list.json'));
        if (response.statusCode == 200) {
          masterList = downloadListItemFromJson(response.body);
          // CACHE THE LIST FOR FUTURE OFFLINE RESTORES!
          await cacheFile.writeAsString(response.body);
        }
      } catch (e) {
        debugPrint("Offline. Trying to load cached list...");
        if (await cacheFile.exists()) {
          masterList = downloadListItemFromJson(await cacheFile.readAsString());
        } else {
          throw Exception("No internet and no cached list available.");
        }
      }
      return masterList;
    }

    // ==========================================
    // LOCAL RESTORE VIEW (Uses cache to map file types)
    // ==========================================
    else {
      // 1. Try to load the map from the cache
      if (await cacheFile.exists()) {
        masterList = downloadListItemFromJson(await cacheFile.readAsString());
      } else {
        // Fallback: Try online if they somehow wiped the cache but kept the zips
        try {
          final response = await http.get(Uri.parse(
              'https://github.com/bksubhuti/tpr_downloads/raw/master/download_source_files/download_list.json'));
          if (response.statusCode == 200) {
            masterList = downloadListItemFromJson(response.body);
            await cacheFile.writeAsString(response.body);
          }
        } catch (e) {
          debugPrint("Offline and no cache found for mapping types.");
        }
      }

      // 2. Scan local directory and cross-reference
      final dir = Directory(Prefs.databaseDirPath);
      final List<DownloadListItem> localItems = [];

      if (!await dir.exists()) return localItems;

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.zip'));

      for (var file in files) {
        final stat = await file.stat();
        final fileName = file.path.split(Platform.pathSeparator).last;
        final sizeInKb = "${(stat.size / 1024).toStringAsFixed(0)} KB";
        final modifiedDate = DateFormat('dd.MM.yyyy').format(stat.modified);

        // --- CROSS-REFERENCE WITH CACHED MASTER LIST ---
        final knownItems =
            masterList.where((item) => item.filename == fileName);
        final knownItem = knownItems.isNotEmpty ? knownItems.first : null;

        String fileType = knownItem?.type ?? 'dictionary';
        String fileCategory = knownItem != null
            ? '${knownItem.category} (Local)'
            : 'Unknown Local Files';
        String displayName = knownItem?.name ?? fileName.replaceAll('.zip', '');

        localItems.add(DownloadListItem(
          name: displayName,
          releaseDate: modifiedDate,
          type: fileType,
          url: file.path,
          filename: fileName,
          size: sizeInKb,
          category: fileCategory,
        ));
      }
      return localItems;
    }
  }

  Future<void> ensureDownloadListCached() async {
    final cacheFile = File('${Prefs.databaseDirPath}/download_list_cache.json');

    if (!await cacheFile.exists()) {
      debugPrint(
          "Cache missing. Forcing background download of JSON mapping...");
      try {
        final response = await http.get(Uri.parse(
            'https://github.com/bksubhuti/tpr_downloads/raw/master/download_source_files/download_list.json'));

        if (response.statusCode == 200) {
          await cacheFile.parent.create(recursive: true);
          await cacheFile.writeAsString(response.body);
          debugPrint("SUCCESS: JSON list cached for future offline restores.");
        }
      } catch (e) {
        debugPrint("FAILED to force-cache JSON on startup: $e");
      }
    }
  }
}
