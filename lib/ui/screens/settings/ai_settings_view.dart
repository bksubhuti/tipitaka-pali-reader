import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/ui/widgets/ai_help_dialog.dart';

class AiSettingsView extends StatefulWidget {
  const AiSettingsView({super.key});

  @override
  State<AiSettingsView> createState() => _AiSettingsViewState();
}

class _AiSettingsViewState extends State<AiSettingsView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _promptController;
  late final TextEditingController _geminiKeyController;
  late final TextEditingController _openRouterKeyController;
  late final TextEditingController _openRouterHeavyModelController;
  late final TextEditingController _openRouterLightModelController;

  bool _isFetchingModels = false;
  List<String> _geminiModels = [];
  String? _selectedHeavyModel;
  String? _selectedLightModel;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: Prefs.openRouterPrompt);
    _geminiKeyController =
        TextEditingController(text: Prefs.geminiDirectApiKey);
    _openRouterKeyController = TextEditingController(text: Prefs.openRouterKey);
    _openRouterHeavyModelController =
        TextEditingController(text: Prefs.openRouterHeavyModel);
    _openRouterLightModelController =
        TextEditingController(text: Prefs.openRouterLightModel);

    _fetchGeminiModels(_geminiKeyController.text);

    // Fetch latest sponsored config so UI updates
    Prefs.fetchSponsoredModelConfig().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _fetchGeminiModels(String apiKey) async {
    if (apiKey.isEmpty) return;
    setState(() => _isFetchingModels = true);
    final endpoint =
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(endpoint));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final modelsList = data['models'] as List?;

        if (modelsList != null) {
          final activeModels = modelsList
              .where((m) {
                final name = m['name'] as String? ?? '';
                final methods = m['supportedGenerationMethods'] as List? ?? [];
                // Exclude ones specifically meant for image or tts
                return !name.contains('image') &&
                    !name.contains('tts') &&
                    !name.contains('vision') &&
                    methods.contains('generateContent');
              })
              .map((m) => (m['name'] as String).replaceFirst('models/', ''))
              .toList();

          if (mounted) {
            setState(() {
              _geminiModels = activeModels;
              if (_geminiModels.isNotEmpty) {
                if (_geminiModels.contains(Prefs.aiHeavyModel)) {
                  _selectedHeavyModel = Prefs.aiHeavyModel;
                } else {
                  if (_geminiModels.contains('gemini-1.5-flash')) {
                    _selectedHeavyModel = 'gemini-1.5-flash';
                  } else {
                    _selectedHeavyModel = _geminiModels.firstWhere(
                        (m) => m.contains('pro'),
                        orElse: () => _geminiModels.first);
                  }
                  Prefs.aiHeavyModel = _selectedHeavyModel!;
                }

                final flashModels =
                    _geminiModels.where((m) => m.contains('flash')).toList();

                if (flashModels.contains(Prefs.aiLightModel)) {
                  _selectedLightModel = Prefs.aiLightModel;
                } else {
                  if (_geminiModels.contains('gemini-1.5-flash-8b')) {
                    _selectedLightModel = 'gemini-1.5-flash-8b';
                  } else {
                    _selectedLightModel = flashModels.isNotEmpty
                        ? flashModels.first
                        : _geminiModels.first;
                  }
                  Prefs.aiLightModel = _selectedLightModel!;
                }
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching Gemini models: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingModels = false);
      }
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _geminiKeyController.dispose();
    _openRouterKeyController.dispose();
    _openRouterHeavyModelController.dispose();
    _openRouterLightModelController.dispose();
    super.dispose();
  }

  Widget _buildBulletPoint(
      BuildContext context, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16, height: 1.4)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.4),
                children: [
                  TextSpan(
                      text: title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showModelInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('AI Model Configuration'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Section 1: How the App Works
                RichText(
                  text: TextSpan(
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.4),
                    children: const [
                      TextSpan(
                          text:
                              'To save usage rates, the AI algorithm uses the heavy model only when '),
                      TextSpan(
                          text: 'fully necessary',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(
                          text:
                              '. The light model is for less intensive processing.\n\n'),
                      TextSpan(
                          text:
                              'The models are fetched from a real-time list. You will need to decide which models work best within your tier. If you have paid access, performance will improve.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Section 2: Recommendations Title
                Text(
                  'Recommended Configurations:',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // Bullet Points for Recommendations
                _buildBulletPoint(
                    context,
                    'Gemini 1.5 Flash (Heavy) & 1.5 Flash-8B (Light):',
                    ' Balanced performance.'),
                _buildBulletPoint(
                    context,
                    'Gemini 1.5 Flash-8B (Both Heavy & Light):',
                    ' Best overall usage limits and efficiency.'),

                const SizedBox(height: 12),
                Text(
                  'Note: You can consult with AI chat windows as models evolve and older ones become obsolete or restricted.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 16),
                Text(
                  'If your usage limits are exhausted, the system will become extremely slow or temporarily stop working.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final url =
                    Uri.parse('https://aistudio.google.com/rate-limit/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Check the "Rate Limit" in aiStudio'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final promptOptions = {
      'line_by_line': AppLocalizations.of(context)!.translatePaliLineByLine,
      'translate': AppLocalizations.of(context)!.translatePali,
      'grammar': AppLocalizations.of(context)!.explainGrammar,
      'summarize': AppLocalizations.of(context)!.summarize,
    };

    final promptValues = {
      'line_by_line':
          AppLocalizations.of(context)!.translatePaliLineByLinePrompt,
      'translate': AppLocalizations.of(context)!.translatePaliPrompt,
      'grammar': AppLocalizations.of(context)!.explainGrammarPrompt,
      'summarize': AppLocalizations.of(context)!.summarizePrompt,
    };

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.psychology),
        title: Text(
          AppLocalizations.of(context)!.aiSettings,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  ToggleButtons(
                    borderRadius: BorderRadius.circular(8.0),
                    onPressed: (int index) {
                      setState(() {
                        Prefs.aiProviderMode = index;
                      });
                    },
                    isSelected: [
                      Prefs.aiProviderMode == 0,
                      Prefs.aiProviderMode == 1,
                      Prefs.aiProviderMode == 2,
                    ],
                    children: const <Widget>[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text('Gemini'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text('BYOK'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text('Sponsored'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  height: 1.5,
                                ),
                            children: const [
                              TextSpan(
                                  text: 'Sponsored: ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(
                                  text:
                                      'A gift to help you get started or for those in restricted regions. May the generous donor gain great merit!'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        height: 1.5,
                                      ),
                                  children: const [
                                    TextSpan(
                                        text: 'Gemini: ',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    TextSpan(
                                        text:
                                            'Best choice! Free, much faster, higher quality, and more daily queries. (Recommended) '),
                                  ],
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 0),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.help_outline, size: 16),
                              label: Text(AppLocalizations.of(context)!.key),
                              onPressed: () => showAiHelpDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        RichText(
                          text: TextSpan(
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  height: 1.5,
                                ),
                            children: const [
                              TextSpan(
                                  text: 'BYOK: ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(
                                  text:
                                      'Open Router, select any model (more complex, but fun).'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  if (Prefs.aiProviderMode == 0) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column: Gemini key
                        Expanded(
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _geminiKeyController,
                                decoration: const InputDecoration(
                                  labelText: 'Gemini API Key',
                                  hintText: 'Enter gemini key',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Right column: save button
                        Column(
                          children: [
                            const SizedBox(height: 12),
                            TextButton.icon(
                              icon: const Icon(Icons.save),
                              label: Text(AppLocalizations.of(context)!.save),
                              onPressed: () {
                                Prefs.geminiDirectApiKey =
                                    _geminiKeyController.text;
                                _fetchGeminiModels(_geminiKeyController.text);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!
                                        .openRouterKeySaved),
                                  ),
                                );
                                _showModelInfoDialog(context);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    if (_isFetchingModels)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    else if (_geminiModels.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Check "Rate Limit" in aiStudio'),
                          onPressed: () async {
                            final url = Uri.parse(
                                'https://aistudio.google.com/rate-limit/');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedHeavyModel,
                        decoration: const InputDecoration(
                          labelText: 'Gemini Heavy Model',
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedHeavyModel = value;
                              Prefs.aiHeavyModel = value;
                            });
                          }
                        },
                        items: _geminiModels.map((modelName) {
                          return DropdownMenuItem(
                            value: modelName,
                            child: Text(modelName,
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: Row(
                          children: [
                            const Text(
                              '1.5 flash recommended',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            IconButton(
                              icon: const Icon(Icons.info_outline,
                                  size: 20, color: Colors.grey),
                              onPressed: () => _showModelInfoDialog(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedLightModel,
                        decoration: const InputDecoration(
                          labelText: 'Gemini Light Model',
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedLightModel = value;
                              Prefs.aiLightModel = value;
                            });
                          }
                        },
                        items: _geminiModels
                            .where((m) => m.contains('flash'))
                            .map((modelName) {
                          return DropdownMenuItem(
                            value: modelName,
                            child: Text(modelName,
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: Row(
                          children: [
                            const Text(
                              '1.5 flash 8b recommended',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            IconButton(
                              icon: const Icon(Icons.info_outline,
                                  size: 20, color: Colors.grey),
                              onPressed: () => _showModelInfoDialog(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else if (Prefs.aiProviderMode == 1) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _openRouterKeyController,
                            decoration: const InputDecoration(
                              labelText: 'OpenRouter API Key',
                              hintText: 'Enter OpenRouter key',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.help_outline),
                              label: Text(AppLocalizations.of(context)!.key),
                              onPressed: () => showAiHelpDialog(context),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.save),
                              label: Text(AppLocalizations.of(context)!.save),
                              onPressed: () {
                                Prefs.openRouterKey =
                                    _openRouterKeyController.text;
                                Prefs.openRouterHeavyModel =
                                    _openRouterHeavyModelController.text;
                                Prefs.openRouterLightModel =
                                    _openRouterLightModelController.text;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!
                                        .openRouterKeySaved),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _openRouterHeavyModelController,
                      decoration: const InputDecoration(
                        labelText: 'OpenRouter Heavy Model',
                        hintText: 'e.g. anthropic/claude-3.5-sonnet',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => Prefs.openRouterHeavyModel = val,
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _openRouterLightModelController,
                      decoration: const InputDecoration(
                        labelText: 'OpenRouter Light Model',
                        hintText: 'e.g. meta-llama/llama-3-8b-instruct',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => Prefs.openRouterLightModel = val,
                    ),
                  ] else if (Prefs.aiProviderMode == 2) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.verified,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Using Sponsored\nCommunity Key',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                                'Service: ${Prefs.aiSponsoredProvider.isEmpty ? "openrouter.ai" : Prefs.aiSponsoredProvider}'),
                            const SizedBox(height: 8),
                            Text(
                                'Heavy Model: ${Prefs.aiSponsoredHeavyModel.isEmpty ? "deepseek/deepseek-v4-pro" : Prefs.aiSponsoredHeavyModel}'),
                            const SizedBox(height: 8),
                            Text(
                                'Light Model: ${Prefs.aiSponsoredLightModel.isEmpty ? "google/gemini-1.5-flash-8b" : Prefs.aiSponsoredLightModel}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16.0),
                  DropdownButtonFormField<String>(
                    value: Prefs.openRouterPromptKey, // e.g., "translate"
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.chooseAiPrompt,
                    ),
                    onChanged: (String? key) {
                      if (key != null) {
                        setState(() {
                          Prefs.openRouterPromptKey = key;
                          Prefs.openRouterPrompt = promptValues[key]!;
                          _promptController.text = Prefs.openRouterPrompt;
                        });
                      }
                    },
                    items: promptOptions.entries.map((entry) {
                      return DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _promptController,
                    maxLines: null,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context)!.customAiPromptLabel,
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      Prefs.openRouterPrompt = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: Text(
                          AppLocalizations.of(context)!.resetAiPromptDefault),
                      onPressed: () {
                        setState(() {
                          Prefs.openRouterPrompt = defaultOpenRouterPrompt;
                          _promptController.text = defaultOpenRouterPrompt;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.of(context)!
                                .resetAiPromptDefault),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
