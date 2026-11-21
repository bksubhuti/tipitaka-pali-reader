import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/download_list_item.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_notifier.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_service.dart';

/// Offers the Digital Pāḷi Dictionary in the reader's own language, once,
/// when TPR shows that language: the app's language, the Pāḷi script, or an
/// installed translation. It goes in next to English DPD as its own
/// dictionary (see DictionaryBook.isDpd).
class DpdLanguageOffer {
  /// Where the packages are. A debug run can take them from this computer:
  /// `--dart-define=TPR_DPD_URL=http://127.0.0.1:8766` with
  /// `python3 -m http.server 8766` in the folder of dpd_*.pkg.zip.
  /// Debug builds take the beta release (dpd-beta), release builds `dpd`.
  static const _release = String.fromEnvironment('TPR_DPD_URL',
      defaultValue: kDebugMode
          ? 'https://github.com/bksubhuti/tpr_downloads/releases/download/dpd-beta'
          : 'https://github.com/bksubhuti/tpr_downloads/releases/download/dpd');

  /// language code -> the dictionary's book id, its name, and the offer in
  /// that language: only a reader of it has any use for the offer.
  static const _languages = {
    'si': _Offer(
      book: 111,
      name: 'සිංහල (Sinhala)',
      title: 'ඩිජිටල් පාලි ශබ්දකෝෂය — සිංහල',
      body: 'ඩිජිටල් පාලි ශබ්දකෝෂය (DPD) දැන් සිංහලෙන් ලබා ගත හැකිය '
          '(AI මගින් පරිවර්තනය කළ, අත්හදා බැලීමේ අනුවාදය). එය ඉංග්‍රීසි '
          'ශබ්දකෝෂය අසලින් එකතු වේ. ශබ්දකෝෂ සැකසුම් තුළ එක් එක් ශබ්දකෝෂය '
          'සක්‍රිය හෝ අක්‍රිය කිරීමට, හෝ පිළිවෙළ වෙනස් කිරීමට හැකිය.\n\n'
          'පසුව සැකසුම් › වැඩි කිරීම වෙතින් ද ස්ථාපනය කළ හැකිය.\n\n'
          'ආසන්න වශයෙන් 11 MB බාගත කරන්නද?',
      notNow: 'දැන් නොවේ',
      install: 'ස්ථාපනය කරන්න',
    ),
    'th': _Offer(
      book: 112,
      name: 'ภาษาไทย (Thai)',
      title: 'พจนานุกรมบาลีดิจิทัล — ภาษาไทย',
      body: 'พจนานุกรมบาลีดิจิทัล (DPD) มีฉบับภาษาไทยแล้ว '
          '(แปลโดย AI รุ่นทดลอง) จะติดตั้งไว้คู่กับฉบับภาษาอังกฤษ '
          'และสามารถเปิด ปิด หรือจัดลำดับแต่ละฉบับได้ในการตั้งค่าพจนานุกรม\n\n'
          'ติดตั้งภายหลังได้ที่ ตั้งค่า › ส่วนขยาย\n\n'
          'ดาวน์โหลดประมาณ 11 MB หรือไม่?',
      notNow: 'ไม่ใช่ตอนนี้',
      install: 'ติดตั้ง',
    ),
    'hi': _Offer(
      book: 113,
      name: 'हिन्दी (Hindi)',
      title: 'डिजिटल पालि शब्दकोश — हिन्दी',
      body: 'डिजिटल पालि शब्दकोश (DPD) अब हिन्दी में उपलब्ध है '
          '(AI द्वारा अनुवादित, बीटा)। यह अंग्रेज़ी शब्दकोश के साथ जोड़ा '
          'जाता है, और शब्दकोश सेटिंग्स में प्रत्येक को चालू या बंद किया जा '
          'सकता है, या उसका क्रम बदला जा सकता है।\n\n'
          'बाद में सेटिंग्स › विस्तार से भी इंस्टॉल कर सकते हैं।\n\n'
          'लगभग 11 MB डाउनलोड करें?',
      notNow: 'अभी नहीं',
      install: 'इंस्टॉल करें',
    ),
    'my': _Offer(
      book: 114,
      name: 'မြန်မာ (Myanmar)',
      title: 'ဒစ်ဂျစ်တယ် ပါဠိ အဘိဓာန် — မြန်မာ',
      body: 'ဒစ်ဂျစ်တယ် ပါဠိ အဘိဓာန် (DPD) ကို မြန်မာဘာသာဖြင့် '
          'ရရှိနိုင်ပါပြီ (AI ဖြင့် ဘာသာပြန်ထားသော စမ်းသပ်ဗားရှင်း)။ '
          '၎င်းကို အင်္ဂလိပ် အဘိဓာန်၏ ဘေးတွင် ထည့်ပေးမည်ဖြစ်ပြီး '
          'အဘိဓာန် ဆက်တင်များတွင် တစ်ခုချင်းစီကို ဖွင့်၊ ပိတ် သို့မဟုတ် '
          'အစီအစဉ် ပြောင်းနိုင်ပါသည်။\n\n'
          'နောက်မှ ဆက်တင်များ › ဖြည့်စွက်ချက်များ မှလည်း ထည့်သွင်းနိုင်ပါသည်။\n\n'
          'ခန့်မှန်းခြေ 11 MB ဒေါင်းလုဒ် လုပ်မလား။',
      notNow: 'နောက်မှ',
      install: 'ထည့်သွင်းမည်',
    ),
  };

  /// Prefs.localeVal of each app language above.
  static const _appLanguages = {1: 'my', 2: 'si', 5: 'hi', 12: 'th'};

  static String _askedPref(String code) => 'dpdLanguageOffered_$code';

  /// The languages TPR is showing, the app's own first.
  static List<String> _wanted() {
    final codes = <String>[
      if (_appLanguages[Prefs.localeVal] != null)
        _appLanguages[Prefs.localeVal]!,
      Prefs.currentScriptLanguage,
      ...DatabaseHelper.installedLanguages,
    ];
    return codes.where(_languages.containsKey).toSet().toList();
  }

  static Future<void> offerIfWanted(BuildContext context) async {
    final db = await DatabaseHelper().database;
    for (final code in _wanted()) {
      if (Prefs.instance.getBool(_askedPref(code)) ?? false) continue;
      final offer = _languages[code]!;
      final have = await db.rawQuery(
          'SELECT 1 FROM dictionary_books WHERE id = ?', [offer.book]);
      if (have.isNotEmpty) continue;
      if (!context.mounted) return;
      // asked once, whatever the answer; it stays in Settings › Downloads
      await Prefs.instance.setBool(_askedPref(code), true);
      if (!context.mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          // English, then the reader's own language
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Digital Pāḷi Dictionary in ${offer.name}'),
              const SizedBox(height: 6),
              Text(offer.title,
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          content: Text(offer.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(offer.notNow),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(offer.install),
            ),
          ],
        ),
      );
      if (install == true && context.mounted) {
        await _install(context, code, offer.name);
      }
      return; // one offer per start
    }
  }

  static Future<void> _install(
      BuildContext context, String code, String name) async {
    final notifier = DownloadNotifier()
      ..downloading = true
      ..message = 'Downloading DPD $name…';
    final item = DownloadListItem(
      name: 'DPD $name',
      type: 'package',
      category: 'Dictionaries',
      url: '$_release/dpd_$code.pkg.zip',
      filename: 'dpd_$code.pkg.zip',
    );
    final job = DownloadService(downloadNotifier: notifier, downloadListItem: item)
        .installPackage();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AnimatedBuilder(
        animation: notifier,
        builder: (context, _) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (notifier.downloading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
              ],
              Text(notifier.message),
            ],
          ),
          actions: [
            if (!notifier.downloading)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
          ],
        ),
      ),
    );
    await job;
    notifier.dispose();
  }
}

class _Offer {
  final int book;
  final String name, title, body, notNow, install;

  const _Offer({
    required this.book,
    required this.name,
    required this.title,
    required this.body,
    required this.notNow,
    required this.install,
  });
}
