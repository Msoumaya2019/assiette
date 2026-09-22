/// Ce que le trousseau range, et ce qu'il fait d'un contenu douteux.
///
/// Ce que ces tests mesurent
/// -------------------------
/// Le **vrai** `SecureStore`, sur un faux stockage injecte. Le trousseau du
/// systeme ne peut pas s'ouvrir dans un test ; la facade, elle, prend son
/// stockage en parametre, donc c'est bien le chemin de code reel qui s'execute —
/// la lecture, l'ecriture, l'effacement, et la relecture d'un contenu abime.
///
/// Pourquoi le contenu douteux est eprouve ici
/// -------------------------------------------
/// Un trousseau peut contenir ce qu'une version **precedente** y a laisse. Une
/// session qu'on ne sait pas relire doit se lire comme « pas de session » —
/// donc « se reconnecter » — et jamais faire tomber l'application au demarrage,
/// qui est le pire moment pour decouvrir une incompatibilite de format.
library;

import 'dart:convert';

import 'package:assiette/models/session.dart';
import 'package:assiette/services/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// --- fixtures ---------------------------------------------------------------

const int _expireLe = 1790000000000;

Session _session({String utilisateur = 'user-1', int expireLe = _expireLe}) =>
    Session(
      jetonAcces: 'jeton-acces',
      jetonRafraichissement: 'jeton-rafraichissement',
      expireLe: expireLe,
      utilisateur: utilisateur,
    );

/// Un stockage en memoire, a la place du trousseau du systeme.
///
/// Il herite de la facade au lieu de l'implementer : c'est la facade que
/// `SecureStore` appelle, et c'est donc ses signatures qu'il faut respecter.
class _FauxTrousseau extends FlutterSecureStorage {
  final Map<String, String> valeurs = {};

  /// Le nombre d'ecritures. Sert a verifier qu'une session part en **une** fois.
  int ecritures = 0;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    ecritures++;
    if (value == null) {
      valeurs.remove(key);
    } else {
      valeurs[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => valeurs[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    valeurs.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    valeurs.clear();
  }
}

void main() {
  late _FauxTrousseau trousseau;
  late SecureStore store;

  setUp(() {
    trousseau = _FauxTrousseau();
    store = SecureStore(storage: trousseau);
  });

  group('la session rangee', () {
    test('une session rangee se relit a l\'identique', () async {
      await store.ecrireSession(_session());

      final relue = await store.lireSession();

      expect(relue, isNotNull);
      expect(relue!.jetonAcces, 'jeton-acces');
      expect(relue.jetonRafraichissement, 'jeton-rafraichissement');
      expect(relue.expireLe, _expireLe);
      expect(relue.utilisateur, 'user-1');
    });

    test('sans session rangee, la lecture rend null', () async {
      expect(await store.lireSession(), isNull);
    });

    test('une session part en une seule ecriture', () async {
      await store.ecrireSession(_session());

      // Un enregistrement en plusieurs morceaux pourrait laisser une session a
      // moitie ecrite, et celle-ci ne se distinguerait pas d'une session valide
      // tant qu'on n'aurait pas essaye de s'en servir.
      expect(trousseau.ecritures, 1);
    });

    test('ecrire une session ecrase la precedente', () async {
      await store.ecrireSession(_session(utilisateur: 'user-1'));
      await store.ecrireSession(_session(utilisateur: 'user-2'));

      expect((await store.lireSession())!.utilisateur, 'user-2');
    });

    test('l\'effacement retire la session', () async {
      await store.ecrireSession(_session());

      await store.effacerSession();

      expect(await store.lireSession(), isNull);
    });

    test('la cle d\'analyse et la session ne se melangent pas', () async {
      await store.writeProviderKey('cle-du-fournisseur');
      await store.ecrireSession(_session());

      // Deux cles distinctes : sans ce temoin, une constante recopiee d'un
      // usage a l'autre ecraserait l'une par l'autre sans que rien ne tombe.
      expect(await store.readProviderKey(), 'cle-du-fournisseur');
      expect((await store.lireSession())!.utilisateur, 'user-1');
    });

    test('wipe efface aussi la session', () async {
      await store.ecrireSession(_session());

      await store.wipe();

      expect(await store.lireSession(), isNull);
    });
  });

  group('un contenu douteux', () {
    test(
      'un contenu qui n\'est pas du JSON se lit comme une absence',
      () async {
        trousseau.valeurs['session'] = 'pas du json du tout';

        expect(await store.lireSession(), isNull);
      },
    );

    test(
      'un contenu qui n\'est pas un objet se lit comme une absence',
      () async {
        trousseau.valeurs['session'] = jsonEncode([
          'acces',
          'rafraichissement',
        ]);

        expect(await store.lireSession(), isNull);
      },
    );

    test('une session sans jeton de rafraichissement est refusee', () async {
      // Le jeton de rafraichissement est la raison d'etre de ce stockage : sans
      // lui, la session ne sert a rien, et la garder ferait croire a une
      // connexion qui n'existe pas.
      trousseau.valeurs['session'] = jsonEncode({
        'acces': 'jeton-acces',
        'expire_le': _expireLe,
        'utilisateur': 'user-1',
      });

      expect(await store.lireSession(), isNull);
    });

    test('une echeance qui n\'est pas un entier est refusee', () async {
      trousseau.valeurs['session'] = jsonEncode({
        'acces': 'jeton-acces',
        'rafraichissement': 'jeton-rafraichissement',
        'expire_le': 'bientot',
        'utilisateur': 'user-1',
      });

      expect(await store.lireSession(), isNull);
    });

    test('une session dont le jeton d\'acces est vide est refusee', () async {
      // Un jeton present mais vide n'est pas un jeton : il ferait echouer
      // chaque requete de donnees, loin d'ici, avec un message qui ne dirait
      // rien de la cause.
      trousseau.valeurs['session'] = jsonEncode({
        'acces': '',
        'rafraichissement': 'jeton-rafraichissement',
        'expire_le': _expireLe,
        'utilisateur': 'user-1',
      });

      expect(await store.lireSession(), isNull);
    });

    test('une session sans compte est refusee', () async {
      trousseau.valeurs['session'] = jsonEncode({
        'acces': 'jeton-acces',
        'rafraichissement': 'jeton-rafraichissement',
        'expire_le': _expireLe,
      });

      expect(await store.lireSession(), isNull);
    });

    test('un contenu vide se lit comme une absence', () async {
      trousseau.valeurs['session'] = '   ';

      expect(await store.lireSession(), isNull);
    });
  });
}
