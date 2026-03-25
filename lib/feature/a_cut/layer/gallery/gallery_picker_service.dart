import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

class GalleryPickerService {
  const GalleryPickerService();

  Future<PermissionState> requestPermission() {
    return PhotoManager.requestPermissionExtend();
  }

  Future<List<AssetPathEntity>> loadAlbums() {
    final filterOption = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );

    return PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: filterOption,
    );
  }

  Future<List<AssetEntity>> loadPhotos({
    required AssetPathEntity album,
    int maxCount = 200,
  }) async {
    final totalCount = await album.assetCountAsync;
    final end = totalCount > maxCount ? maxCount : totalCount;

    if (end <= 0) {
      return const [];
    }

    return album.getAssetListRange(start: 0, end: end);
  }

  Future<Uint8List?> loadThumbnail(AssetEntity asset) {
    return asset.thumbnailDataWithSize(const ThumbnailSize(500, 500));
  }

  Future<void> openSystemSettings() {
    return PhotoManager.openSetting();
  }
}
