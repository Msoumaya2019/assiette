import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/failures.dart';
import '../../models/analysis_result.dart';
import 'vision_provider.dart';

/// Analyse via une fonction serveur qui detient la cle du fournisseur.
///
/// Mode prevu pour la publication : l'application ne contient alors aucun
/// secret exploitable, meme decompilee.
class ProxyVisionProvider implements VisionProvider {
  ProxyVisionProvider({
    required this.endpoint,
    http.Client? client,
    this.authToken,
  }) : _client = client ?? http.Client();

  /// URL de base des fonctions, par exemple
  /// `https://<projet>.supabase.co/functions/v1`.
  final String endpoint;

  /// Jeton de session, une fois l'authentification active.
  final String? authToken;

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 90);

  @override
  String get id => 'proxy';

  @override
  String get label => 'Service securise';

  @override
  bool get isConfigured => endpoint.trim().isNotEmpty;

  @override
  Future<MealAnalysisResult> analyzeMeal(MealAnalysisRequest request) async {
    final payload = <String, dynamic>{
      'imageBase64': base64Encode(request.image),
      'mimeType': request.mimeType,
      if (request.hasSecondImage)
        'secondImageBase64': base64Encode(request.secondImage!),
      if (request.hasSecondImage)
        'secondMimeType': request.secondMimeType ?? request.mimeType,
      if (request.portionHint != null) 'portionHint': request.portionHint,
      if (request.userHint != null && request.userHint!.trim().isNotEmpty)
        'userHint': request.userHint!.trim(),
    };

    final decoded = await _post('analyze-meal', payload);
    final result = parseMealAnalysis(jsonEncode(decoded));
    if (result.isEmpty) throw const NoFoodDetectedFailure();
    return result;
  }

  @override
  Future<LabelExtraction> analyzeLabel(LabelAnalysisRequest request) async {
    final payload = <String, dynamic>{
      'imageBase64': base64Encode(request.image),
      'mimeType': request.mimeType,
      if (request.hasSecondImage)
        'secondImageBase64': base64Encode(request.secondImage!),
      if (request.hasSecondImage)
        'secondMimeType': request.secondMimeType ?? request.mimeType,
    };

    final decoded = await _post('analyze-label', payload);
    return parseLabelExtraction(jsonEncode(decoded));
  }

  Future<Map<String, dynamic>> _post(
    String function,
    Map<String, dynamic> payload,
  ) async {
    if (!isConfigured) {
      throw const MissingCredentialFailure();
    }

    final uri = Uri.parse(
      '${endpoint.replaceAll(RegExp(r'/+$'), '')}/$function',
    );

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (authToken != null) 'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      final decoded = response.body.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
      final map = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};

      if (response.statusCode == 200) return map;

      final serverMessage = map['message']?.toString();

      switch (response.statusCode) {
        case 401:
        case 403:
          throw const MissingCredentialFailure(rejected: true);
        case 413:
          throw const ProviderFailure(
            'Photo trop volumineuse',
            hint:
                'Reprenez la photo : l\'application la compresse automatiquement.',
          );
        case 415:
          throw const ProviderFailure(
            'Format d\'image non pris en charge',
            hint: 'Utilisez une photo JPEG ou PNG.',
          );
        case 429:
          throw RateLimitFailure(
            retryAfterS: (map['retryAfterS'] as num?)?.toInt(),
          );
        default:
          if (response.statusCode >= 500) {
            throw ProviderFailure(
              serverMessage ??
                  'Le service d\'analyse est momentanement indisponible',
              hint: 'Reessayez dans quelques instants.',
              statusCode: response.statusCode,
            );
          }
          throw ProviderFailure(
            serverMessage ?? 'L\'analyse a echoue',
            statusCode: response.statusCode,
          );
      }
    } on AppFailure {
      rethrow;
    } on SocketException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    } on FormatException {
      throw const InvalidResponseFailure();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
