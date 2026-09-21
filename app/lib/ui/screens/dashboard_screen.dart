import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/goals.dart';
import '../../models/meal.dart';
import '../../models/nutrition_values.dart';
import '../../services/nutrition_calculator.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';

/// Tableau de bord : repartition des glucides dans le temps et progression
/// vers les objectifs.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// 0 = semaine, 1 = mois.
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    final series = _range == 0
        ? ref.watch(weeklySeriesProvider)
        : ref.watch(monthlySeriesProvider);
    final summary = ref.watch(todaySummaryProvider);
    final progress = ref.watch(goalProgressProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques'),
        actions: [
          IconButton(
            onPressed: () => ref.read(mealsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            summary.when(
              loading: () => const SizedBox(height: 120),
              error: (error, _) => EstimateBanner(
                message: 'Lecture impossible : $error',
                severity: EstimateSeverity.danger,
              ),
              data: (data) => _TodayCard(summary: data),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Glucides dans le temps',
              subtitle: _range == 0
                  ? '7 derniers jours'
                  : '6 dernieres semaines',
              trailing: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('7 j')),
                  ButtonSegment(value: 1, label: Text('6 sem.')),
                ],
                selected: {_range},
                onSelectionChanged: (selection) =>
                    setState(() => _range = selection.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              child: series.when(
                loading: () => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Text('Lecture impossible : $error'),
                data: (buckets) => Column(
                  children: [
                    SizedBox(
                      height: 210,
                      child: _CarbsBarChart(
                        buckets: buckets,
                        weekly: _range == 1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SeriesStats(buckets: buckets, weekly: _range == 1),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            if (settings.goals.isNotEmpty)
              SectionCard(
                title: 'Objectifs du jour',
                subtitle: 'Progression vers vos objectifs personnels',
                child: progress.when(
                  loading: () => const SizedBox(height: 80),
                  error: (error, _) => Text('Lecture impossible : $error'),
                  data: (list) => list.isEmpty
                      ? Text(
                          'Aucun objectif defini.',
                          style: TextStyle(color: context.palette.mutedText),
                        )
                      : Column(
                          children: [
                            for (final item in list) ...[
                              _GoalBar(progress: item),
                              const SizedBox(height: AppSpacing.md),
                            ],
                          ],
                        ),
                ),
              )
            else
              SectionCard(
                title: 'Objectifs',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Definissez un objectif de glucides par jour pour suivre votre '
                      'progression. L\'application n\'en propose aucun par defaut : '
                      'ces valeurs vous appartiennent.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: context.palette.mutedText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => context.push(Routes.goals),
                      icon: const Icon(Icons.flag_rounded, size: 18),
                      label: const Text('Definir mes objectifs'),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: AppSpacing.lg),

            _MacroBreakdown(series: series),

            const SizedBox(height: AppSpacing.lg),

            const _PoidsCard(),

            const SizedBox(height: AppSpacing.lg),

            const EstimateBanner(
              message:
                  'Ces chiffres reposent sur les quantites que vous avez validees. '
                  'Ils ne constituent pas un avis medical.',
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.summary});

  final NutritionSummary summary;

  @override
  Widget build(BuildContext context) {
    final totals = summary.totals;
    final palette = context.palette;

    return SectionCard(
      title: 'Aujourd\'hui',
      subtitle:
          '${summary.mealCount} repas enregistre${summary.mealCount > 1 ? 's' : ''}',
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.grain_rounded, size: 18, color: palette.carb),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Glucides',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.carb,
                ),
              ),
              const Spacer(),
              Text(
                '${Format.carbs(totals.carbs)} g',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: palette.carb,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MacroGrid(totals: totals),
        ],
      ),
    );
  }
}

/// Acces au suivi du poids depuis le tableau de bord.
///
/// Une seule ligne, sans courbe : le tableau de bord parle de glucides, et la
/// courbe de poids a son propre ecran. Melanger les deux ici donnerait a croire
/// qu'ils sont lies, ce qui n'est pas le propos de l'application.
class _PoidsCard extends ConsumerWidget {
  const _PoidsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suivi = ref.watch(suiviProvider);
    final palette = context.palette;

    final derniere = suivi.valueOrNull?.serie().derniereKg;
    final objectif = suivi.valueOrNull?.objectif.cibleKg;

    return SectionCard(
      title: 'Poids',
      subtitle: derniere == null
          ? 'Aucune pesee enregistree'
          : 'Derniere pesee : ${Format.number(derniere)} kg'
                '${objectif == null ? '' : ' · objectif ${Format.number(objectif)} kg'}',
      trailing: Icon(Icons.chevron_right_rounded, color: palette.mutedText),
      onTap: () => context.push(Routes.poids),
      child: Text(
        'Suivez votre poids, fixez vous-meme un repere et notez vos '
        'mensurations. Ces donnees restent sur votre telephone.',
        style: TextStyle(fontSize: 13, height: 1.45, color: palette.mutedText),
      ),
    );
  }
}

/// Histogramme des glucides par jour ou par semaine.
class _CarbsBarChart extends StatelessWidget {
  const _CarbsBarChart({required this.buckets, required this.weekly});

  final List<DailyBucket> buckets;
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final maxValue = buckets
        .map((bucket) => bucket.totals.carbs)
        .fold<double>(
          0,
          (previous, value) => value > previous ? value : previous,
        );

    // Une echelle minimale evite un graphique ecrase lorsque les valeurs sont
    // faibles, tout en restant proportionnelle des que les glucides montent.
    final maxY = maxValue <= 0 ? 100.0 : (maxValue * 1.25).ceilToDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => context.colors.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final bucket = buckets[group.x];
              return BarTooltipItem(
                '${Format.carbs(bucket.totals.carbs)} g\n${Format.kcal(bucket.totals.kcal)}',
                TextStyle(
                  color: context.colors.onInverseSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: palette.cardBorder, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
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
              reservedSize: 34,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                value.round().toString(),
                style: TextStyle(fontSize: 10, color: palette.mutedText),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= buckets.length) {
                  return const SizedBox.shrink();
                }
                final date = buckets[index].date;
                final label = weekly
                    ? Format.dayMonth(date).split(' ').first
                    : frenchWeekdayInitials[date.weekday - 1];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.mutedText,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var index = 0; index < buckets.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: buckets[index].totals.carbs,
                  width: weekly ? 22 : 18,
                  borderRadius: BorderRadius.circular(6),
                  color: buckets[index].mealCount == 0
                      ? palette.cardBorder
                      : palette.carb,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Statistiques textuelles sous le graphique.
class _SeriesStats extends StatelessWidget {
  const _SeriesStats({required this.buckets, required this.weekly});

  final List<DailyBucket> buckets;
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    final average = NutritionCalculator.averagePerActiveDay(buckets);
    final activeDays = buckets.where((bucket) => bucket.mealCount > 0).length;
    final total = NutritionValues.sum(buckets.map((bucket) => bucket.totals));

    final unit = weekly ? 'semaine' : 'jour';

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        _Stat(
          label: 'Moyenne par $unit actif',
          value: '${Format.carbs(average.carbs)} g',
        ),
        _Stat(label: 'Total', value: '${Format.carbs(total.carbs)} g'),
        _Stat(
          label: weekly ? 'Periodes actives' : 'Jours actifs',
          value: '$activeDays / ${buckets.length}',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.palette.mutedText),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = progress.isExceeded
        ? AppColors.warning
        : context.colors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                progress.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${Format.number(progress.consumed)} / ${Format.number(progress.target)} ${progress.unit}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.mutedText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.clampedRatio,
            minHeight: 8,
            backgroundColor: palette.cardBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          progress.isExceeded
              ? 'Depasse de ${Format.number(-progress.remaining)} ${progress.unit}'
              : 'Reste ${Format.number(progress.remaining)} ${progress.unit}',
          style: TextStyle(fontSize: 11, color: palette.mutedText),
        ),
      ],
    );
  }
}

/// Repartition moyenne des macronutriments.
class _MacroBreakdown extends StatelessWidget {
  const _MacroBreakdown({required this.series});

  final AsyncValue<List<DailyBucket>> series;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Repartition moyenne',
      subtitle: 'Sur les periodes ou des repas sont enregistres',
      child: series.when(
        loading: () => const SizedBox(height: 80),
        error: (error, _) => Text('Lecture impossible : $error'),
        data: (buckets) {
          final average = NutritionCalculator.averagePerActiveDay(buckets);
          if (!average.isNotEmpty) {
            return Text(
              'Pas encore assez de donnees.',
              style: TextStyle(color: context.palette.mutedText),
            );
          }
          return MacroGrid(totals: average);
        },
      ),
    );
  }
}
