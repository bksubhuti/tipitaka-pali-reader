import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

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
                  if (_geminiModels.contains('gemini-3.6-flash')) {
                    _selectedHeavyModel = 'gemini-3.6-flash';
                  } else if (_geminiModels.contains('gemini-3.5-flash')) {
                    _selectedHeavyModel = 'gemini-3.5-flash';
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
                  if (_geminiModels.contains('gemini-3.5-flash-lite')) {
                    _selectedLightModel = 'gemini-3.5-flash-lite';
                  } else if (_geminiModels.contains('gemini-3.1-flash-lite')) {
                    _selectedLightModel = 'gemini-3.1-flash-lite';
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
                    'Gemini-3.6-flash (Heavy) & Gemini-3.5-flash-lite (Light):',
                    ' Balanced performance.'),
                _buildBulletPoint(
                    context,
                    'Gemini-3.1-flash-lite (Both Heavy & Light):',
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
            TextButton.icon(
              icon: const Icon(Icons.speed),
              onPressed: () async {
                final url =
                    Uri.parse('https://aistudio.google.com/rate-limit/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              label: const Text('Check "Rate Limit" in aiStudio'),
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

  String _formatKeyPreview(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 8) return trimmed;
    return '${trimmed.substring(0, 4)}....................${trimmed.substring(trimmed.length - 4)}';
  }

  Widget _buildKeySetupRow(BuildContext context, int mode, String key) {
    final trimmedKey = key.trim();
    final isKeySetup = trimmedKey.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isKeySetup) ...[
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 6),
              Text(
                _formatKeyPreview(trimmedKey),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () => _showSetupDialog(context, mode),
            icon: const Icon(Icons.settings_outlined),
            label: Text(isKeySetup ? 'Change Key Now' : 'Setup Now'),
          ),
        ),
      ],
    );
  }

  void _showSetupDialog(BuildContext context, int mode) {
    if (mode == 0) {
      _geminiKeyController.text = Prefs.geminiDirectApiKey;
    } else {
      _openRouterKeyController.text = Prefs.openRouterKey;
    }
    showDialog(
      context: context,
      builder: (dialogContext) {
        final isSetup = mode == 0
            ? Prefs.geminiDirectApiKey.trim().isNotEmpty
            : Prefs.openRouterKey.trim().isNotEmpty;
        return AlertDialog(
          title: Text(mode == 0
              ? (isSetup ? 'Change Gemini API Key' : 'Setup Gemini API Key')
              : (isSetup
                  ? 'Change OpenRouter API Key'
                  : 'Setup OpenRouter API Key')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mode == 0) ...[
                  Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.ondemand_video),
                      label: const Text('Watch Key Instructions'),
                      onPressed: () async {
                        final url = Uri.parse(
                            'https://www.youtube.com/watch?v=zgmkYP7UqtU');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(AppLocalizations.of(context)!.apiKeyInstructions1),
                  const SizedBox(height: 12),
                  Text(AppLocalizations.of(context)!.apiKeyInstructions2),
                  Text(AppLocalizations.of(context)!.apiKeyInstructions3),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton(
                      child: Text(AppLocalizations.of(context)!.getGenminiKey),
                      onPressed: () async {
                        final url =
                            Uri.parse('https://aistudio.google.com/app/apikey');
                        if (await canLaunchUrl(url)) await launchUrl(url);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _geminiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Gemini API Key',
                      hintText: 'Enter gemini key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else if (mode == 1) ...[
                  Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.ondemand_video),
                      label: const Text('Watch OpenRouter Tutorial'),
                      onPressed: () async {
                        final url = Uri.parse('https://youtu.be/We_kBUyT10E');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _openRouterKeyController,
                    decoration: const InputDecoration(
                      labelText: 'OpenRouter API Key',
                      hintText: 'Enter OpenRouter key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context)!.close),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: Text(AppLocalizations.of(context)!.save),
              onPressed: () {
                if (mode == 0) {
                  Prefs.geminiDirectApiKey = _geminiKeyController.text;
                  _fetchGeminiModels(_geminiKeyController.text);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            AppLocalizations.of(context)!.openRouterKeySaved)),
                  );
                } else {
                  Prefs.openRouterKey = _openRouterKeyController.text;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            AppLocalizations.of(context)!.openRouterKeySaved)),
                  );
                }
                if (mounted) {
                  setState(() {});
                }
                Navigator.of(dialogContext).pop();
              },
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
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text('Gemini', style: TextStyle(fontSize: 13)),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child:
                            Text('OpenRouter', style: TextStyle(fontSize: 13)),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text('Dāna', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12.0),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 2,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (Prefs.aiProviderMode == 2)
                                  RichText(
                                    text: TextSpan(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(height: 1.5),
                                      children: const [
                                        TextSpan(
                                            text: 'Dāna Mode:\n',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        TextSpan(
                                            text:
                                                'A gift to help you get started or for those in restricted regions. May the generous donor gain great merit!'),
                                      ],
                                    ),
                                  ),
                                if (Prefs.aiProviderMode == 0) ...[
                                  RichText(
                                    text: TextSpan(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(height: 1.5),
                                      children: const [
                                        TextSpan(
                                            text: 'Gemini Direct Mode:\n',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        TextSpan(
                                            text:
                                                'Best choice! Free, much faster, higher quality, and more daily queries. (Recommended) '),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildKeySetupRow(
                                      context, 0, Prefs.geminiDirectApiKey),
                                  const SizedBox(height: 8),
                                ],
                                if (Prefs.aiProviderMode == 1) ...[
                                  RichText(
                                    text: TextSpan(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(height: 1.5),
                                      children: const [
                                        TextSpan(
                                            text: 'OpenRouter:\n',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        TextSpan(
                                            text:
                                                'In Myanmar, China or other countries, you cannot use Google Gemini and other models due to geographic restrictions. OpenRouter lets you choose the allowable AI model you want, but there are costs involved.'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildKeySetupRow(
                                      context, 1, Prefs.openRouterKey),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  if (Prefs.aiProviderMode == 0) ...[
                    if (_isFetchingModels)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    else if (_geminiModels.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.speed),
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
                              '3.6 Flash recommended',
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
                              '3.1-Flash-lite recommended',
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
                                  'Using Dāna\nCommunity Key',
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
                            const SizedBox(height: 12),
                            Material(
                              color: Colors.transparent,
                              child: SwitchListTile(
                                title: const Text(
                                    'Bypass OpenRouter for DeepSeek'),
                                subtitle: const Text(
                                    'Route directly to deepseek.com (temporary override)'),
                                value: Prefs.aiSponsoredBypassOpenRouter,
                                onChanged: (val) {
                                  setState(() {
                                    Prefs.aiSponsoredBypassOpenRouter = val;
                                  });
                                },
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
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
