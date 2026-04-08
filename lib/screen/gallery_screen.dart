import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class GalleryScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final void Function(Future<Uint8List?> future)? onOpenInEditor;

  const GalleryScreen({super.key, required this.onMoveTab, this.onOpenInEditor});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _loading = true;
  bool _granted = false;
  bool _showSettingsShortcut = false;
  String? _errorMessage;

  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _photos = [];

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
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('앨범 로드 에러: $e');

      if (!mounted) return;
      setState(() {
        _granted = true;
        _loading = false;
        _showSettingsShortcut = false;
        _albums = [];
        _selectedAlbum = null;
        _photos = [];
        _errorMessage = '앨범 정보를 불러오는 중 문제가 발생했습니다.';
      });
    }
  }

  Future<List<AssetEntity>> _loadPhotosFromAlbum(AssetPathEntity album) async {
    try {
      final totalCount = await album.assetCountAsync;
      final end = totalCount > 200 ? 200 : totalCount;

      if (end <= 0) return [];

      final assets = await album.getAssetListRange(start: 0, end: end);

      return assets;
    } catch (e) {
      debugPrint('앨범 사진 로드 에러: $e');
      return [];
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
      final photos = await _loadPhotosFromAlbum(album);

      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
      });
    } catch (e) {
      debugPrint('앨범 선택 에러: $e');

      if (!mounted) return;
      setState(() {
        _photos = [];
        _loading = false;
        _errorMessage = '선택한 앨범을 불러오는 중 문제가 발생했습니다.';
      });
    }
  }

  Future<Uint8List?> _thumb(AssetEntity asset) async {
    try {
      return await asset.thumbnailDataWithSize(const ThumbnailSize(500, 500));
    } catch (e) {
      debugPrint('썸네일 생성 에러: $e');
      return null;
    }
  }

  String _albumLabel(AssetPathEntity album) {
    final name = album.name.trim();
    if (name.isEmpty) return 'Album';
    return name;
  }

  Future<void> _openSettings() async {
    await PhotoManager.openSetting();
  }

  void _handlePhotoDeleted(String assetId) {
    setState(() {
      _photos.removeWhere((a) => a.id == assetId);
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
            if (_granted && _albums.isNotEmpty) const SizedBox(height: 18),
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
                              return GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _PhotoDetailPage(
                                      photos: _photos,
                                      initialIndex: index,
                                      onPhotoDeleted: _handlePhotoDeleted,
                                      onOpenInEditor: widget.onOpenInEditor,
                                    ),
                                  ),
                                ),
                                child: Hero(
                                  tag: 'photo_${asset.id}',
                                  child: _GalleryThumb(future: _thumb(asset)),
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
          ],
        ),
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
        separatorBuilder: (context, i) => const SizedBox(width: 8),
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

  const _GalleryThumb({required this.future});

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

        if (!snapshot.hasData || snapshot.data == null) {
          return Container(
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
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(snapshot.data!, fit: BoxFit.cover),
        );
      },
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
                '허용하면 휴대폰에 있는 사진과 앨범을\n앱에서 불러올 수 있습니다.',
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
                  child: Text(
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
                    child: Text(
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

class _PhotoDetailPage extends StatefulWidget {
  final List<AssetEntity> photos;
  final int initialIndex;
  final void Function(String assetId)? onPhotoDeleted;
  final void Function(Future<Uint8List?> future)? onOpenInEditor;

  const _PhotoDetailPage({
    required this.photos,
    required this.initialIndex,
    this.onPhotoDeleted,
    this.onOpenInEditor,
  });

  @override
  State<_PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<_PhotoDetailPage> {
  late int _currentIndex;
  late PageController _pageController;

  // Cache futures so swiping re-uses already-started loads
  final Map<int, Future<Uint8List?>> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _preloadPages(widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _getImage(int index) {
    return _imageCache.putIfAbsent(index, () => widget.photos[index].originBytes);
  }

  void _preloadPages(int index) {
    final start = (index - 1).clamp(0, widget.photos.length - 1);
    final end = (index + 1).clamp(0, widget.photos.length - 1);
    for (int i = start; i <= end; i++) {
      _getImage(i); // starts the future if not already cached
    }
  }

  Future<void> _deleteCurrentPhoto() async {
    final asset = widget.photos[_currentIndex];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사진 삭제'),
        content: const Text('이 사진을 갤러리에서 삭제하시겠습니까?\n삭제 후에는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final deleted = await PhotoManager.editor.deleteWithIds([asset.id]);
    if (!mounted) return;

    if (deleted.contains(asset.id)) {
      widget.onPhotoDeleted?.call(asset.id);
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진 삭제에 실패했습니다.')),
      );
    }
  }

  Future<void> _showPhotoInfo() async {
    final asset = widget.photos[_currentIndex];
    int fileSize = 0;
    try {
      final file = await asset.file;
      if (file != null) fileSize = await file.length();
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => _PhotoInfoDialog(asset: asset, fileSize: fileSize),
    );
  }

  void _openInEditor() {
    if (!mounted) return;
    widget.onOpenInEditor?.call(_getImage(_currentIndex));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              _preloadPages(i);
            },
            itemBuilder: (context, index) {
              final asset = widget.photos[index];
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Hero(
                    tag: 'photo_${asset.id}',
                    child: FutureBuilder<Uint8List?>(
                      future: _getImage(index),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 2,
                            ),
                          );
                        }
                        if (snapshot.data == null) {
                          return const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                            size: 48,
                          );
                        }
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          // 상단 바
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentIndex + 1} / ${widget.photos.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          // 하단 액션 바
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.delete_outline_rounded,
                      label: '삭제',
                      onTap: _deleteCurrentPhoto,
                    ),
                    _ActionButton(
                      icon: Icons.info_outline_rounded,
                      label: '정보',
                      onTap: _showPhotoInfo,
                    ),
                    _ActionButton(
                      icon: Icons.edit_outlined,
                      label: '편집',
                      onTap: _openInEditor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoInfoDialog extends StatelessWidget {
  final AssetEntity asset;
  final int fileSize;

  const _PhotoInfoDialog({required this.asset, required this.fileSize});

  @override
  Widget build(BuildContext context) {
    final date = asset.createDateTime;
    final dateStr =
        '${date.year}년 ${date.month}월 ${date.day}일 '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

    String sizeStr;
    if (fileSize >= 1024 * 1024) {
      sizeStr = '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (fileSize >= 1024) {
      sizeStr = '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      sizeStr = '$fileSize B';
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        '사진 정보',
        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InfoRow(label: '촬영 일시', value: dateStr),
          _InfoRow(label: '해상도', value: '${asset.width} × ${asset.height}'),
          if (fileSize > 0) _InfoRow(label: '파일 크기', value: sizeStr),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
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
