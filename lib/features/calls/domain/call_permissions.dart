import 'call_history_entry.dart';

enum CallPermission { microphone, camera }

extension CallPermissionX on CallPermission {
  String get label => switch (this) {
        CallPermission.microphone => 'Microphone',
        CallPermission.camera => 'Camera',
      };
}

enum CallPermissionStatus { unknown, granted, denied }

extension CallPermissionStatusX on CallPermissionStatus {
  String get label => switch (this) {
        CallPermissionStatus.unknown => 'Ask every time',
        CallPermissionStatus.granted => 'Allowed',
        CallPermissionStatus.denied => 'Not now',
      };
}

class CallPermissions {
  const CallPermissions({
    this.microphone = CallPermissionStatus.unknown,
    this.camera = CallPermissionStatus.unknown,
  });

  final CallPermissionStatus microphone;
  final CallPermissionStatus camera;

  CallPermissionStatus statusFor(CallPermission permission) {
    return switch (permission) {
      CallPermission.microphone => microphone,
      CallPermission.camera => camera,
    };
  }

  List<CallPermission> missingFor(CallType type) {
    final permissions = <CallPermission>[CallPermission.microphone];
    if (type == CallType.video) {
      permissions.add(CallPermission.camera);
    }

    return List<CallPermission>.unmodifiable(
      permissions.where((permission) =>
          statusFor(permission) != CallPermissionStatus.granted),
    );
  }

  CallPermissions update(
    List<CallPermission> permissions,
    CallPermissionStatus status,
  ) {
    var updatedMicrophone = microphone;
    var updatedCamera = camera;

    for (final permission in permissions) {
      switch (permission) {
        case CallPermission.microphone:
          updatedMicrophone = status;
        case CallPermission.camera:
          updatedCamera = status;
      }
    }

    return CallPermissions(
      microphone: updatedMicrophone,
      camera: updatedCamera,
    );
  }
}
