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
import 'package:wakelock_plus/wakelock_plus.dart';

class DownloadView extends StatefulWidget {
  final bool showLocalRestores;
  final bool autoInstallEnglish;
  const DownloadView({
    super.key,
    this.showLocalRestores = false,
    this.autoInstallEnglish = false,
  });

  @override
  State<DownloadView> createState() => _DownloadViewState();
}

class _DownloadViewState extends State<DownloadView> {
  bool _hasAutoStarted = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  void _startLocalEnglishInstall(DownloadNotifier dn) {
    if (_hasAutoStarted) return;
    _hasAutoStarted = true;

    final localItem = DownloadListItem(
      name:
          'ePitaka.org English (Full replacement of core texts with Pāḷi / English texts)',
      releaseDate: '24.2.2026',
      type: 'books index',
      url:
          'https://www.dropbox.com/scl/fi/jfr93gi4k8hnv9016bjw1/epitaka_full_en.zip?rlkey=8ovolzb3eo1n9jp4fl2vw47qd&st=onglx7un&dl=1',
      filename: 'epitaka_full_en.zip',
      size: '80.8 MB',
      category: 'Full Translations',
    );
    getDownload(context, dn, localItem);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<bool> _confirmExit(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 48),
          title: const Text('Download In Progress'),
          content: const Text(
            'A database operation is still running.\n\n'
            'Leaving now may corrupt the database and require a reinstall.\n\n'
            'Are you sure you want to exit?',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Exit Anyway'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DownloadNotifier>(
      create: (context) => DownloadNotifier(),
      child: SafeArea(
        child: Consumer<DownloadNotifier>(
          builder: (context, downloadModel, child) {
            return PopScope(
              canPop: !downloadModel.downloading,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                final shouldExit = await _confirmExit(context);
                if (shouldExit && context.mounted) {
                  downloadModel.downloading = false;
                  Navigator.of(context).pop();
                }
              },
              child: Scaffold(
                appBar: AppBar(
                  title: Text(AppLocalizations.of(context)!.downloadTitle),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () async {
                      if (downloadModel.downloading) {
                        final shouldExit = await _confirmExit(context);
                        if (shouldExit && context.mounted) {
                          downloadModel.downloading = false;
                          Navigator.of(context).pop();
                        }
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
                body: Builder(
                  builder: (context) {
                    // When autoInstallEnglish, bypass the online list entirely
                    // and go straight to the local testing.db.zip file.
                    if (widget.autoInstallEnglish && !_hasAutoStarted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _startLocalEnglishInstall(downloadModel);
                      });
                    }

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
                          if (downloadModel.downloading &&
                              downloadModel.totalSteps > 0)
                            _buildVerticalStepProgress(context, downloadModel),
                          const SizedBox(height: 10),
                          if (downloadModel.downloading ||
                              downloadModel.connectionChecking)
                            const SizedBox.shrink(),
                          const SizedBox(height: 20),
                          // Skip list fetch entirely when autoInstallEnglish
                          if (!widget.autoInstallEnglish)
                            FutureBuilder<bool>(
                              future: checkInternetConnection(downloadModel),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const SizedBox.shrink();
                                }
                                if (snapshot.hasData && snapshot.data!) {
                                  return getFutureBuilder(
                                      context, downloadModel);
                                } else {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildVerticalStepProgress(
      BuildContext context, DownloadNotifier downloadModel) {
    final stepTitles = [
      'Downloading / Locating Archive',
      'Copying Database Tables',
      'Indexing FTS Pages',
      'Rebuilding Book Indexes',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(stepTitles.length, (index) {
          final isDone = downloadModel.stepsCompleted > index;
          final isActive = downloadModel.stepsCompleted == index &&
              downloadModel.downloading;
          final isLast = index == stepTitles.length - 1;

          Color circleColor;
          Widget circleChild;

          if (isDone) {
            circleColor = Colors.green;
            circleChild =
                const Icon(Icons.check, size: 14, color: Colors.white);
          } else if (isActive) {
            circleColor = Colors.blue;
            circleChild = Text(
              '${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            );
          } else {
            circleColor = Colors.grey.shade400;
            circleChild = Text(
              '${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            );
          }

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: circleChild,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isDone ? Colors.green : Colors.grey.shade300,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 16.0, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stepTitles[index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive || isDone
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isActive
                                ? Colors.blue
                                : (isDone
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color
                                    : Theme.of(context).disabledColor),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.blue),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  downloadModel.message,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Future<bool> checkInternetConnection(DownloadNotifier downloadModel) async {
    // Always bypass internet check for local restores, autoInstallEnglish, or active downloads!
    if (widget.showLocalRestores ||
        widget.autoInstallEnglish ||
        downloadModel.downloading) {
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

    // Check if selecting ePitaka English / Vietnamese DB extension or test DB zip
    final nameLower = downloadListItem.name.toLowerCase();
    final filenameLower = downloadListItem.filename.toLowerCase();
    final urlLower = downloadListItem.url.toLowerCase();
    final categoryLower = (downloadListItem.category ?? '').toLowerCase();

    bool isDbExtension = filenameLower.contains('epitaka') ||
        filenameLower.contains('testingdb') ||
        filenameLower.contains('testing.db') ||
        urlLower.contains('epitaka') ||
        urlLower.contains('testing') ||
        nameLower.contains('epitaka') ||
        nameLower.contains('epub english') ||
        categoryLower.contains('full translations') ||
        categoryLower.contains('full epitaka integration') ||
        downloadListItem.type.toLowerCase() == 'database';

    // If local file path, check if zip contains a .db file
    if (!isDbExtension && !downloadListItem.url.startsWith('http')) {
      final localFile = File(downloadListItem.url);
      if (localFile.existsSync()) {
        isDbExtension = downloadService.isDbZip(localFile);
      }
    }

    if (isDbExtension) {
      await downloadService.installDbExtensionFromDesktopZip();
      return;
    }

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

            // autoInstallEnglish is handled in initState — no online fetch needed

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

                bool isEnglishCategory = category == 'Full Translations' ||
                    category == 'Full ePitaka Integration' ||
                    category.toLowerCase().contains('epitaka') ||
                    category.toLowerCase().contains('pali english');

                // Only show RECOMMENDED badge on the top item (index == 0)
                bool isRecommendedCategory = index == 0 && isEnglishCategory;

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
                    initiallyExpanded:
                        isEnglishCategory || Prefs.expandedBookList,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isRecommendedCategory) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    childrenPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    children: items.map<Widget>((item) {
                      bool isEnglishItem =
                          item.filename == 'epitaka_full_en.zip' ||
                              item.filename == 'epitaka_viet_full.zip' ||
                              item.filename.contains('epitaka') ||
                              item.category == 'Full Translations' ||
                              item.category == 'Full ePitaka Integration' ||
                              item.name.toLowerCase().contains('epitaka');

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: isEnglishItem ? 4.0 : 2.0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: isEnglishItem
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2.0,
                                )
                              : BorderSide.none,
                        ),
                        color: isEnglishItem
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.3)
                            : null,
                        child: ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "${item.name} (${item.size})",
                                  style: TextStyle(
                                    fontWeight: isEnglishItem
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isEnglishItem)
                                Icon(
                                  Icons.star,
                                  color: Colors.amber.shade700,
                                  size: 20,
                                ),
                            ],
                          ),
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
    if (!widget.showLocalRestores) {
      try {
        final response = await http.get(Uri.parse(
            'https://cdn.jsdelivr.net/gh/bksubhuti/tpr_downloads@master/download_source_files/download_list_2.json'));
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
              'https://cdn.jsdelivr.net/gh/bksubhuti/tpr_downloads@master/download_source_files/download_list_2.json'));
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

      const legacyZips = {
        'full_en.zip',
        'full_vn.zip',
        'en_full.zip',
        'vn_full.zip',
      };

      for (var file in files) {
        final stat = await file.stat();
        final fileName = file.path.split(Platform.pathSeparator).last;
        final fileNameLower = fileName.toLowerCase();

        // Skip legacy outdated zips
        if (legacyZips.contains(fileNameLower)) {
          continue;
        }

        final sizeInKb = "${(stat.size / 1024).toStringAsFixed(0)} KB";
        final modifiedDate = DateFormat('dd.MM.yyyy').format(stat.modified);

        // --- CROSS-REFERENCE WITH CACHED MASTER LIST ---
        final knownItems = masterList.where((item) {
          if (item.filename == fileName) return true;
          if (item.url.isNotEmpty) {
            try {
              final lastSeg = Uri.parse(item.url).pathSegments.last;
              if (lastSeg == fileName) return true;
            } catch (_) {}
          }
          return false;
        });
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
            'https://cdn.jsdelivr.net/gh/bksubhuti/tpr_downloads@master/download_source_files/download_list_2.json'));

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
