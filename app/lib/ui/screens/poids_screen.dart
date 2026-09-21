import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/suivi_poids.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// Suivi du poids et des mensurations.
///
/// ## Ce que cet ecran fait, et ce qu'il ne fait pas
///
/// Il **enregistre** ce que l'utilisateur saisit et le lui **montre** : une
/// courbe, un objectif qu'il a lui-meme fixe, et des mesures.
///
/// Il ne calcule aucun indice de masse corporelle, ne propose aucune cible, ne
/// qualifie aucun chiffre de bon ou de mauvais, et ne formule aucun conseil.
/// Ce n'est pas une precaution de redaction : suggerer un poids cible est un
/// acte de prescription, et une application qui compte des glucides n'a aucune
/// competence pour cela. Les valeurs affichees viennent de l'utilisateur, ou
/// d'un professionnel qui le suit.
///
/// ## Donnees personnelles
///
/// Poids et mensurations ne quittent pas l'appareil, sauf par la sauvegarde que
/// l'utilisateur declenche lui-meme depuis les reglages. Ils sont effaces par
/// la remise a zero, au meme titre que l'historique des repas.
class PoidsScreen extends ConsumerWidget {
  const PoidsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suivi = ref.watch(suiviProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Suivi du poids'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Poids'),
              Tab(text: 'Mensurations'),
            ],
          ),
        ),
        body: SafeArea(
          child: suivi.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Lecture impossible : $error',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (data) => TabBarView(
              children: [
                _OngletPoids(suivi: data),
                _OngletMensurations(suivi: data),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onglet du poids
// ---------------------------------------------------------------------------

class _OngletPoids extends ConsumerWidget {
  const _OngletPoids({required this.suivi});

  final SuiviPoids suivi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serie = suivi.serie();
    final objectif = suivi.objectif.cibleKg;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        _ResumeCard(serie: serie, objectifKg: objectif, pesees: suivi.pesees),

        const SizedBox(height: AppSpacing.lg),

        if (serie.estVide)
          SectionCard(
            title: 'Aucune pesee',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enregistrez une premiere pesee pour voir la courbe se '
                  'dessiner. Vous pouvez saisir une date passee si vous avez '
                  'deja des chiffres a reporter.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.palette.mutedText,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => _ajouterPesee(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Ajouter une pesee'),
                ),
              ],
            ),
          )
        else
          SectionCard(
            title: 'Courbe',
            subtitle: serie.longueur == 1
                ? 'Une seule pesee pour l\'instant'
                : '${serie.longueur} jours de suivi',
            trailing: FilledButton.tonalIcon(
              onPressed: () => _ajouterPesee(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Peser'),
            ),
            child: SizedBox(
              height: 240,
              child: _CourbePoids(serie: serie, objectifKg: objectif),
            ),
          ),

        const SizedBox(height: AppSpacing.lg),

        _CarteObjectif(objectif: suivi.objectif),

        if (suivi.pesees.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Historique',
            subtitle: suivi.pesees.length > 1
                ? '${suivi.pesees.length} pesees'
                : '1 pesee',
            child: Column(
              children: [
                for (final pesee in suivi.pesees)
                  _LignePesee(
                    pesee: pesee,
                    onSupprimer: () => _supprimerPesee(context, ref, pesee),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Resume du haut : dernier poids, variation, objectif.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.serie,
    required this.objectifKg,
    required this.pesees,
  });

  final SeriePoids serie;
  final double? objectifKg;
  final List<Pesee> pesees;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final derniere = serie.derniereKg;
    final variation = serie.variationKg;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.carb.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: palette.carb.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dernier poids',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.mutedText,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                derniere == null ? '—' : Format.number(derniere),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: palette.carb,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'kg',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.carb,
                ),
              ),
            ],
          ),
          if (serie.dernier != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'le ${Format.fullDate(serie.dernier!.le)}',
              style: TextStyle(fontSize: 12, color: palette.mutedText),
            ),
          ],

          if (variation != null || objectifKg != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (variation != null)
                  _Puce(
                    icone: variation <= 0
                        ? Icons.trending_down_rounded
                        : Icons.trending_up_rounded,
                    // Aucun jugement sur le signe : l'application affiche
                    // l'ecart, elle ne dit pas s'il est souhaitable.
                    texte:
                        '${variation > 0 ? '+' : ''}${Format.number(variation)} kg '
                        'depuis le debut',
                    couleur: palette.mutedText,
                  ),
                if (objectifKg != null)
                  _Puce(
                    icone: Icons.flag_outlined,
                    texte: 'objectif ${Format.number(objectifKg!)} kg',
                    couleur: context.colors.primary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({
    required this.icone,
    required this.texte,
    required this.couleur,
  });

  final IconData icone;
  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: couleur),
          const SizedBox(width: 6),
          // `Flexible` plutot qu'un `Text` nu : une puce posee dans un `Wrap`
          // ne recoit qu'une largeur bornee. Sans cela, un libelle long — ou
          // une taille de texte systeme augmentee — la fait deborder au lieu
          // de se raccourcir.
          Flexible(
            child: Text(
              texte,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La courbe, avec la ligne d'objectif quand elle est definie.
class _CourbePoids extends StatelessWidget {
  const _CourbePoids({required this.serie, this.objectifKg});

  final SeriePoids serie;
  final double? objectifKg;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final points = serie.points;
    if (points.isEmpty) return const SizedBox.shrink();

    // L'axe horizontal est en **jours depuis la premiere pesee** : une courbe
    // en dates serait illisible des que deux pesees sont eloignees, et les
    // trous se verraient a leur juste proportion.
    final origine = points.first.le;
    double abscisse(DateTime le) =>
        le.difference(origine).inMinutes / Duration.minutesPerDay;

    final dernierX = abscisse(points.last.le);
    final bornes = serie.bornes(objectifKg: objectifKg);
    final intervalleY = (bornes.max - bornes.min) / 4;
    final intervalleX = dernierX <= 0 ? 1.0 : dernierX / 4;

    return LineChart(
      LineChartData(
        minX: -0.3,
        maxX: dernierX + 0.3,
        minY: bornes.min,
        maxY: bornes.max,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => context.colors.inverseSurface,
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${Format.number(spot.y)} kg\n'
                    '${Format.dayMonthShort(origine.add(Duration(minutes: (spot.x * Duration.minutesPerDay).round())))}',
                    TextStyle(
                      color: context.colors.onInverseSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: intervalleY <= 0 ? 1 : intervalleY,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: palette.cardBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (objectifKg != null)
              HorizontalLine(
                y: objectifKg!,
                color: context.colors.primary.withValues(alpha: 0.7),
                strokeWidth: 1.5,
                dashArray: const [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                  labelResolver: (_) => 'objectif',
                ),
              ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: intervalleY <= 0 ? 1 : intervalleY,
              getTitlesWidget: (value, meta) => Text(
                Format.number(value),
                style: TextStyle(fontSize: 10, color: palette.mutedText),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: intervalleX,
              getTitlesWidget: (value, meta) {
                final date = origine.add(
                  Duration(minutes: (value * Duration.minutesPerDay).round()),
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    Format.dayMonthShort(date),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: palette.mutedText,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final point in points) FlSpot(abscisse(point.le), point.kg),
            ],
            isCurved: false,
            barWidth: 2.5,
            color: palette.carb,
            dotData: FlDotData(show: points.length <= 40),
            belowBarData: BarAreaData(
              show: true,
              color: palette.carb.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _LignePesee extends StatelessWidget {
  const _LignePesee({required this.pesee, required this.onSupprimer});

  final Pesee pesee;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${Format.number(pesee.poidsKg)} kg',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        pesee.note == null || pesee.note!.isEmpty
            ? Format.fullDate(pesee.le)
            : '${Format.fullDate(pesee.le)} · ${pesee.note}',
        style: TextStyle(fontSize: 12, color: palette.mutedText),
      ),
      trailing: IconButton(
        onPressed: onSupprimer,
        icon: const Icon(Icons.delete_outline_rounded, size: 20),
        tooltip: 'Supprimer cette pesee',
      ),
    );
  }
}

/// L'objectif de poids, defini par l'utilisateur.
class _CarteObjectif extends ConsumerWidget {
  const _CarteObjectif({required this.objectif});

  final ObjectifPoids objectif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return SectionCard(
      title: 'Objectif',
      subtitle: objectif.estDefini
          ? '${Format.number(objectif.cibleKg!)} kg'
          : 'Aucun objectif defini',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            objectif.estDefini
                ? 'Ce chiffre est le votre. L\'application l\'affiche sur la '
                      'courbe et ne le commente pas : elle ne juge aucun poids '
                      'et ne propose aucune cible.'
                : 'Fixez vous-meme un repere si vous le souhaitez. '
                      'L\'application ne propose aucune valeur : un objectif de '
                      'poids se decide avec un professionnel qui vous suit, pas '
                      'avec une application.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: palette.mutedText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: () =>
                    _definirObjectif(context, ref, actuel: objectif.cibleKg),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(
                  objectif.estDefini
                      ? 'Modifier l\'objectif'
                      : 'Definir un objectif',
                ),
              ),
              if (objectif.estDefini)
                TextButton(
                  onPressed: () =>
                      ref.read(suiviProvider.notifier).definirObjectif(null),
                  child: const Text('Retirer'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onglet des mensurations
// ---------------------------------------------------------------------------

class _OngletMensurations extends ConsumerWidget {
  const _OngletMensurations({required this.suivi});

  final SuiviPoids suivi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final dernieres = suivi.dernieresMesures();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        SectionCard(
          title: 'Mensurations',
          subtitle: 'En centimetres, quand vous le souhaitez',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _ajouterMesure(context, ref),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Mesurer'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ces mesures restent sur votre telephone. Elles servent a voir '
                'une evolution, pas a etre comparees a une norme : '
                'l\'application n\'en tire aucun commentaire.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: palette.mutedText,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (dernieres.isEmpty)
                Text(
                  'Aucune mesure enregistree.',
                  style: TextStyle(fontSize: 13, color: palette.mutedText),
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final type in TypeMesure.values)
                      if (dernieres[type] != null)
                        _TuileMesure(type: type, valeur: dernieres[type]!),
                  ],
                ),
            ],
          ),
        ),

        if (suivi.mesures.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Historique',
            subtitle: suivi.mesures.length > 1
                ? '${suivi.mesures.length} mesures'
                : '1 mesure',
            child: Column(
              children: [
                for (final mesure in suivi.mesures)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${mesure.type.displayLabel} · '
                      '${Format.number(mesure.valeurCm)} ${TypeMesure.unite}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      Format.fullDate(mesure.le),
                      style: TextStyle(fontSize: 12, color: palette.mutedText),
                    ),
                    trailing: IconButton(
                      onPressed: () => _supprimerMesure(context, ref, mesure),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      tooltip: 'Supprimer cette mesure',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TuileMesure extends StatelessWidget {
  const _TuileMesure({required this.type, required this.valeur});

  final TypeMesure type;
  final double valeur;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 104,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            type.displayLabel.replaceFirst('Tour de ', ''),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.mutedText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${Format.number(valeur)} ${TypeMesure.unite}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saisies
// ---------------------------------------------------------------------------

/// Demande une pesee : poids, date, remarque facultative.
Future<void> _ajouterPesee(BuildContext context, WidgetRef ref) async {
  final poids = TextEditingController();
  final note = TextEditingController();
  var quand = DateTime.now();
  String? erreur;

  final resultat = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return AlertDialog(
          title: const Text('Nouvelle pesee'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: poids,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Poids',
                  suffixText: 'kg',
                  hintText: '72,4',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Remarque (facultatif)',
                  hintText: 'a jeun, apres sport',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: () async {
                  final choix = await showDatePicker(
                    context: dialogContext,
                    initialDate: quand,
                    firstDate: DateTime(2000),
                    // Une pesee dans le futur n'a pas de sens : la borne est
                    // aujourd'hui.
                    lastDate: DateTime.now(),
                  );
                  if (choix != null) setState(() => quand = choix);
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(
                  quand.year == DateTime.now().year &&
                          quand.month == DateTime.now().month &&
                          quand.day == DateTime.now().day
                      ? 'Aujourd\'hui'
                      : Format.fullDate(quand),
                ),
              ),
              if (erreur != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  erreur!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final valeur = double.tryParse(poids.text.replaceAll(',', '.'));
                if (valeur == null || valeur <= 0) {
                  setState(() => erreur = 'Entrez un poids superieur a zero.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );

  if (resultat != true) return;

  final valeur = double.tryParse(poids.text.replaceAll(',', '.'));
  if (valeur == null) return;

  await ref
      .read(suiviProvider.notifier)
      .ajouterPesee(poidsKg: valeur, le: _instantDe(quand), note: note.text);
}

/// Demande une mesure : type, valeur, date.
Future<void> _ajouterMesure(BuildContext context, WidgetRef ref) async {
  final valeur = TextEditingController();
  var type = TypeMesure.taille;
  var quand = DateTime.now();
  String? erreur;

  final resultat = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return AlertDialog(
          title: const Text('Nouvelle mesure'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<TypeMesure>(
                initialValue: type,
                // Sans cela, la liste se dimensionne sur son libelle le plus
                // long — « Tour de poitrine » — et deborde de la largeur d'une
                // boite de dialogue sur un telephone de 360 points. Mesure :
                // 88 pixels de debordement.
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final valeur in TypeMesure.values)
                    DropdownMenuItem(
                      value: valeur,
                      child: Text(valeur.displayLabel),
                    ),
                ],
                onChanged: (choix) {
                  if (choix != null) setState(() => type = choix);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                type.precision,
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.mutedText,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: valeur,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Valeur',
                  suffixText: TypeMesure.unite,
                  hintText: '82',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: () async {
                  final choix = await showDatePicker(
                    context: dialogContext,
                    initialDate: quand,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (choix != null) setState(() => quand = choix);
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(Format.fullDate(quand)),
              ),
              if (erreur != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  erreur!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final lue = double.tryParse(valeur.text.replaceAll(',', '.'));
                if (lue == null || lue <= 0) {
                  setState(
                    () => erreur = 'Entrez une valeur superieure a zero.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );

  if (resultat != true) return;

  final lue = double.tryParse(valeur.text.replaceAll(',', '.'));
  if (lue == null) return;

  await ref
      .read(suiviProvider.notifier)
      .ajouterMesure(type: type, valeurCm: lue, le: _instantDe(quand));
}

/// Demande l'objectif de poids.
Future<void> _definirObjectif(
  BuildContext context,
  WidgetRef ref, {
  double? actuel,
}) async {
  final controller = TextEditingController(
    text: actuel == null ? '' : Format.number(actuel),
  );
  String? erreur;

  final resultat = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return AlertDialog(
          title: const Text('Objectif de poids'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Poids vise',
                  suffixText: 'kg',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                erreur ??
                    'L\'application n\'affiche que ce que vous saisissez. Elle '
                        'ne propose aucune cible et ne commente pas l\'ecart '
                        'avec votre poids actuel.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: erreur == null
                      ? context.palette.mutedText
                      : AppColors.danger,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final valeur = double.tryParse(
                  controller.text.replaceAll(',', '.'),
                );
                if (valeur == null || valeur <= 0) {
                  setState(() => erreur = 'Entrez un poids superieur a zero.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Valider'),
            ),
          ],
        );
      },
    ),
  );

  if (resultat != true) return;
  final valeur = double.tryParse(controller.text.replaceAll(',', '.'));
  if (valeur == null) return;
  await ref.read(suiviProvider.notifier).definirObjectif(valeur);
}

/// Instant a enregistrer pour une date choisie dans le calendrier.
///
/// Une date choisie est ramenee a **midi** : le calendrier ne rend qu'un jour,
/// et minuit ferait basculer la pesee sur la veille des qu'un fuseau ou un
/// arrondi s'en mele. Midi reste dans la journee voulue, dans tous les cas.
DateTime _instantDe(DateTime choisi) {
  final maintenant = DateTime.now();
  final memeJour =
      choisi.year == maintenant.year &&
      choisi.month == maintenant.month &&
      choisi.day == maintenant.day;
  if (memeJour) return maintenant;
  return DateTime(choisi.year, choisi.month, choisi.day, 12);
}

Future<void> _supprimerPesee(
  BuildContext context,
  WidgetRef ref,
  Pesee pesee,
) async {
  final confirme = await _confirmer(
    context,
    titre: 'Supprimer cette pesee ?',
    message:
        '${Format.number(pesee.poidsKg)} kg du ${Format.fullDate(pesee.le)} '
        'seront retires de la courbe.',
  );
  if (confirme != true) return;
  await ref.read(suiviProvider.notifier).supprimerPesee(pesee.id);
}

Future<void> _supprimerMesure(
  BuildContext context,
  WidgetRef ref,
  Mesure mesure,
) async {
  final confirme = await _confirmer(
    context,
    titre: 'Supprimer cette mesure ?',
    message:
        '${mesure.type.displayLabel} du ${Format.fullDate(mesure.le)} sera '
        'retiree de l\'historique.',
  );
  if (confirme != true) return;
  await ref.read(suiviProvider.notifier).supprimerMesure(mesure.id);
}

Future<bool?> _confirmer(
  BuildContext context, {
  required String titre,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(titre),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
}
