import 'package:assiette/models/arbitrage.dart';
import 'package:assiette/models/synchronisation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une ligne de contenu simple, pour ne pas meler deux questions.
LigneSynchronisable ligne(
  String cle, {
  required int updatedAt,
  int? deletedAt,
  String nom = 'Repas',
}) => LigneSynchronisable(
  cle: cle,
  updatedAt: updatedAt,
  deletedAt: deletedAt,
  contenu: {'nom': nom},
);

List<String> cles(List<LigneSynchronisable> lignes) =>
    lignes.map((ligne) => ligne.cle).toList();

/// Les trois nombres qui decrivent une version, pour comparer sans `==`.
List<Object?> identite(VersionArbitrable version) => [
  version.updatedAt,
  version.deletedAt,
  version.empreinte,
];

/// Ce que ce cote detient une fois son plan applique.
///
/// Un plan dit soit « ecris cette distante », soit « garde ta locale ». C'est
/// exactement ce que fait le moteur de synchronisation.
LigneSynchronisable apresPlan(
  LigneSynchronisable locale,
  PlanDeSynchronisation plan,
) {
  for (final aEcrire in plan.aAppliquer) {
    if (aEcrire.cle == locale.cle) return aEcrire;
  }
  return locale;
}

/// La version que ce cote detiendra une fois le plan applique.
VersionArbitrable versionFinale(
  LigneSynchronisable locale,
  PlanDeSynchronisation plan,
) => apresPlan(locale, plan).version;

void main() {
  group('Une ligne presente d\'un seul cote', () {
    test('une ligne locale que la distante ignore est a pousser', () {
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 100)],
        distantes: const [],
      );
      expect(cles(plan.aPousser), ['m1']);
      expect(plan.aAppliquer, isEmpty);
      expect(plan.identiques, isEmpty);
    });

    test('une ligne distante inconnue localement est a appliquer', () {
      final plan = planifierSynchronisation(
        locales: const [],
        distantes: [ligne('m1', updatedAt: 100)],
      );
      expect(plan.aPousser, isEmpty);
      expect(cles(plan.aAppliquer), ['m1']);
    });

    test('une pierre tombale locale inconnue en face est poussee aussi', () {
      // Le but est que les deux cotes finissent avec le meme etat, y compris
      // une suppression. Ne pas pousser laisserait une difference invisible —
      // et une difference invisible est une difference qu'aucun test ne
      // rattrape.
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 100, deletedAt: 100)],
        distantes: const [],
      );
      expect(cles(plan.aPousser), ['m1']);
      expect(plan.aPousser.single.estSupprimee, isTrue);
    });

    test('deux etats vides donnent un plan vide', () {
      final plan = planifierSynchronisation(
        locales: const [],
        distantes: const [],
      );
      expect(plan.estVide, isTrue);
      expect(plan.vuesDesDeuxCotes, 0);
    });
  });

  group('Une ligne presente des deux cotes est arbitree', () {
    test('la version distante plus recente est appliquee', () {
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 100, nom: 'ancien')],
        distantes: [ligne('m1', updatedAt: 200, nom: 'recent')],
      );
      expect(cles(plan.aAppliquer), ['m1']);
      expect(plan.aPousser, isEmpty);
    });

    test('la version locale plus recente est poussee', () {
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 300, nom: 'recent')],
        distantes: [ligne('m1', updatedAt: 200, nom: 'ancien')],
      );
      expect(cles(plan.aPousser), ['m1']);
      expect(plan.aAppliquer, isEmpty);
    });

    test('deux versions identiques ne produisent aucun travail', () {
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 100, nom: 'identique')],
        distantes: [ligne('m1', updatedAt: 100, nom: 'identique')],
      );
      expect(plan.estVide, isTrue);
      expect(plan.identiques, ['m1']);
    });

    test('a date egale, la suppression distante l\'emporte', () {
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 100, nom: 'vivante')],
        distantes: [
          ligne('m1', updatedAt: 100, deletedAt: 100, nom: 'vivante'),
        ],
      );
      expect(cles(plan.aAppliquer), ['m1']);
      expect(plan.aAppliquer.single.estSupprimee, isTrue);
    });

    test('a date egale, une locale supprimee ne se fait pas ressusciter', () {
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 100, deletedAt: 100, nom: 'vivante')],
        distantes: [ligne('m1', updatedAt: 100, nom: 'vivante')],
      );
      expect(cles(plan.aPousser), ['m1']);
      expect(plan.aPousser.single.estSupprimee, isTrue);
    });

    test('une date inconnue perd contre une date connue', () {
      final plan = planifierSynchronisation(
        locales: [ligne('m1', updatedAt: 0, nom: 'sans date')],
        distantes: [ligne('m1', updatedAt: 50, nom: 'datee')],
      );
      expect(cles(plan.aAppliquer), ['m1']);
    });

    test(
      'a date egale, l\'empreinte tranche au lieu de declarer identique',
      () {
        final plan = planifierSynchronisation(
          locales: [ligne('m1', updatedAt: 100, nom: 'un')],
          distantes: [ligne('m1', updatedAt: 100, nom: 'deux')],
        );
        expect(plan.identiques, isEmpty);
        expect(plan.vuesDesDeuxCotes, 1);
      },
    );
  });

  group('Plusieurs lignes a la fois', () {
    test('chaque ligne est traitee pour elle-meme', () {
      final plan = planifierSynchronisation(
        locales: [
          ligne('a', updatedAt: 300, nom: 'recente'),
          ligne('b', updatedAt: 100, nom: 'ancienne'),
          ligne('c', updatedAt: 100, nom: 'seule ici'),
        ],
        distantes: [
          ligne('a', updatedAt: 100, nom: 'ancienne'),
          ligne('b', updatedAt: 200, nom: 'recente'),
          ligne('d', updatedAt: 100, nom: 'seule en face'),
        ],
      );
      expect(cles(plan.aPousser), ['a', 'c']);
      expect(cles(plan.aAppliquer), ['b', 'd']);
      expect(plan.identiques, isEmpty);
    });

    test('les listes du plan sont triees par cle', () {
      final plan = planifierSynchronisation(
        locales: [
          ligne('z', updatedAt: 100),
          ligne('a', updatedAt: 100),
          ligne('m', updatedAt: 100),
        ],
        distantes: const [],
      );
      expect(cles(plan.aPousser), ['a', 'm', 'z']);
    });

    test('l\'ordre des listes fournies ne change pas le plan', () {
      final locales = [ligne('z', updatedAt: 100), ligne('a', updatedAt: 100)];
      final distantes = [
        ligne('m', updatedAt: 100),
        ligne('b', updatedAt: 100),
      ];
      final plan = planifierSynchronisation(
        locales: locales,
        distantes: distantes,
      );
      final inverse = planifierSynchronisation(
        locales: locales.reversed.toList(),
        distantes: distantes.reversed.toList(),
      );
      expect(cles(plan.aPousser), cles(inverse.aPousser));
      expect(cles(plan.aAppliquer), cles(inverse.aAppliquer));
      expect(plan.identiques, inverse.identiques);
    });
  });

  group('Ce qui fait converger : la symetrie du plan', () {
    // Le jeu d'etats couvre les cas qui se contredisent : date inconnue, date
    // egale, suppression, contenus differents a date egale.
    final etats = <LigneSynchronisable>[
      ligne('m1', updatedAt: 100, nom: 'ancienne'),
      ligne('m1', updatedAt: 200, nom: 'recente'),
      ligne('m1', updatedAt: 200, nom: 'autre recente'),
      ligne('m1', updatedAt: 200, deletedAt: 200, nom: 'recente'),
      ligne('m1', updatedAt: 0, nom: 'sans date'),
      ligne('m1', updatedAt: 300, deletedAt: 300, nom: 'supprimee'),
    ];

    test('le plan est le meme, en miroir, pour chaque paire', () {
      for (final gauche in etats) {
        for (final droite in etats) {
          final aller = planifierSynchronisation(
            locales: [gauche],
            distantes: [droite],
          );
          final retour = planifierSynchronisation(
            locales: [droite],
            distantes: [gauche],
          );
          final description = '$gauche / $droite';
          expect(
            cles(aller.aPousser),
            cles(retour.aAppliquer),
            reason: description,
          );
          expect(
            cles(aller.aAppliquer),
            cles(retour.aPousser),
            reason: description,
          );
          expect(aller.identiques, retour.identiques, reason: description);
        }
      }
    });

    test('aucune cle n\'est a la fois poussee et appliquee', () {
      for (final gauche in etats) {
        for (final droite in etats) {
          final plan = planifierSynchronisation(
            locales: [gauche],
            distantes: [droite],
          );
          expect(
            cles(
              plan.aPousser,
            ).toSet().intersection(cles(plan.aAppliquer).toSet()),
            isEmpty,
            reason: '$gauche / $droite',
          );
        }
      }
    });

    test('les deux cotes finissent avec la meme version', () {
      for (final gauche in etats) {
        for (final droite in etats) {
          final aller = planifierSynchronisation(
            locales: [gauche],
            distantes: [droite],
          );
          final retour = planifierSynchronisation(
            locales: [droite],
            distantes: [gauche],
          );
          expect(
            identite(versionFinale(gauche, aller)),
            identite(versionFinale(droite, retour)),
            reason: '$gauche / $droite',
          );
        }
      }
    });

    test(
      'une fois le plan applique des deux cotes, il n\'y a plus rien a faire',
      () {
        // L'idempotence : une synchronisation qui se termine ne doit pas laisser
        // de travail pour la suivante, sinon les deux appareils s'echangent la
        // meme ligne sans fin.
        for (final gauche in etats) {
          for (final droite in etats) {
            final aller = planifierSynchronisation(
              locales: [gauche],
              distantes: [droite],
            );
            final retour = planifierSynchronisation(
              locales: [droite],
              distantes: [gauche],
            );
            final suivant = planifierSynchronisation(
              locales: [apresPlan(gauche, aller)],
              distantes: [apresPlan(droite, retour)],
            );
            expect(suivant.estVide, isTrue, reason: '$gauche / $droite');
          }
        }
      },
    );
  });

  group('Un agregat est une seule ligne', () {
    // Un repas et ses aliments sont une ligne du point de vue de la
    // synchronisation : `saveMeal` reecrit les aliments en bloc et horodate le
    // repas dans le meme geste.
    Map<String, Object?> repas(double quantite) => {
      'nom': 'Petit-dejeuner',
      'items': [
        {'nom': 'Riz', 'quantity_g': quantite},
      ],
    };

    test('changer un aliment change l\'empreinte du repas', () {
      final avant = LigneSynchronisable(
        cle: 'm1',
        updatedAt: 100,
        contenu: repas(100),
      );
      final apres = LigneSynchronisable(
        cle: 'm1',
        updatedAt: 100,
        contenu: repas(150),
      );
      expect(avant.version.empreinte, isNot(apres.version.empreinte));
    });

    test('un repas modifie n\'est pas declare identique a l\'ancien', () {
      final plan = planifierSynchronisation(
        locales: [
          LigneSynchronisable(cle: 'm1', updatedAt: 100, contenu: repas(100)),
        ],
        distantes: [
          LigneSynchronisable(cle: 'm1', updatedAt: 100, contenu: repas(150)),
        ],
      );
      expect(plan.identiques, isEmpty);
      expect(plan.vuesDesDeuxCotes, 1);
    });

    test('le meme repas des deux cotes ne se pousse rien', () {
      final plan = planifierSynchronisation(
        locales: [
          LigneSynchronisable(cle: 'm1', updatedAt: 100, contenu: repas(150)),
        ],
        distantes: [
          LigneSynchronisable(cle: 'm1', updatedAt: 100, contenu: repas(150)),
        ],
      );
      expect(plan.estVide, isTrue);
      expect(plan.identiques, ['m1']);
    });
  });

  group('Une cle en double est refusee', () {
    // Deux lignes de meme cle rendraient le plan dependant de l'ordre des
    // listes : la ligne gagnante dependrait de celle qui a ete lue en dernier.
    test('deux lignes locales de meme cle font lever', () {
      expect(
        () => planifierSynchronisation(
          locales: [ligne('m1', updatedAt: 100), ligne('m1', updatedAt: 200)],
          distantes: const [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deux lignes distantes de meme cle font lever', () {
      expect(
        () => planifierSynchronisation(
          locales: const [],
          distantes: [ligne('m1', updatedAt: 100), ligne('m1', updatedAt: 200)],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('le refus nomme la cle et le cote fautif', () {
      try {
        planifierSynchronisation(
          locales: [ligne('m1', updatedAt: 100), ligne('m1', updatedAt: 200)],
          distantes: const [],
        );
        fail('le plan aurait du refuser deux lignes locales de meme cle');
      } on ArgumentError catch (erreur) {
        expect(erreur.message, contains('m1'));
        expect(erreur.message, contains('locale'));
      }
    });
  });
}
