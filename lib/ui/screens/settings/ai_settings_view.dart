import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:tipitaka_pali/l10n/app_localizations.dart';

class AiSettingsView extends StatefulWidget {
  const AiSettingsView({super.key});

  @override
  State<AiSettingsView> createState() => _AiSettingsViewState();
}

class _AiSettingsViewState extends State<AiSettingsView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _apiKeyController;
  late final TextEditingController _promptController;
  late final TextEditingController _geminiKeyController;

  Map<String, String> _modelLabels = {};
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: Prefs.openRouterApiKey);
    _promptController = TextEditingController(text: Prefs.openRouterPrompt);
    _geminiKeyController =
        TextEditingController(text: Prefs.geminiDirectApiKey);

    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      Directory dir;
      dir = await getApplicationSupportDirectory();
      final file = File(join(dir.path, 'openrouter_models.json'));

      if (await file.exists()) {
        final contents = await file.readAsString();
        final Map<String, dynamic> data = json.decode(contents);
        if (mounted) {
          setState(() {
            _modelLabels = data.map((k, v) => MapEntry(k, v.toString()));
            _selectedModel = _modelLabels.containsKey(Prefs.openRouterModel)
                ? Prefs.openRouterModel
                : 'deepseek/deepseek-chat-v3-0324:free';
            Prefs.openRouterModel = _selectedModel!; // persist default
          });
        }
      } else {
        const defaultModels = {
          // Free models
          'google/gemini-2.0-flash-exp:free': 'Gemini Flash 2.0 (Free)',
          'deepseek/deepseek-chat-v3-0324:free':
              'DeepSeek -V3 (Free w/ tkn acct)',
          'meta-llama/llama-4-maverick:free': 'Llama-4 Maverick (Free)',
          'meta-llama/llama-4-scout:free': 'Llama-4 Scout (Free)',
          'mistralai/mistral-small-3.1-24b-instruct:free': 'Mistral 3.1 (Free)',

          // Paid models (prices included via raw strings so $ is literal)
          'openai/gpt-4.1': r'GPT-4.1 ($2/$8)',
          'openai/chatgpt-4o-latest': r'GPT-4o ($5/$15)',
          'openai/gpt-5': r'GPT-5 ($1.25/$10)',
          'x-ai/grok-3-mini': r'Grok 3 Mini ($0.3/$0.5)',
          'x-ai/grok-4': r'Grok 4 ($3/$15)',
          'google/gemini-2.5-pro': r'Gemini 2.5 Pro ($1.25/$10)',
        };

        await file.writeAsString(json.encode(defaultModels));
        if (mounted) {
          setState(() {
            _modelLabels = defaultModels;
            _selectedModel = 'google/gemini-2.0-flash-exp:free';
            Prefs.openRouterModel = _selectedModel!;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load models: $e');
    }
  }

  Future<void> _updateModelsFromGitHub(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(
          'https://github.com/bksubhuti/tpr_downloads/raw/master/download_source_files/openrouter_models.json'));

      if (response.statusCode == 200) {
        final newData = json.decode(response.body);
        Directory dir;
        dir = await getApplicationSupportDirectory();
        final file = File(join(dir.path, 'openrouter_models.json'));
        await file.writeAsString(json.encode(newData));
        if (mounted) {
          setState(() {
            _modelLabels = Map<String, String>.from(newData);
            _selectedModel = _modelLabels.containsKey(Prefs.openRouterModel)
                ? Prefs.openRouterModel
                : null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)!.updateModelList)),
          );
        }
      } else {
        throw Exception('Failed to fetch models');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${AppLocalizations.of(context)!.updateModelList}: $e')),
        );
      }
    }
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.howToGetApiKey),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context)!.apiKeyInstructions1),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context)!.apiKeyInstructions2),
              Text(AppLocalizations.of(context)!.apiKeyInstructions3),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context)!.apiKeyInstructions4),
              Text(AppLocalizations.of(context)!.apiKeyInstructions5),
              Text(AppLocalizations.of(context)!.apiKeyInstructions6),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context)!.apiKeyInstructions7),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(context)!.close),
          ),
          ElevatedButton(
            child: Text(AppLocalizations.of(context)!.getOpenRouterKey),
            onPressed: () async {
              final url = Uri.parse('https://openrouter.ai');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
          ),
          ElevatedButton(
            child: Text(AppLocalizations.of(context)!.getGenminiKey),
            onPressed: () async {
              final url = Uri.parse('https://aistudio.google.com/app/apikey');
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _promptController.dispose();
    _geminiKeyController.dispose();

    super.dispose();
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
                  SwitchListTile(
                    title: const Text("OpenRouter / Gemini Direct"),
                    value: Prefs.useGeminiDirect,
                    onChanged: (val) {
                      setState(() {
                        Prefs.useGeminiDirect = val;
                      });
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left column: OpenRouter + Gemini keys stacked
                      Expanded(
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            if (!Prefs.useGeminiDirect)
                              TextFormField(
                                controller: _apiKeyController,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.of(context)!
                                      .openRouterAiKey,
                                ),
                              ),
                            if (Prefs.useGeminiDirect)
                              TextFormField(
                                controller: _geminiKeyController,
                                decoration: const InputDecoration(
                                  labelText: 'Gemini API Key (direct)',
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right column: buttons stacked
                      Column(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.help_outline),
                            label: Text(AppLocalizations.of(context)!.key),
                            onPressed: () => _showHelpDialog(context),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.save),
                            label: Text(AppLocalizations.of(context)!.save),
                            onPressed: () {
                              Prefs.openRouterApiKey = _apiKeyController.text;
                              Prefs.geminiDirectApiKey =
                                  _geminiKeyController.text;
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
                  const SizedBox(height: 24.0),
                  if (!Prefs.useGeminiDirect)
                    DropdownButtonFormField<String>(
                      value: _selectedModel,
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.openRouterAiModel,
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedModel = value;
                            Prefs.openRouterModel = value;
                          });
                        }
                      },
                      items: _modelLabels.entries.map((entry) {
                        return DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value,
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                    ),
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
                  if (!Prefs.useGeminiDirect)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.download),
                        label:
                            Text(AppLocalizations.of(context)!.updateModelList),
                        onPressed: () => _updateModelsFromGitHub(context),
                      ),
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
