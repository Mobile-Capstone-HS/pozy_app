import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum FigmaNavTab { home, gallery, camera, bestCut, editor }

class FigmaIconUrls {
  const FigmaIconUrls._();

  static const menu = 'assets/figma/icons/menu.svg';
  static const profile = 'assets/figma/icons/profile.svg';
  static const quickShoot = 'assets/figma/icons/quick_shoot.svg';
  static const galleryCard = 'assets/figma/icons/gallery_card.svg';
  static const bestCard = 'assets/figma/icons/best_card.svg';

  static const homeNav = 'assets/figma/icons/nav_home.svg';
  static const galleryNav = 'assets/figma/icons/nav_gallery.svg';
  static const bestNav = 'assets/figma/icons/nav_best_cut.svg';
  static const editorNav = 'assets/figma/icons/nav_editor.svg';
  static const cameraNav = 'assets/figma/icons/nav_camera.svg';
}

class FigmaTopHeader extends StatelessWidget implements PreferredSizeWidget {
  const FigmaTopHeader({
    super.key,
    this.onMenuTap,
    this.onProfileTap,
    this.backgroundColor = const Color(0xFFF3F4F6),
  });

  final VoidCallback? onMenuTap;
  final VoidCallback? onProfileTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 390;

    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      centerTitle: true,
      leadingWidth: 52,
      leading: IconButton(
        onPressed: onMenuTap,
        icon: const _SvgIcon(FigmaIconUrls.menu, width: 18, height: 12),
      ),
      title: Text(
        'Pozy',
        style: TextStyle(
          color: const Color(0xFF333333),
          fontSize: compact ? 28 : 32,
          fontWeight: FontWeight.w700,
          height: 1,
          letterSpacing: -0.4,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            onPressed: onProfileTap,
            icon: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: _SvgIcon(FigmaIconUrls.profile, width: 20, height: 20),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class FigmaBottomNavBar extends StatelessWidget {
  const FigmaBottomNavBar({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
  });

  final FigmaNavTab currentTab;
  final ValueChanged<FigmaNavTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isGallery = currentTab == FigmaNavTab.gallery;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 82 + bottomInset,
      padding: EdgeInsets.only(
        bottom: bottomInset + 6,
        left: 8,
        right: 8,
        top: 8,
      ),
      decoration: BoxDecoration(
        color: isGallery ? const Color(0xCCFFFFFF) : const Color(0xF2FFFFFF),
        border: const Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            iconUrl: FigmaIconUrls.homeNav,
            label: 'Home',
            selected: currentTab == FigmaNavTab.home,
            onTap: () => onTabSelected(FigmaNavTab.home),
          ),
          _NavItem(
            iconUrl: FigmaIconUrls.galleryNav,
            label: 'Gallery',
            selected: currentTab == FigmaNavTab.gallery,
            onTap: () => onTabSelected(FigmaNavTab.gallery),
          ),
          _CenterCameraItem(
            selected: currentTab == FigmaNavTab.camera,
            onTap: () => onTabSelected(FigmaNavTab.camera),
          ),
          _NavItem(
            iconUrl: FigmaIconUrls.bestNav,
            label: 'Best Cut',
            selected: currentTab == FigmaNavTab.bestCut,
            onTap: () => onTabSelected(FigmaNavTab.bestCut),
          ),
          _NavItem(
            iconUrl: FigmaIconUrls.editorNav,
            label: 'Editor',
            selected: currentTab == FigmaNavTab.editor,
            onTap: () => onTabSelected(FigmaNavTab.editor),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.iconUrl,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String iconUrl;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF333333) : const Color(0xFF94A3B8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SvgIcon(iconUrl, width: 20, height: 20, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterCameraItem extends StatelessWidget {
  const _CenterCameraItem({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Transform.translate(
        offset: const Offset(0, -6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: _SvgIcon(
                      FigmaIconUrls.cameraNav,
                      width: 25,
                      height: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            // const SizedBox(height: 2),
            // Text(
            //   'CAMERA',
            //   style: TextStyle(
            //     fontSize: 10,
            //     color: selected
            //         ? const Color(0xFF333333)
            //         : const Color(0xFF94A3B8),
            //     fontWeight: FontWeight.w500,
            //     letterSpacing: -0.2,
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}

class _SvgIcon extends StatelessWidget {
  const _SvgIcon(this.url, {this.width, this.height, this.color});

  final String url;
  final double? width;
  final double? height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      url,
      width: width,
      height: height,
      fit: BoxFit.contain,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}
