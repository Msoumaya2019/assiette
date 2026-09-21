import 'package:assiette/models/arbitrage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le verdict oppose, tel qu'on l'attend de l'autre cote.
///
/// `garderLocale` et `prendreDistante` decrivent le **meme** gagnant vu de deux
/// places : si A garde A, alors B doit prendre A. `identiques` est son propre
/// oppose — il n'y a pas de gagnant du tout.
VerdictArbitrage oppose(VerdictArbitrage verdict) => switch (verdict) {
  VerdictArbitrage.garderLocale => VerdictArbitrage.prendreDistante,
  VerdictArbitrage.prendreDistante => VerdictArbitrage.garderLocale,
  VerdictArbitrage.identiques => VerdictArbitrage.identiques,
};

void main() {
  // Dates en millisecondes. `updatedAt: 0` signifie « inconnue ».
  const ancienne = VersionArbitrable(
    updatedAt: 100,
    deletedAt: null,
    empreinte: 'a',
  );
  const recente = VersionArbitrable(
    updatedAt: 200,
    deletedAt: null,
    empreinte: 'a',
  );
  const recenteAutre = VersionArbitrable(
    updatedAt: 200,
    deletedAt: null,
    empreinte: 'b',
  );
  const supprimeeAncienne = VersionArbitrable(
    updatedAt: 100,
    deletedAt: 150,
    empreinte: 'a',
  );
  const supprimeeRecente = VersionArbitrable(
    updatedAt: 300,
    deletedAt: 300,
    empreinte: 'a',
  );
  const dateInconnue = VersionArbitrable(
    updatedAt: 0,
    deletedAt: null,
    empreinte: 'a',
  );
  const dateInconnueSupprimee = VersionArbitrable(
    updatedAt: 0,
    deletedAt: 0,
    empreinte: 'a',
  );

  group('La modification la plus recente gagne', () {
    test('la distante plus recente l\'emporte', () {
      expect(
        arbitrer(locale: ancienne, distante: recente),
        VerdictArbitrage.prendreDistante,
      );
    });

    test('la locale plus recente se garde', () {
      expect(
        arbitrer(locale: recente, distante: ancienne),
        VerdictArbitrage.garderLocale,
      );
    });
  });

  group('A date egale, la suppression gagne', () {
    test('la suppression distante l\'emporte sur une vivante', () {
      final vivante = VersionArbitrable(
        updatedAt: 200,
        deletedAt: null,
        empreinte: 'a',
      );
      final supprimee = VersionArbitrable(
        updatedAt: 200,
        deletedAt: 200,
        empreinte: 'a',
      );
      expect(
        arbitrer(locale: vivante, distante: supprimee),
        VerdictArbitrage.prendreDistante,
      );
      expect(
        arbitrer(locale: supprimee, distante: vivante),
        VerdictArbitrage.garderLocale,
      );
    });

    test('deux suppressions a la meme date ne s\'annulent pas', () {
      // Sans la regle 3, deux pierres tombales de contenus differents se
      // departageraient au hasard — et les deux appareils differemment.
      final gauche = VersionArbitrable(
        updatedAt: 200,
        deletedAt: 200,
        empreinte: 'a',
      );
      final droite = VersionArbitrable(
        updatedAt: 200,
        deletedAt: 200,
        empreinte: 'b',
      );
      expect(
        arbitrer(locale: gauche, distante: droite),
        VerdictArbitrage.prendreDistante,
      );
      expect(
        arbitrer(locale: droite, distante: gauche),
        VerdictArbitrage.garderLocale,
      );
    });

    test('une suppression ANCIENNE ne bat pas une vivante plus recente', () {
      // Le cas qui distingue « la suppression gagne » de « la suppression gagne
      // toujours » : la regle ne s'applique qu'a date egale.
      expect(
        arbitrer(locale: supprimeeAncienne, distante: recente),
        VerdictArbitrage.prendreDistante,
      );
    });

    test('une suppression recente bat une vivante ancienne', () {
      expect(
        arbitrer(locale: ancienne, distante: supprimeeRecente),
        VerdictArbitrage.prendreDistante,
      );
      expect(
        arbitrer(locale: supprimeeRecente, distante: ancienne),
        VerdictArbitrage.garderLocale,
      );
    });
  });

  group('A date egale, l\'empreinte departage', () {
    test('la plus grande empreinte gagne, des deux cotes', () {
      expect(
        arbitrer(locale: recente, distante: recenteAutre),
        VerdictArbitrage.prendreDistante,
      );
      expect(
        arbitrer(locale: recenteAutre, distante: recente),
        VerdictArbitrage.garderLocale,
      );
    });

    test('meme date, meme etat, meme empreinte : rien a faire', () {
      expect(
        arbitrer(locale: recente, distante: recente),
        VerdictArbitrage.identiques,
      );
    });
  });

  group('Une date inconnue', () {
    test('perd contre une date connue', () {
      expect(
        arbitrer(locale: ancienne, distante: dateInconnue),
        VerdictArbitrage.garderLocale,
      );
      expect(
        arbitrer(locale: dateInconnue, distante: ancienne),
        VerdictArbitrage.prendreDistante,
      );
    });

    test(
      'ne perd pas contre une autre date inconnue : l\'empreinte decide',
      () {
        final autre = VersionArbitrable(
          updatedAt: 0,
          deletedAt: null,
          empreinte: 'b',
        );
        expect(
          arbitrer(locale: dateInconnue, distante: autre),
          VerdictArbitrage.prendreDistante,
        );
        expect(
          arbitrer(locale: autre, distante: dateInconnue),
          VerdictArbitrage.garderLocale,
        );
      },
    );

    test('une suppression sans date bat une vivante sans date', () {
      expect(
        arbitrer(locale: dateInconnue, distante: dateInconnueSupprimee),
        VerdictArbitrage.prendreDistante,
      );
      expect(
        arbitrer(locale: dateInconnueSupprimee, distante: dateInconnue),
        VerdictArbitrage.garderLocale,
      );
    });
  });

  group('Ce qui fait converger : la symetrie', () {
    // Le jeu couvre les trois regles, leurs combinaisons, et les dates
    // inconnues. Chaque paire est eprouvee dans les deux sens.
    const cas = <String, VersionArbitrable>{
      'vivante ancienne': ancienne,
      'vivante recente': recente,
      'vivante recente, autre contenu': recenteAutre,
      'supprimee ancienne': supprimeeAncienne,
      'supprimee recente': supprimeeRecente,
      'date inconnue': dateInconnue,
      'date inconnue supprimee': dateInconnueSupprimee,
    };

    test('le verdict est le meme des deux cotes, pour chaque paire', () {
      // C'est le controle central. Deux appareils qui se croient chacun
      // vainqueur ne convergent jamais : ils s'echangent leurs versions
      // indefiniment. Une regle qui dit « en cas d'egalite je garde la mienne »
      // passerait tous les autres tests et tomberait ici.
      var paires = 0;
      for (final entree in cas.entries) {
        for (final autre in cas.entries) {
          final direct = arbitrer(locale: entree.value, distante: autre.value);
          final inverse = arbitrer(locale: autre.value, distante: entree.value);
          expect(
            inverse,
            oppose(direct),
            reason:
                '${entree.key} contre ${autre.key} : '
                'le verdict change selon le cote qui regarde',
          );
          paires++;
        }
      }
      expect(paires, cas.length * cas.length);
    });

    test('aucune paire ne renvoie les deux cotes gagnants', () {
      // La meme propriete, enoncee comme le defaut qu'elle evite : deux
      // verdicts `garderLocale` face a face signifieraient que chacun garde sa
      // version et que rien ne converge.
      for (final entree in cas.entries) {
        for (final autre in cas.entries) {
          final direct = arbitrer(locale: entree.value, distante: autre.value);
          final inverse = arbitrer(locale: autre.value, distante: entree.value);
          expect(
            direct == VerdictArbitrage.garderLocale &&
                inverse == VerdictArbitrage.garderLocale,
            isFalse,
            reason: '${entree.key} et ${autre.key} se gardent tous les deux',
          );
        }
      }
    });

    test('les deux appareils finissent avec la meme version', () {
      // La propriete, enoncee sur les donnees et non sur le verdict : apres
      // l'echange, les deux appareils doivent tenir le meme contenu. C'est cela
      // qui fait qu'une divergence s'arrete, au lieu de se repeter a chaque
      // synchronisation.
      for (final entree in cas.entries) {
        for (final autre in cas.entries) {
          final vuDA = arbitrer(locale: entree.value, distante: autre.value);
          final vuDeB = arbitrer(locale: autre.value, distante: entree.value);

          final chezA = switch (vuDA) {
            VerdictArbitrage.prendreDistante => autre.value,
            _ => entree.value,
          };
          final chezB = switch (vuDeB) {
            VerdictArbitrage.prendreDistante => entree.value,
            _ => autre.value,
          };

          expect(
            (chezA.updatedAt, chezA.deletedAt, chezA.empreinte),
            (chezB.updatedAt, chezB.deletedAt, chezB.empreinte),
            reason:
                '${entree.key} contre ${autre.key} : '
                'les deux appareils ne gardent pas la meme version',
          );
        }
      }
    });
  });
}
