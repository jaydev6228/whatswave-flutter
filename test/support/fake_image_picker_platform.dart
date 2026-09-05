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
    this.singleImagePath = '/fake/test-photo.jpg',
  });

  final List<String> multiImagePaths;
  final String? videoPath;
  int imageFromSourceCallCount = 0;
  int multiImageCallCount = 0;

  /// Backs [ImagePicker.pickImage] (e.g. the profile-photo picker) --
  /// distinct from [multiImagePaths], which backs the multi-select gallery
  /// pick used elsewhere.
  final String? singleImagePath;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    multiImageCallCount++;
    return [for (final path in multiImagePaths) XFile(path)];
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    imageFromSourceCallCount++;
    final path = singleImagePath;
    return path == null ? null : XFile(path);
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
