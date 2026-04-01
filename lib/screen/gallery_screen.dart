import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/layer/gallery/gallery_picker_service.dart';
import '../feature/a_cut/model/photo_type_mode.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import 'a_cut_result_screen.dart';
import 'single_photo_eval_screen.dart';

class GalleryScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;

  const GalleryScreen({super.key, required this.onMoveTab});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final GalleryPickerService _galleryPickerService =
      const GalleryPickerService();

  bool _loading = true;
  bool _granted = false;
  bool _showSettingsShortcut = false;
  String? _errorMessage;

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _photos = [];

  // Keeps selected assets across album switches.
  final Map<String, AssetEntity> _selectedAssetsById = {};
  PhotoTypeMode _photoTypeMode = PhotoTypeMode.auto;

  @override
  void initState() {
    super.initState();
    _loadAlbumsAndPhotos();
  }

  Future<void> _loadAlbumsAndPhotos() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final permission = await _galleryPickerService.requestPermission();

      if (!permission.isAuth && !permission.hasAccess) {
        if (!mounted) return;
        setState(() {
          _granted = false;
          _loading = false;
          _showSettingsShortcut =
              permission == PermissionState.denied ||
              permission == PermissionState.restricted;
          _albums = [];
          _selectedAlbum = null;
          _photos = [];
          _errorMessage = null;
          _selectedAssetsById.clear();
        });
        return;
      }

      final albums = await _galleryPickerService.loadAlbums();

      if (albums.isEmpty) {
        if (!mounted) return;
        setState(() {
          _granted = true;
          _loading = false;
          _showSettingsShortcut = false;
          _albums = [];
          _selectedAlbum = null;
          _photos = [];
          _errorMessage = null;
          _selectedAssetsById.clear();
        });
        return;
      }

      final firstAlbum = albums.first;
      final photos = await _galleryPickerService.loadPhotos(album: firstAlbum);

      if (!mounted) return;
      setState(() {
        _granted = true;
        _loading = false;
        _showSettingsShortcut = false;
        _albums = albums;
        _selectedAlbum = firstAlbum;
        _photos = photos;
        _errorMessage = null;
      });
    } catch (error) {
      debugPrint('Gallery load error: $error');

      if (!mounted) return;
      setState(() {
        _granted = true;
        _loading = false;
        _showSettingsShortcut = false;
        _albums = [];
        _selectedAlbum = null;
        _photos = [];
        _errorMessage = 'Could not load albums and photos.';
      });
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    if (_selectedAlbum?.id == album.id) return;

    setState(() {
      _loading = true;
      _selectedAlbum = album;
      _errorMessage = null;
    });

    try {
      final photos = await _galleryPickerService.loadPhotos(album: album);

      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Album switch error: $error');

      if (!mounted) return;
      setState(() {
        _photos = [];
        _loading = false;
        _errorMessage = 'Could not load selected album.';
      });
    }
  }

  Future<Uint8List?> _thumb(AssetEntity asset) async {
    try {
      return await _galleryPickerService.loadThumbnail(asset);
    } catch (error) {
      debugPrint('Thumbnail error: $error');
      return null;
    }
  }

  String _albumLabel(AssetPathEntity album) {
    final name = album.name.trim();
    if (name.isEmpty) return 'Album';
    return name;
  }

  Future<void> _openSettings() {
    return _galleryPickerService.openSystemSettings();
  }

  void _toggleAssetSelection(AssetEntity asset) {
    setState(() {
      if (_selectedAssetsById.containsKey(asset.id)) {
        _selectedAssetsById.remove(asset.id);
      } else {
        _selectedAssetsById[asset.id] = asset;
      }
    });
  }

  int? _selectionOrder(String assetId) {
    final index = _selectedAssetsById.keys.toList().indexOf(assetId);
    if (index < 0) return null;
    return index + 1;
  }

  Future<void> _openACutResultScreen() async {
    if (_selectedAssetsById.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 사진을 1장 이상 선택해 주세요.')));
      return;
    }

    final selectedAssets = _selectedAssetsById.values.toList(growable: false);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ACutResultScreen(
          selectedAssets: selectedAssets,
          initialPhotoTypeMode: _photoTypeMode,
        ),
      ),
    );
  }

  Future<void> _openSinglePhotoEvaluation() async {
    if (_selectedAssetsById.length != 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('사진 1장을 선택해 주세요.')));
      return;
    }

    final asset = _selectedAssetsById.values.first;
    final bytes = await asset.originBytes;
    if (!mounted) return;

    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미지 원본을 불러오지 못했습니다.')));
      return;
    }

    final title = await asset.titleAsync;
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SinglePhotoEvalScreen(
          imageBytes: bytes,
          fileName: title.trim().isEmpty ? 'photo_1' : title,
        ),
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _selectedAssetsById.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: const Color(0xFFF7F7F7),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: 'Gallery',
                trailing: GestureDetector(
                  onTap: _loadAlbumsAndPhotos,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppColors.soft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.refresh,
                      size: 18,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_granted && _albums.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _AlbumChipRow(
                  albums: _albums,
                  selectedAlbum: _selectedAlbum,
                  onSelected: _selectAlbum,
                  labelBuilder: _albumLabel,
                ),
              ),
            if (_granted && _albums.isNotEmpty) const SizedBox(height: 12),
            if (_granted && _albums.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _PhotoTypeSelector(
                  selected: _photoTypeMode,
                  onSelected: (mode) {
                    setState(() {
                      _photoTypeMode = mode;
                    });
                  },
                ),
              ),
            if (_granted && _albums.isNotEmpty) const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const _LoadingView()
                  : !_granted
                  ? _PermissionView(
                      onRetry: _loadAlbumsAndPhotos,
                      onOpenSettings: _showSettingsShortcut
                          ? _openSettings
                          : null,
                    )
                  : _errorMessage != null
                  ? _ErrorView(
                      message: _errorMessage!,
                      onRetry: _loadAlbumsAndPhotos,
                    )
                  : _albums.isEmpty
                  ? const _EmptyAlbumView()
                  : _photos.isEmpty
                  ? _EmptyPhotoView(albumName: _albumLabel(_selectedAlbum!))
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                            child: Text(
                              _albumLabel(_selectedAlbum!).toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryText,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final asset = _photos[index];
                              final order = _selectionOrder(asset.id);
                              return _GalleryThumb(
                                future: _thumb(asset),
                                selectedOrder: order,
                                onTap: () => _toggleAssetSelection(asset),
                              );
                            }, childCount: _photos.length),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 4,
                                  crossAxisSpacing: 4,
                                  childAspectRatio: 1,
                                ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (_granted && _albums.isNotEmpty)
              _SelectionActionBar(
                selectedCount: _selectedAssetsById.length,
                onClear: _selectedAssetsById.isEmpty ? null : _clearSelection,
                onEvaluateSingle: _openSinglePhotoEvaluation,
                onAnalyze: _openACutResultScreen,
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTypeSelector extends StatelessWidget {
  final PhotoTypeMode selected;
  final ValueChanged<PhotoTypeMode> onSelected;

  const _PhotoTypeSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: PhotoTypeMode.values.map((mode) {
        final isSelected = selected == mode;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF3A3A3A)
                      : const Color(0xFFEFEFEF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF5A5A5A),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback? onClear;
  final VoidCallback onEvaluateSingle;
  final VoidCallback onAnalyze;

  const _SelectionActionBar({
    required this.selectedCount,
    required this.onClear,
    required this.onEvaluateSingle,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '선택됨 $selectedCount장',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              if (onClear != null)
                TextButton(onPressed: onClear, child: const Text('초기화')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (selectedCount == 1) ...[
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: onEvaluateSingle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryText,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '사진 평가',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: onAnalyze,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'A컷 분석',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlbumChipRow extends StatelessWidget {
  final List<AssetPathEntity> albums;
  final AssetPathEntity? selectedAlbum;
  final ValueChanged<AssetPathEntity> onSelected;
  final String Function(AssetPathEntity) labelBuilder;

  const _AlbumChipRow({
    required this.albums,
    required this.selectedAlbum,
    required this.onSelected,
    required this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final album = albums[index];
          final selected = selectedAlbum?.id == album.id;

          return GestureDetector(
            onTap: () => onSelected(album),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFEFEFEF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Text(
                  labelBuilder(album),
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF5A5A5A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  final Future<Uint8List?> future;
  final int? selectedOrder;
  final VoidCallback onTap;

  const _GalleryThumb({
    required this.future,
    required this.selectedOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedOrder != null;

    return GestureDetector(
      onTap: onTap,
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEDEFF3),
                borderRadius: BorderRadius.circular(14),
              ),
            );
          }

          Widget child;
          if (!snapshot.hasData || snapshot.data == null) {
            child = Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEDEFF3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.lightText,
                  size: 22,
                ),
              ),
            );
          } else {
            child = ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(snapshot.data!, fit: BoxFit.cover),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primaryText, width: 2),
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ),
              if (isSelected)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryText,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$selectedOrder',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        strokeWidth: 2.6,
        color: AppColors.primaryText,
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  const _PermissionView({required this.onRetry, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 42,
                color: AppColors.primaryText,
              ),
              const SizedBox(height: 14),
              const Text(
                'Gallery permission is required.',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Allow permission to read photos from your library.',
                style: AppTextStyles.body13,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.buttonDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Retry Permission',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (onOpenSettings != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: onOpenSettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      side: const BorderSide(color: Color(0xFFD6D6D6)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Open Settings',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 42,
                color: AppColors.primaryText,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.buttonDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAlbumView extends StatelessWidget {
  const _EmptyAlbumView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_album_outlined,
              size: 42,
              color: AppColors.primaryText,
            ),
            SizedBox(height: 14),
            Text(
              'No albums found.',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPhotoView extends StatelessWidget {
  final String albumName;

  const _EmptyPhotoView({required this.albumName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_outlined,
                size: 42,
                color: AppColors.primaryText,
              ),
              const SizedBox(height: 14),
              Text(
                'No photos in $albumName.',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
