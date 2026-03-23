import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'figma_camera.dart';
import 'figma_common.dart';
import 'figma_gallery.dart';

class FigmaDesignScreen extends StatefulWidget {
  const FigmaDesignScreen({super.key});

  @override
  State<FigmaDesignScreen> createState() => _FigmaDesignScreenState();
}

class _FigmaDesignScreenState extends State<FigmaDesignScreen> {
  FigmaNavTab _currentTab = FigmaNavTab.home;

  void _onTabSelected(FigmaNavTab tab) {
    if (tab == FigmaNavTab.camera) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const FigmaCameraScreen(),
          fullscreenDialog: true,
        ),
      );
      return;
    }

    setState(() {
      _currentTab = tab;
    });
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case FigmaNavTab.gallery:
        return const FigmaGalleryContent();
      case FigmaNavTab.home:
        return const _FigmaHomeContent();
      case FigmaNavTab.camera:
        return const _FigmaHomeContent();
      case FigmaNavTab.bestCut:
        return const _ComingSoonContent(title: 'Best Cut');
      case FigmaNavTab.editor:
        return const _ComingSoonContent(title: 'Editor');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarBg = _currentTab == FigmaNavTab.gallery
        ? Colors.white
        : const Color(0xFFF7F7F7);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: FigmaTopHeader(backgroundColor: appBarBg),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey<FigmaNavTab>(_currentTab),
          child: _buildBody(),
        ),
      ),
      bottomNavigationBar: FigmaBottomNavBar(
        currentTab: _currentTab,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}

class _FigmaHomeContent extends StatelessWidget {
  const _FigmaHomeContent();

  static const _quickImage =
      'https://www.figma.com/api/mcp/asset/0740fd63-cff8-4169-a929-e3406157b941';
  static const _galleryImage =
      'https://www.figma.com/api/mcp/asset/e41bd470-ad50-4ae0-a550-54e17c1b24a3';
  static const _bestImage =
      'https://www.figma.com/api/mcp/asset/de9cb9ef-f0c9-4f30-9211-c11a55e9c131';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = (width / 430).clamp(0.84, 1.18);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16 * scale,
            12 * scale,
            16 * scale,
            24 * scale,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              SizedBox(height: 20 * scale),
              Text(
                '당신의 촬영 경험을 보다 이롭게',
                style: TextStyle(
                  fontSize: 24 * scale,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF333333),
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(height: 4 * scale),
              Text(
                '상상을 현실로, Pozy를 경험해보세요!',
                style: TextStyle(
                  fontSize: 14 * scale,
                  height: 1.35,
                  color: const Color(0xFF64748B),
                ),
              ),
              SizedBox(height: 16 * scale),
              _FeatureCard(
                scale: scale,
                title: 'Quick Shoot',
                subtitle:
                    'Start capturing high-quality moments instantly\nwith one tap.',
                buttonText: 'Launch',
                iconUrl: FigmaIconUrls.quickShoot,
                previewUrl: _quickImage,
              ),
              SizedBox(height: 16 * scale),
              _FeatureCard(
                scale: scale,
                title: 'Gallery',
                subtitle:
                    'View, organize, and\nmanage your entire\nmedia library.',
                buttonText: 'Open',
                iconUrl: FigmaIconUrls.galleryCard,
                previewUrl: _galleryImage,
              ),
              SizedBox(height: 16 * scale),
              _FeatureCard(
                scale: scale,
                title: 'Pick your Best',
                subtitle:
                    'Enjoy Pozy to the fullest,\nsuggest the best shots\nfrom your bursts.',
                buttonText: 'Try Now',
                iconUrl: FigmaIconUrls.bestCard,
                previewUrl: _bestImage,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ComingSoonContent extends StatelessWidget {
  const _ComingSoonContent({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title 화면 준비 중',
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.scale,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.iconUrl,
    required this.previewUrl,
  });

  final double scale;
  final String title;
  final String subtitle;
  final String buttonText;
  final String iconUrl;
  final String previewUrl;

  @override
  Widget build(BuildContext context) {
    final imageSize = (128 * scale).clamp(96, 128).toDouble();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(21 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: 12 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset(
                        iconUrl,
                        width: 20 * scale,
                        height: 20 * scale,
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 18 * scale,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF333333),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * scale),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14 * scale,
                      height: 1.4,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(height: 16 * scale),
                  SizedBox(
                    width: 172 * scale,
                    height: 36 * scale,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F5F9),
                        foregroundColor: const Color(0xFF333333),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8 * scale),
                        ),
                      ),
                      onPressed: () {},
                      child: Text(
                        buttonText,
                        style: TextStyle(
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8 * scale),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(previewUrl, fit: BoxFit.cover),
          ),
        ],
      ),
    );
  }
}

