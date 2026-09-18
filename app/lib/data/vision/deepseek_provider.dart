import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/failures.dart';
import '../../models/analysis_result.dart';
import 'label_prompt.dart' as label_prompt;
import 'meal_prompt.dart' as meal_prompt;
import 'vision_provider.dart';

/// Analyse directe aupres d'un fournisseur compatible OpenAI.
///
/// La cle n'est jamais presente dans le binaire : elle est saisie par
/// l'utilisateur et conservee dans le trousseau du systeme (Keychain sur iOS,
/// Keystore sur Android). Ce mode ne necessite aucun backend.
class DeepSeekVisionProvider implements VisionProvider {
  DeepSeekVisionProvider({
    required this.apiKey,
    http.Client? client,
    this.baseUrl = AppConfig.providerBaseUrl,
    this.model = AppConfig.providerModel,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final String model;
  final http.Client _client;

  /// Le modele peut renvoyer un contenu vide en mode JSON ; on retente alors.
  static const int _maxAttempts = 3;

  /// Delai maximal d'une requete. Une analyse de photo prend typiquement
  /// quelques secondes ; au-dela, mieux vaut rendre la main a l'utilisateur.
  static const Duration _timeout = Duration(seconds: 75);

  @override
  String get id => 'deepseek-direct';

  @override
  String get label => 'Cle personnelle';

  @override
  bool get isConfigured => apiKey.trim().isNotEmpty;

  @override
  Future<MealAnalysisResult> analyzeMeal(MealAnalysisRequest request) async {
    _ensureConfigured();

    final blocks = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': meal_prompt.buildMealUserPrompt(
          portionHint: request.portionHint,
          userHint: request.userHint,
          hasSecondImage: request.hasSecondImage,
        ),
      },
      {
        'type': 'image_url',
        'image_url': {
          'url':
              'data:${request.mimeType};base64,${base64Encode(request.image)}',
          'detail': 'high',
        },
      },
    ];

    if (request.hasSecondImage) {
      blocks.add({
        'type': 'image_url',
        'image_url': {
          'url':
              'data:${request.secondMimeType ?? request.mimeType};base64,${base64Encode(request.secondImage!)}',
          'detail': 'high',
        },
      });
    }

    final content = await _chat(
      systemPrompt: meal_prompt.mealSystemPrompt,
      userBlocks: blocks,
      maxTokens: 2048,
      temperature: 0.2,
    );

    final result = parseMealAnalysis(
      content,
      promptVersion: meal_prompt.promptVersion,
    );
    if (result.isEmpty) throw const NoFoodDetectedFailure();
    return result;
  }

  @override
  Future<LabelExtraction> analyzeLabel(LabelAnalysisRequest request) async {
    _ensureConfigured();

    final blocks = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': label_prompt.buildLabelUserPrompt(
          hasSecondImage: request.hasSecondImage,
        ),
      },
      {
        'type': 'image_url',
        'image_url': {
          'url':
              'data:${request.mimeType};base64,${base64Encode(request.image)}',
          'detail': 'high',
        },
      },
    ];

    if (request.hasSecondImage) {
      blocks.add({
        'type': 'image_url',
        'image_url': {
          'url':
              'data:${request.secondMimeType ?? request.mimeType};base64,${base64Encode(request.secondImage!)}',
          'detail': 'high',
        },
      });
    }

    final content = await _chat(
      systemPrompt: label_prompt.labelSystemPrompt,
      userBlocks: blocks,
      maxTokens: 1200,
      temperature: 0.1,
    );

    return parseLabelExtraction(
      content,
      promptVersion: label_prompt.promptVersion,
    );
  }

  void _ensureConfigured() {
    if (!isConfigured) throw const MissingCredentialFailure();
  }

  /// Appel `chat/completions`, avec reprise sur contenu vide.
  Future<String> _chat({
    required String systemPrompt,
    required List<Map<String, dynamic>> userBlocks,
    required int maxTokens,
    required double temperature,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userBlocks},
      ],
      'response_format': {'type': 'json_object'},
      'max_tokens': maxTokens,
      'temperature': temperature,
    });

    Object? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        final response = await _client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: body,
            )
            .timeout(_timeout);

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const MissingCredentialFailure(rejected: true);
        }
        if (response.statusCode == 429) {
          throw const RateLimitFailure();
        }
        if (response.statusCode >= 500) {
          throw ProviderFailure(
            'Le service d\'analyse est momentanement indisponible',
            hint: 'Reessayez dans quelques instants.',
            statusCode: response.statusCode,
          );
        }
        if (response.statusCode >= 400) {
          throw ProviderFailure(
            'Requete refusee par le service d\'analyse',
            hint: _providerMessage(response.body),
            statusCode: response.statusCode,
          );
        }

        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final content = _extractContent(decoded);
        if (content != null && content.trim().isNotEmpty) return content;

        // Contenu vide : probleme connu du mode JSON, on retente.
        lastError = const InvalidResponseFailure();
      } on AppFailure catch (error) {
        // Une erreur de fond (cle refusee, quota) ne se retente pas.
        if (error is MissingCredentialFailure || error is RateLimitFailure) {
          rethrow;
        }
        if (error is ProviderFailure && (error.statusCode ?? 0) < 500) rethrow;
        lastError = error;
      } on SocketException {
        lastError = const NetworkFailure();
      } on http.ClientException {
        lastError = const NetworkFailure();
      } catch (error) {
        lastError = AppFailure.from(error);
      }

      if (attempt < _maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }

    throw lastError is AppFailure ? lastError : const InvalidResponseFailure();
  }

  String? _extractContent(Object? decoded) {
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final message = (choices.first as Map)['message'];
    if (message is! Map) return null;
    final content = message['content'];
    return content is String ? content : null;
  }

  /// Message d'erreur renvoye par le fournisseur, s'il est exploitable.
  String? _providerMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) {
            return message.length > 200 ? message.substring(0, 200) : message;
          }
        }
      }
    } on FormatException {
      // Corps non JSON : rien d'exploitable a montrer.
    }
    return null;
  }
}
