import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Test double for [ImagePickerPlatform.instance]. Widget tests have no
/// real photo library to pick from, so this returns [XFile]s pointing at
/// paths that don't exist on disk -- attachment tiles fall back to their
/// placeholder swatch instead of attempting to decode a real image, same
/// as the app's own "media missing on this device" path.
class FakeImagePickerPlatform extends ImagePickerPlatform {
  FakeImagePickerPlatform({
    this.multiImagePaths = const ['/fake/test-photo.jpg'],
    this.videoPath = '/fake/test-video.mp4',
  });

  final List<String> multiImagePaths;
  final String? videoPath;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    return [for (final path in multiImagePaths) XFile(path)];
  }

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    final path = videoPath;
    return path == null ? null : XFile(path);
  }
}
