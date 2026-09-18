import 'dart:io';

/// Erreurs applicatives, traduites en messages comprehensibles pour
/// l'utilisateur. Aucune trace technique ne doit atteindre l'interface.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.hint, this.isRetryable = false});

  /// Message principal, en francais, affichable tel quel.
  final String message;

  /// Piste d'action proposee a l'utilisateur.
  final String? hint;

  /// Vrai si relancer l'operation a une chance d'aboutir.
  final bool isRetryable;

  /// Construit l'echec correspondant a une exception quelconque.
  static AppFailure from(Object error, {String? context}) {
    if (error is AppFailure) return error;

    if (error is SocketException) {
      return const NetworkFailure();
    }
    if (error is FormatException) {
      return const InvalidResponseFailure();
    }

    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return const NetworkFailure();
    }
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return const TimeoutFailure();
    }

    return UnknownFailure(context: context);
  }

  @override
  String toString() => message;
}

/// Aucune connexion reseau.
class NetworkFailure extends AppFailure {
  const NetworkFailure()
      : super(
          'Pas de connexion internet',
          hint: 'Verifiez votre connexion, puis relancez l\'analyse.',
          isRetryable: true,
        );
}

/// Le serveur n'a pas repondu dans le delai imparti.
class TimeoutFailure extends AppFailure {
  const TimeoutFailure()
      : super(
          'L\'analyse a pris trop de temps',
          hint: 'Reessayez avec une photo plus petite ou une connexion plus stable.',
          isRetryable: true,
        );
}

/// Reponse illisible ou inattendue.
class InvalidResponseFailure extends AppFailure {
  const InvalidResponseFailure()
      : super(
          'Reponse inattendue du service',
          hint: 'Reessayez dans un instant.',
          isRetryable: true,
        );
}

/// Aucun aliment n'a ete reconnu sur la photo.
class NoFoodDetectedFailure extends AppFailure {
  const NoFoodDetectedFailure()
      : super(
          'Aucun aliment reconnu',
          hint: 'Reprenez la photo en cadrant mieux l\'assiette, avec plus de lumiere.',
        );
}

/// La cle d'acces est absente ou refusee.
class MissingCredentialFailure extends AppFailure {
  const MissingCredentialFailure({this.rejected = false})
      : super(
          'Cle d\'analyse absente ou refusee',
          hint: 'Renseignez une cle valide dans Reglages, section Analyse des repas.',
        );

  /// Vrai lorsque le fournisseur a explicitement refuse la cle fournie.
  final bool rejected;
}

/// Le fournisseur a refuse la requete pour une raison de fond.
class ProviderFailure extends AppFailure {
  /// [isRetryable] distingue une panne passagere (5xx, a relancer) d'un refus
  /// de fond (4xx, ou relancer ne changerait rien). Sans ce parametre, tous les
  /// echecs du fournisseur seraient traites de la meme facon dans l'interface.
  const ProviderFailure(
    super.message, {
    super.hint,
    super.isRetryable,
    this.statusCode,
  });

  final int? statusCode;
}

/// Quota d'appels depasse.
class RateLimitFailure extends AppFailure {
  const RateLimitFailure({this.retryAfterS})
      : super(
          'Trop de requetes',
          hint: 'Patientez quelques secondes avant de relancer l\'analyse.',
          isRetryable: true,
        );

  final int? retryAfterS;
}

/// Produit introuvable dans la base de produits.
class ProductNotFoundFailure extends AppFailure {
  const ProductNotFoundFailure(this.barcode)
      : super(
          'Produit inconnu',
          hint: 'Ce code-barres n\'est pas dans la base. Vous pouvez saisir les valeurs de l\'etiquette.',
        );

  final String barcode;
}

/// Erreur non identifiee.
class UnknownFailure extends AppFailure {
  UnknownFailure({String? context})
      : super(
          'Une erreur est survenue',
          hint: context == null
              ? 'Reessayez. Si le probleme persiste, signalez-le depuis Reglages.'
              : 'Contexte : $context',
          isRetryable: true,
        );
}
