import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/calls/domain/call_history_entry.dart';
import '../../features/calls/domain/call_permissions.dart';
import '../../features/communities/domain/contact_access_status.dart';

abstract class AppPermissionService {
  Future<ContactAccessStatus> contactAccessStatus();

  Future<ContactAccessStatus> requestContactsAccess();

  Future<CallPermissions> callPermissionsStatus();

  Future<CallPermissions> requestCallPermissions(CallType type);

  Future<void> openSettings();
}

class MemoryAppPermissionService implements AppPermissionService {
  MemoryAppPermissionService({
    ContactAccessStatus contactsStatus = ContactAccessStatus.unknown,
    CallPermissionStatus microphoneStatus = CallPermissionStatus.unknown,
    CallPermissionStatus cameraStatus = CallPermissionStatus.unknown,
    this.grantContactsOnRequest = true,
    this.grantMicrophoneOnRequest = true,
    this.grantCameraOnRequest = true,
  })  : _contactsStatus = contactsStatus,
        _callPermissions = CallPermissions(
          microphone: microphoneStatus,
          camera: cameraStatus,
        );

  ContactAccessStatus _contactsStatus;
  CallPermissions _callPermissions;
  bool grantContactsOnRequest;
  bool grantMicrophoneOnRequest;
  bool grantCameraOnRequest;

  @override
  Future<ContactAccessStatus> contactAccessStatus() async => _contactsStatus;

  @override
  Future<ContactAccessStatus> requestContactsAccess() async {
    _contactsStatus = grantContactsOnRequest
        ? ContactAccessStatus.granted
        : ContactAccessStatus.denied;
    return _contactsStatus;
  }

  @override
  Future<CallPermissions> callPermissionsStatus() async => _callPermissions;

  @override
  Future<CallPermissions> requestCallPermissions(CallType type) async {
    _callPermissions = CallPermissions(
      microphone: grantMicrophoneOnRequest
          ? CallPermissionStatus.granted
          : CallPermissionStatus.denied,
      camera: type == CallType.video
          ? (grantCameraOnRequest
              ? CallPermissionStatus.granted
              : CallPermissionStatus.denied)
          : _callPermissions.camera,
    );
    return _callPermissions;
  }

  @override
  Future<void> openSettings() async {}
}

class NativeAppPermissionService implements AppPermissionService {
  static const _contactsRequestedKey = 'permissions.contacts.requested';
  static const _microphoneRequestedKey = 'permissions.microphone.requested';
  static const _cameraRequestedKey = 'permissions.camera.requested';

  @override
  Future<ContactAccessStatus> contactAccessStatus() async {
    final preferences = await SharedPreferences.getInstance();
    final status = await Permission.contacts.status;
    return _mapContactStatus(
      status,
      hasRequestedBefore: preferences.getBool(_contactsRequestedKey) ?? false,
    );
  }

  @override
  Future<ContactAccessStatus> requestContactsAccess() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_contactsRequestedKey, true);
    final status = await Permission.contacts.request();
    return _mapContactStatus(status, hasRequestedBefore: true);
  }

  @override
  Future<CallPermissions> callPermissionsStatus() async {
    final preferences = await SharedPreferences.getInstance();
    final microphoneStatus = await Permission.microphone.status;
    final cameraStatus = await Permission.camera.status;

    return CallPermissions(
      microphone: _mapCallStatus(
        microphoneStatus,
        hasRequestedBefore:
            preferences.getBool(_microphoneRequestedKey) ?? false,
      ),
      camera: _mapCallStatus(
        cameraStatus,
        hasRequestedBefore: preferences.getBool(_cameraRequestedKey) ?? false,
      ),
    );
  }

  @override
  Future<CallPermissions> requestCallPermissions(CallType type) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_microphoneRequestedKey, true);
    final microphoneStatus = await Permission.microphone.request();

    PermissionStatus cameraStatus = await Permission.camera.status;
    if (type == CallType.video) {
      await preferences.setBool(_cameraRequestedKey, true);
      cameraStatus = await Permission.camera.request();
    }

    return CallPermissions(
      microphone: _mapCallStatus(microphoneStatus, hasRequestedBefore: true),
      camera: _mapCallStatus(
        cameraStatus,
        hasRequestedBefore: type == CallType.video ||
            (preferences.getBool(_cameraRequestedKey) ?? false),
      ),
    );
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }

  ContactAccessStatus _mapContactStatus(
    PermissionStatus status, {
    required bool hasRequestedBefore,
  }) {
    if (status == PermissionStatus.granted) {
      return ContactAccessStatus.granted;
    }
    // iOS's "Select contacts..." limited-access choice (and its older
    // "provisional" cousin) -- distinct from full access on purpose, so the
    // UI can offer a way back to the system picker to add more contacts
    // instead of silently treating a one-contact selection as "done".
    if (status == PermissionStatus.limited ||
        status == PermissionStatus.provisional) {
      return ContactAccessStatus.limited;
    }
    return hasRequestedBefore
        ? ContactAccessStatus.denied
        : ContactAccessStatus.unknown;
  }

  CallPermissionStatus _mapCallStatus(
    PermissionStatus status, {
    required bool hasRequestedBefore,
  }) {
    if (_isGranted(status)) {
      return CallPermissionStatus.granted;
    }
    return hasRequestedBefore
        ? CallPermissionStatus.denied
        : CallPermissionStatus.unknown;
  }

  bool _isGranted(PermissionStatus status) {
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited ||
        status == PermissionStatus.provisional;
  }
}
