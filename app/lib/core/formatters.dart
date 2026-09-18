import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Formatage des nombres, dates et quantites, en francais.
///
/// Les nombres sont arrondis avec une regle unique : jamais plus d'une decimale
/// pour les grammes, et un entier pour les calories. Afficher « 74,3 g » a cote
/// de « 74 g » selon l'ecran donne une impression d'imprecision.
class Format {
  const Format._();

  static final DateFormat _dayMonth = DateFormat('d MMMM', 'fr_FR');
  static final DateFormat _dayMonthYear = DateFormat('d MMMM y', 'fr_FR');
  static final DateFormat _time = DateFormat('HH:mm', 'fr_FR');
  static final DateFormat _weekday = DateFormat('EEEE d MMMM', 'fr_FR');
  static final DateFormat _month = DateFormat('MMMM y', 'fr_FR');

  /// Grammes, avec une decimale seulement si necessaire.
  static String grams(double value) {
    if (value.isNaN || value.isInfinite) return '0 g';
    if (value >= 100) return '${value.round()} g';
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.round()} g'
        : '${rounded.toStringAsFixed(1).replaceAll('.', ',')} g';
  }

  /// Nombre sans unite, arrondi.
  static String number(double value) {
    if (value.isNaN || value.isInfinite) return '0';
    if (value >= 100) return value.round().toString();
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Kilocalories, toujours entieres.
  static String kcal(double value) {
    if (value.isNaN || value.isInfinite) return '0 kcal';
    return '${value.round()} kcal';
  }

  /// Nombre de glucides mis en avant, sans decimales inutiles.
  static String carbs(double value) => number(value);

  /// Pourcentage, entier.
  static String percent(double ratio) => '${(ratio * 100).round()} %';

  /// Confiance, sous forme de pourcentage lisible.
  static String confidence(double value) {
    final percent = (value * 100).round();
    return '$percent %';
  }

  static String time(DateTime date) => _time.format(date);

  static String dayMonth(DateTime date) => _dayMonth.format(date);

  static String weekdayDayMonth(DateTime date) {
    final formatted = _weekday.format(date);
    return formatted.isEmpty
        ? formatted
        : formatted[0].toUpperCase() + formatted.substring(1);
  }

  static String monthYear(DateTime date) {
    final formatted = _month.format(date);
    return formatted.isEmpty
        ? formatted
        : formatted[0].toUpperCase() + formatted.substring(1);
  }

  static String fullDate(DateTime date) {
    final formatted = _dayMonthYear.format(date);
    return formatted.isEmpty
        ? formatted
        : formatted[0].toUpperCase() + formatted.substring(1);
  }

  /// Libelle relatif : « Aujourd'hui », « Hier », puis la date.
  static String relativeDay(DateTime date, {DateTime? reference}) {
    final today = _dayOnly(reference ?? DateTime.now());
    final target = _dayOnly(date);
    final difference = today.difference(target).inDays;

    if (difference == 0) return 'Aujourd\'hui';
    if (difference == 1) return 'Hier';
    if (difference == 2) return 'Avant-hier';
    if (difference < 7) return weekdayDayMonth(date);
    if (target.year == today.year) return dayMonth(date);
    return fullDate(date);
  }

  /// Fourchette de glucides : « 68–82 g ».
  static String range(double low, double high) =>
      '${number(low)}–${number(high)} g';

  /// Duree courte : « 3 s », « 1 min 12 s ».
  static String duration(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds} s';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return seconds == 0 ? '$minutes min' : '$minutes min $seconds s';
  }

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

/// Libelles francais des jours, utilises par les graphiques.
const List<String> frenchWeekdayInitials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Initialise les donnees de locale francaise.
///
/// Sans cet appel, `DateFormat('...', 'fr_FR')` retombe silencieusement sur
/// l'anglais : les mois s'affichent alors en anglais sans qu'aucune erreur ne
/// soit levee. A appeler une seule fois, avant `runApp`.
Future<void> initializeFormatting() => initializeDateFormatting('fr_FR');
