import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Enveloppe des cinq onglets principaux.
///
/// La barre de navigation reste visible en permanence : les actions du
/// quotidien ne doivent jamais etre a plus d'un geste.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Accueil',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'Historique',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights_rounded),
      label: 'Statistiques',
    ),
    NavigationDestination(
      icon: Icon(Icons.star_outline_rounded),
      selectedIcon: Icon(Icons.star_rounded),
      label: 'Favoris',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Reglages',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
            ),
          ),
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            destinations: _destinations,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              // Appuyer sur l'onglet deja actif revient a sa racine.
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ),
      ),
    );
  }
}
