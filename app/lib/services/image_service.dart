import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/failures.dart';

/// Resultat d'une capture : les octets compresses et, si la photo est conservee,
/// le chemin du fichier local.
class CapturedImage {
  const CapturedImage({required this.bytes, required this.mimeType, this.path});

  final Uint8List bytes;
  final String mimeType;
  final String? path;

  int get sizeBytes => bytes.length;
}

/// Capture et preparation des images.
///
/// Les photos sont reduites des la prise de vue, avant tout envoi : une photo
/// brute de telephone pese plusieurs megaoctets, ce qui allonge l'analyse,
/// consomme le forfait mobile de l'utilisateur et fait grimper le cout des
/// appels au modele. Reduire a 1600 px conserve largement de quoi identifier un
/// aliment, pour un fichier de quelques centaines de kilooctets.
class ImageService {
  ImageService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Cote maximal, en pixels. Au-dela, le modele reduit de toute facon l'image.
  static const double _maxDimension = 1600;

  /// Qualite JPEG. 85 est le meilleur compromis taille / lisibilite du texte
  /// des etiquettes.
  static const int _quality = 85;

  /// Taille maximale acceptee par la fonction d'analyse.
  static const int maxUploadBytes = 6 * 1024 * 1024;

  Future<CapturedImage?> pickFromCamera() => _pick(ImageSource.camera);

  Future<CapturedImage?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<CapturedImage?> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        imageQuality: _quality,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) return null;
      // `await` explicite : sans lui, une erreur de lecture remonterait hors du
      // `try` et ne serait plus traduite en message comprehensible.
      return await readFile(file.path);
    } on PlatformException catch (error) {
      throw AppFailure.from(error, context: 'acces a l\'appareil photo');
    }
  }

  /// Lit un fichier image depuis le disque, en verifiant sa taille.
  Future<CapturedImage> readFile(String path) async {
    final file = File(path);
    // `existsSync` plutot que `exists` : une simple interrogation de metadonnees
    // coute moins cher en appel systeme direct qu'en passage par le pool de
    // threads asynchrone.
    if (!file.existsSync()) {
      throw const ProviderFailure(
        'Photo introuvable',
        hint: 'Reprenez la photo : le fichier a peut-etre ete supprime.',
      );
    }

    final bytes = await file.readAsBytes();
    return _finalize(bytes, path);
  }

  CapturedImage fromBytes(Uint8List bytes, {String mimeType = 'image/jpeg'}) {
    if (bytes.isEmpty) {
      throw const ProviderFailure('Photo illisible', hint: 'Reprenez la photo.');
    }
    return CapturedImage(bytes: bytes, mimeType: mimeType);
  }

  CapturedImage _finalize(Uint8List bytes, String? path) {
    if (bytes.isEmpty) {
      throw const ProviderFailure('Photo illisible', hint: 'Reprenez la photo.');
    }
    if (bytes.length > maxUploadBytes) {
      throw const ProviderFailure(
        'Photo trop volumineuse',
        hint: 'Reprenez la photo : elle depasse la taille acceptee.',
      );
    }
    return CapturedImage(bytes: bytes, mimeType: _mimeOf(path), path: path);
  }

  String _mimeOf(String? path) {
    switch (p.extension(path ?? '').toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// Copie une photo dans le dossier prive de l'application, pour la conserver
  /// avec le repas sans dependre du fichier temporaire de la galerie.
  ///
  /// Retourne `null` en cas d'echec : perdre la photo ne doit jamais empecher
  /// d'enregistrer le repas.
  Future<String?> persist(CapturedImage image, String mealId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photos = Directory(p.join(directory.path, 'meal_photos'));
      if (!photos.existsSync()) {
        await photos.create(recursive: true);
      }
      final extension = p.extension(image.path ?? '.jpg');
      final target = File(p.join(photos.path, '$mealId$extension'));
      await target.writeAsBytes(image.bytes, flush: true);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  /// Supprime une photo devenue inutile. Best-effort : l'echec est ignore.
  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Une photo orpheline n'est pas un probleme bloquant.
    }
  }
}
