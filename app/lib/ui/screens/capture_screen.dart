import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/failures.dart';
import '../../core/theme.dart';
import '../../models/meal.dart';
import '../../services/image_service.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';

/// Ecran de capture.
///
/// Deux modes coexistent, sans choix prealable impose :
///  * mode rapide : une seule photo suffit, c'est le cas courant ;
///  * mode plus precis : une seconde photo sous un autre angle affine
///    l'estimation du volume.
///
/// La photo n'est jamais envoyee depuis cet ecran : elle est d'abord confirmee
/// par l'utilisateur, puis analysee.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, this.source});

  /// « camera » ou « gallery », pour ouvrir directement le bon selecteur.
  final String? source;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final List<CapturedImage> _photos = [];
  PortionSize? _portion;
  String? _error;
  bool _busy = false;

  static const int _maxPhotos = 2;

  bool get _canAddPhoto => _photos.length < _maxPhotos;

  @override
  void initState() {
    super.initState();
    // Ouverture directe du selecteur demande par l'ecran precedent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.source) {
        case 'camera':
          _addPhoto(fromCamera: true);
        case 'gallery':
          _addPhoto(fromCamera: false);
      }
    });
  }

  Future<void> _addPhoto({required bool fromCamera}) async {
    if (_busy || !_canAddPhoto) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = ref.read(imageServiceProvider);
      final photo = fromCamera ? await service.pickFromCamera() : await service.pickFromGallery();
      if (!mounted) return;
      if (photo == null) {
        // L'utilisateur a annule : ce n'est pas une erreur.
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _photos.add(photo);
        _busy = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.hint == null ? failure.message : '${failure.message} — ${failure.hint}';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppFailure.from(error).message;
        _busy = false;
      });
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  Future<void> _analyze() async {
    if (_photos.isEmpty) return;

    final imageService = ref.read(imageServiceProvider);
    final settings = ref.read(settingsProvider);

    final meal = Meal(
      eatenAt: DateTime.now(),
      name: 'Repas',
      items: const [],
      source: MealSource.photo,
    );

    // La photo n'est conservee que si l'utilisateur l'a demande : moins de
    // donnees sur l'appareil, et un espace de stockage maitrise.
    final photoPath = settings.keepPhotos
        ? await imageService.persist(_photos.first, meal.id)
        : null;

    ref.read(pendingCaptureProvider.notifier).set(
          PendingCapture(
            image: _photos.first,
            secondImage: _photos.length > 1 ? _photos[1] : null,
            portionHint: _portion?.name,
          ),
        );
    ref.read(draftMealProvider.notifier).start(meal.copyWith(photoPath: photoPath));

    if (!mounted) return;
    context.pushReplacement(Routes.analysis);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo du repas'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Fermer',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const EstimateBanner(),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              EstimateBanner(message: _error!, severity: EstimateSeverity.danger),
            ],

            const SizedBox(height: AppSpacing.lg),

            if (_photos.isEmpty)
              _EmptyCapture(
                busy: _busy,
                onCamera: () => _addPhoto(fromCamera: true),
                onGallery: () => _addPhoto(fromCamera: false),
              )
            else
              _PhotoPreview(
                photos: _photos,
                busy: _busy,
                canAdd: _canAddPhoto,
                onRemove: _removePhoto,
                onCamera: () => _addPhoto(fromCamera: true),
                onGallery: () => _addPhoto(fromCamera: false),
              ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Taille de la portion',
              subtitle: 'Facultatif : affine l\'estimation',
              child: Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final portion in PortionSize.values)
                    ChoiceChip(
                      label: Text(portion.label),
                      selected: _portion == portion,
                      onSelected: (selected) =>
                          setState(() => _portion = selected ? portion : null),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            FilledButton.icon(
              onPressed: _photos.isEmpty || _busy ? null : _analyze,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _photos.isEmpty
                    ? 'Ajoutez une photo'
                    : _photos.length == 1
                        ? 'Analyser ce repas'
                        : 'Analyser avec les 2 photos',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCapture extends StatelessWidget {
  const _EmptyCapture({required this.busy, required this.onCamera, required this.onGallery});

  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _BigButton(
          icon: Icons.photo_camera_rounded,
          title: 'Prendre une photo',
          subtitle: 'Cadrez l\'assiette entiere, vue du dessus',
          primary: true,
          enabled: !busy,
          onTap: onCamera,
        ),
        const SizedBox(height: AppSpacing.sm),
        _BigButton(
          icon: Icons.photo_library_rounded,
          title: 'Choisir dans la galerie',
          subtitle: 'Une photo deja prise',
          enabled: !busy,
          onTap: onGallery,
        ),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.photos,
    required this.busy,
    required this.canAdd,
    required this.onRemove,
    required this.onCamera,
    required this.onGallery,
  });

  final List<CapturedImage> photos;
  final bool busy;
  final bool canAdd;
  final void Function(int) onRemove;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: Row(
            children: [
              for (var index = 0; index < photos.length; index++) ...[
                Expanded(
                  child: _PhotoThumb(
                    photo: photos[index],
                    index: index,
                    onRemove: () => onRemove(index),
                  ),
                ),
                if (index != photos.length - 1) const SizedBox(width: AppSpacing.sm),
              ],
              if (canAdd) ...[
                if (photos.isNotEmpty) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _AddSecondPhoto(
                    enabled: !busy,
                    onCamera: onCamera,
                    onGallery: onGallery,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          photos.length == 1
              ? 'Une seconde photo sous un autre angle ameliore l\'estimation du volume.'
              : 'Deux angles fournis : l\'estimation sera plus fiable.',
          style: TextStyle(fontSize: 12, color: context.palette.mutedText),
        ),
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.index, required this.onRemove});

  final CapturedImage photo;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Image.memory(photo.bytes, fit: BoxFit.cover),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              index == 0 ? 'Angle 1' : 'Angle 2',
              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddSecondPhoto extends StatelessWidget {
  const _AddSecondPhoto({required this.enabled, required this.onCamera, required this.onGallery});

  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () => showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_camera_rounded),
                        title: const Text('Prendre une seconde photo'),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onCamera();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library_rounded),
                        title: const Text('Choisir dans la galerie'),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onGallery();
                        },
                      ),
                    ],
                  ),
                ),
              )
          : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: context.colors.primary.withValues(alpha: 0.5),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_rounded, color: context.colors.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Second angle',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: primary ? colors.primary : colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: primary ? null : Border.all(color: context.palette.cardBorder),
            ),
            child: Row(
              children: [
                Icon(icon, size: 30, color: primary ? colors.onPrimary : colors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: primary ? colors.onPrimary : colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: primary
                              ? colors.onPrimary.withValues(alpha: 0.85)
                              : context.palette.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
