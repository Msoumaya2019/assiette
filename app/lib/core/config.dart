/// Configuration compilee dans l'application.
///
/// Les valeurs sensibles ne figurent JAMAIS ici. Deux modes d'analyse existent :
///
///  * [AnalysisMode.personal] : l'utilisateur saisit sa propre cle fournisseur.
///    Elle est stockee dans le trousseau du systeme (Keychain / Keystore), pas
///    dans le binaire. Aucun backend n'est necessaire.
///
///  * [AnalysisMode.proxy] : l'application appelle une fonction serveur qui
///    detient la cle. Mode prevu pour la publication publique.
///
/// Les valeurs ci-dessous proviennent de `--dart-define` au moment de la
/// compilation (voir .github/workflows/android.yml et ios.yml).
library;

enum AnalysisMode {
  /// Cle fournie par l'utilisateur, stockee dans le trousseau du systeme.
  personal,

  /// Appel d'une fonction serveur qui detient la cle.
  proxy,
}

class AppConfig {
  const AppConfig._();

  /// Nom affiche de l'application.
  static const String appName = 'Assiette';

  /// Version de l'application, telle qu'inscrite dans le binaire.
  ///
  /// Fournie a la compilation par `--dart-define=APP_VERSION=…`, alimentee par
  /// `tools/version_build.sh` — le meme script qui decide de la version de
  /// l'APK, de l'AAB et de l'IPA. L'ecran des reglages affiche donc exactement
  /// ce que le systeme lit dans le paquet installe.
  ///
  /// Recopier la version ici aurait l'air plus simple, et c'est ce qui avait ete
  /// fait : l'ecran annoncait `0.1.0` alors que le binaire etait `0.1.2`. Une
  /// valeur recopiee finit par mentir, parce que rien ne la relie a la source.
  ///
  /// Hors compilation par les flux — un `flutter run` local — la valeur vaut
  /// `dev`, ce qui est exact : cette compilation-la ne porte aucun numero de
  /// version.
  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  /// Identifiant de version, utile pour les rapports d'erreur.
  static const String buildChannel = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// URL de la fonction d'analyse cote serveur (mode proxy).
  static const String analysisEndpoint = String.fromEnvironment(
    'ANALYSIS_ENDPOINT',
  );

  /// Projet Supabase (synchronisation et compte). Facultatif.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Cle publique Supabase. Publique par conception : la protection repose sur
  /// les politiques RLS, pas sur le secret de cette cle.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Mode d'analyse par defaut a la premiere ouverture.
  ///
  /// Si un point d'entree serveur est compile, on l'utilise ; sinon l'application
  /// bascule en mode personnel et invite l'utilisateur a saisir sa cle.
  static AnalysisMode get defaultAnalysisMode =>
      analysisEndpoint.isNotEmpty ? AnalysisMode.proxy : AnalysisMode.personal;

  /// Fournisseur compatible OpenAI utilise en mode personnel.
  static const String providerBaseUrl = 'https://api.deepseek.com';

  /// Modele multimodal. `deepseek-flash` accepte les images et le mode JSON.
  static const String providerModel = 'deepseek-flash';

  /// Identifiant envoye a Open Food Facts. Exige par leur politique d'usage.
  ///
  /// L'adresse doit pointer vers un depot qui existe : leur politique demande
  /// de pouvoir identifier l'auteur de l'application. Une adresse morte revient
  /// a ne pas repondre.
  static const String openFoodFactsUserAgent =
      'Assiette/0.1 (https://github.com/Msoumaya2019/assiette)';

  /// URL d'assistance, affichee dans les parametres et les fiches de store.
  static const String supportUrl =
      'https://github.com/Msoumaya2019/assiette/issues';

  /// Version de la politique de confidentialite acceptee par l'utilisateur.
  static const String privacyPolicyVersion = '1.0';
}
