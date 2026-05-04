import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/model/photo_type_mode.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'a_cut_result_screen.dart';

class BestCutGalleryScreen extends StatefulWidget {
  const BestCutGalleryScreen({super.key});

  @override
  State<BestCutGalleryScreen> createState() => _BestCutGalleryScreenState();
}

class _BestCutGalleryScreenState extends State<BestCutGalleryScreen> {
  bool _loading = true;
  bool _granted = false;
  bool _showSettingsShortcut = false;
  String? _errorMessage;

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _photos = [];
  final Map<String, AssetEntity> _selectedAssetsById = {};
  final Map<String, Future<Uint8List?>> _thumbCache = {};
  final PhotoTypeMode _photoTypeMode = PhotoTypeMode.auto;

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
      final permission = await PhotoManager.requestPermissionExtend();

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
          _thumbCache.clear();
          _selectedAssetsById.clear();
          _errorMessage = null;
        });
        return;
      }

      final filterOption = FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: filterOption,
      );

      if (albums.isEmpty) {
        if (!mounted) return;
        setState(() {
          _granted = true;
          _loading = false;
          _showSettingsShortcut = false;
          _albums = [];
          _selectedAlbum = null;
          _photos = [];
          _thumbCache.clear();
          _selectedAssetsById.clear();
          _errorMessage = null;
        });
        return;
      }

      final firstAlbum = albums.first;
      final photos = await _loadPhotosFromAlbum(firstAlbum);

      if (!mounted) return;
      setState(() {
        _granted = true;
        _loading = false;
        _showSettingsShortcut = false;
        _albums = albums;
        _selectedAlbum = firstAlbum;
        _photos = photos;
        _thumbCache
          ..clear()
          ..addEntries(
            photos.map((asset) => MapEntry(asset.id, _loadThumb(asset))),
          );
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Best cut gallery load error: $e');

      if (!mounted) return;
      setState(() {
        _granted = true;
        _loading = false;
        _showSettingsShortcut = false;
        _albums = [];
        _selectedAlbum = null;
        _photos = [];
        _thumbCache.clear();
        _selectedAssetsById.clear();
        _errorMessage = '갤러리 정보를 불러오는 중 문제가 발생했습니다.';
      });
    }
  }

  Future<List<AssetEntity>> _loadPhotosFromAlbum(AssetPathEntity album) async {
    try {
      final totalCount = await album.assetCountAsync;
      final end = totalCount > 200 ? 200 : totalCount;

      if (end <= 0) return [];

      return await album.getAssetListRange(start: 0, end: end);
    } catch (e) {
      debugPrint('Best cut album load error: $e');
      return [];
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    if (_selectedAlbum?.id == album.id) return;

    _thumbCache.clear();
    setState(() {
      _loading = true;
      _selectedAlbum = album;
      _errorMessage = null;
    });

    final photos = await _loadPhotosFromAlbum(album);
    if (!mounted) return;

    setState(() {
      _photos = photos;
      _thumbCache.addEntries(
        photos.map((asset) => MapEntry(asset.id, _loadThumb(asset))),
      );
      _loading = false;
    });
  }

  Future<Uint8List?> _loadThumb(AssetEntity asset) async {
    try {
      return await asset.thumbnailDataWithSize(const ThumbnailSize(500, 500));
    } catch (e) {
      debugPrint('Best cut thumbnail error: $e');
      return null;
    }
  }

  Future<Uint8List?> _thumb(AssetEntity asset) {
    return _thumbCache.putIfAbsent(asset.id, () => _loadThumb(asset));
  }

  String _albumLabel(AssetPathEntity album) {
    final name = album.name.trim();
    return name.isEmpty ? 'Album' : name;
  }

  Future<void> _openSettings() async {
    await PhotoManager.openSetting();
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

  void _clearSelection() {
    setState(() {
      _selectedAssetsById.clear();
    });
  }

  Future<void> _openACutResultScreen() async {
    if (_selectedAssetsById.isEmpty) return;

    final selectedAssets = _selectedAssetsById.values.toList(growable: false);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ACutResultScreen(
          selectedAssets: selectedAssets,
          initialPhotoTypeMode: _photoTypeMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            if (_granted && _albums.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: _BestCutAlbumChipRow(
                  albums: _albums,
                  selectedAlbum: _selectedAlbum,
                  onSelected: _selectAlbum,
                  labelBuilder: _albumLabel,
                ),
              ),
            if (_granted && _albums.isNotEmpty) const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const _BestCutLoadingView()
                  : !_granted
                  ? _BestCutPermissionView(
                      onRetry: _loadAlbumsAndPhotos,
                      onOpenSettings: _showSettingsShortcut
                          ? _openSettings
                          : null,
                    )
                  : _errorMessage != null
                  ? _BestCutErrorView(
                      message: _errorMessage!,
                      onRetry: _loadAlbumsAndPhotos,
                    )
                  : _albums.isEmpty
                  ? const _BestCutEmptyAlbumView()
                  : _photos.isEmpty
                  ? _BestCutEmptyPhotoView(
                      albumName: _albumLabel(_selectedAlbum!),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 10, 10),
                            child: Row(
                              children: [
                                Expanded(
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
                                GestureDetector(
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
                              ],
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
                              return GestureDetector(
                                onTap: () => _toggleAssetSelection(asset),
                                child: _BestCutGalleryThumb(
                                  future: _thumb(asset),
                                  selectedOrder: _selectionOrder(asset.id),
                                ),
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
              _BestCutSelectionActionBar(
                selectedCount: _selectedAssetsById.length,
                onClear: _selectedAssetsById.isEmpty ? null : _clearSelection,
                onAnalyze: _openACutResultScreen,
              ),
          ],
        ),
      ),
    );
  }
}

class _BestCutAlbumChipRow extends StatelessWidget {
  final List<AssetPathEntity> albums;
  final AssetPathEntity? selectedAlbum;
  final ValueChanged<AssetPathEntity> onSelected;
  final String Function(AssetPathEntity) labelBuilder;

  const _BestCutAlbumChipRow({
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

class _BestCutGalleryThumb extends StatelessWidget {
  final Future<Uint8List?> future;
  final int? selectedOrder;

  const _BestCutGalleryThumb({
    required this.future,
    required this.selectedOrder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
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

        if (selectedOrder == null) {
          return child;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryText, width: 2),
                color: Colors.black.withValues(alpha: 0.22),
              ),
            ),
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
                alignment: Alignment.center,
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
          ],
        );
      },
    );
  }
}

class _BestCutSelectionActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback? onClear;
  final VoidCallback onAnalyze;

  const _BestCutSelectionActionBar({
    required this.selectedCount,
    required this.onClear,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final canAnalyze = selectedCount >= 1;
    final title = switch (selectedCount) {
      0 => '사진 선택',
      1 => '1장 선택됨',
      _ => '$selectedCount장 선택됨',
    };
    final subtitle = switch (selectedCount) {
      0 => '사진을 탭으로 선택해 주세요.',
      1 => '1장 평가 또는 사진을 더 추가해 A컷 랭킹으로 비교하세요.',
      _ => '선택한 사진들로 베스트 컷 분석을 시작할 수 있어요.',
    };
    final buttonLabel = selectedCount == 1 ? '사진 평가하기' : '베스트 컷 분석하기';

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                TextButton(onPressed: onClear, child: const Text('초기화')),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: canAnalyze ? onAnalyze : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonDark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.track,
                disabledForegroundColor: AppColors.lightText,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BestCutLoadingView extends StatelessWidget {
  const _BestCutLoadingView();

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

class _BestCutPermissionView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  const _BestCutPermissionView({required this.onRetry, this.onOpenSettings});

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
              Text(
                '갤러리 접근 권한이 필요합니다.',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '허용하면 여러 장 사진을 선택해서 베스트 컷 분석을 시작할 수 있습니다.',
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
                    '권한 허용 다시 시도',
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

class _BestCutErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _BestCutErrorView({required this.message, required this.onRetry});

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
                    '다시 시도',
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

class _BestCutEmptyAlbumView extends StatelessWidget {
  const _BestCutEmptyAlbumView();

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
              '표시할 앨범이 없습니다.',
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

class _BestCutEmptyPhotoView extends StatelessWidget {
  final String albumName;

  const _BestCutEmptyPhotoView({required this.albumName});

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
                '$albumName 앨범에 표시할 사진이 없습니다.',
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
