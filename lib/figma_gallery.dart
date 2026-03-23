import 'dart:io';

import 'package:flutter/material.dart';

import 'services/photo_service.dart';

class FigmaGalleryContent extends StatefulWidget {
  const FigmaGalleryContent({super.key});

  @override
  State<FigmaGalleryContent> createState() => _FigmaGalleryContentState();
}

class _FigmaGalleryContentState extends State<FigmaGalleryContent> {
  static const _recentPhotos = <String>[
    'https://www.figma.com/api/mcp/asset/7c72676c-c501-4dbc-ae93-9ea06e4e01e9',
    'https://www.figma.com/api/mcp/asset/34e2f1db-78bb-4074-a491-fc3b9663f252',
    'https://www.figma.com/api/mcp/asset/05cb00ef-05c6-4f4b-8547-50bf903c7a48',
    'https://www.figma.com/api/mcp/asset/547bf7df-ebbf-4b7e-b7ad-7eafc35d301b',
    'https://www.figma.com/api/mcp/asset/ec03304e-0a52-4a49-baa3-303c61fc9b4e',
    'https://www.figma.com/api/mcp/asset/98f7b894-57b4-4921-98e0-e9569c062fd6',
  ];

  static const _lastWeekPhotos = <String>[
    'https://www.figma.com/api/mcp/asset/95fddb47-8f7c-446d-8dae-78b312929d18',
    'https://www.figma.com/api/mcp/asset/c1a4d59f-9d00-4488-9095-3b8bc74ba7fe',
    'https://www.figma.com/api/mcp/asset/c7151830-7a11-4e90-b35f-626228f925c8',
    'https://www.figma.com/api/mcp/asset/0d6b8b1d-d650-49af-8228-d127eb385bfe',
    'https://www.figma.com/api/mcp/asset/1ffb2398-0c61-4cfa-8dbc-3d50a8e0ed67',
    'https://www.figma.com/api/mcp/asset/1b51621e-1c34-45d2-985b-034c8a685341',
    'https://www.figma.com/api/mcp/asset/8de5d9dd-acf3-44bc-8148-e075604f2fc7',
    'https://www.figma.com/api/mcp/asset/2556ccb0-9dfe-439e-b7e0-21937542cf5f',
    'https://www.figma.com/api/mcp/asset/a4ce703d-2057-41a9-9df0-d26d24021dae',
    'https://www.figma.com/api/mcp/asset/95fddb47-8f7c-446d-8dae-78b312929d18',
    'https://www.figma.com/api/mcp/asset/c1a4d59f-9d00-4488-9095-3b8bc74ba7fe',
    'https://www.figma.com/api/mcp/asset/c7151830-7a11-4e90-b35f-626228f925c8',
  ];

  final PhotoService _photoService = PhotoService();
  List<File> _savedPhotos = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshSavedPhotos();
  }

  Future<void> _refreshSavedPhotos() async {
    try {
      final files = await _photoService.loadPhotos();
      if (!mounted) return;
      setState(() {
        _savedPhotos = files;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진 로드 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        SizedBox(
          height: 68,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            scrollDirection: Axis.horizontal,
            children: const [
              _FilterChip(label: 'All Photos', selected: true),
              SizedBox(width: 6),
              _FilterChip(label: 'Favorites'),
              SizedBox(width: 6),
              _FilterChip(label: 'Screenshot'),
              SizedBox(width: 6),
              _FilterChip(label: 'Videos'),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshSavedPhotos,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('RECENT'),
                  const SizedBox(height: 12),
                  const _PhotoGrid(imageUrls: _recentPhotos),
                  const SizedBox(height: 28),
                  const _SectionTitle('LAST WEEK'),
                  const SizedBox(height: 12),
                  const _PhotoGrid(imageUrls: _lastWeekPhotos),
                  const SizedBox(height: 28),
                  const _SectionTitle('MY PHOTOS'),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_savedPhotos.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Text(
                        '저장된 사진이 없습니다. 카메라에서 촬영해보세요.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    _SavedPhotoGrid(files: _savedPhotos),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 28,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: Color(0xFF333333),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    this.selected = false,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF333333) : const Color(0x1A333333),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF333333),
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GridView.builder(
        itemCount: imageUrls.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          return ColoredBox(
            color: const Color(0xFFE2E8F0),
            child: Image.network(
              imageUrls[index],
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) {
                return const Icon(Icons.image_not_supported_outlined);
              },
            ),
          );
        },
      ),
    );
  }
}

class _SavedPhotoGrid extends StatelessWidget {
  const _SavedPhotoGrid({required this.files});

  final List<File> files;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GridView.builder(
        itemCount: files.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          return ColoredBox(
            color: const Color(0xFFE2E8F0),
            child: Image.file(
              files[index],
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) {
                return const Icon(Icons.broken_image_outlined);
              },
            ),
          );
        },
      ),
    );
  }
}
