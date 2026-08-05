import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as device_contacts;

import '../../../app/theme/app_palette.dart';
import '../domain/community_contact.dart';

/// Reads contacts from the device's address book.
///
/// Kept as a small interface (same pattern as [AppPermissionService] /
/// [StatusMediaStore]) so it can be swapped for a fake in tests without
/// touching the platform contacts plugin.
abstract class DeviceContactsService {
  Future<List<CommunityContact>> fetchDeviceContacts();

  /// Fires whenever the OS reports the device contacts database changed --
  /// notably, on iOS, when the user edits their "Select Contacts..."
  /// limited-access list from Settings while the app is backgrounded.
  /// There's no callback for that from inside the app itself, only this
  /// native change notification (or the app resuming, which
  /// CommunitiesController also listens for as a fallback). Null for
  /// implementations with no real change-notification backing (e.g. the
  /// in-memory fake).
  Stream<void>? watchContactsChanged();
}

class MemoryDeviceContactsService implements DeviceContactsService {
  const MemoryDeviceContactsService(this._contacts);

  final List<CommunityContact> _contacts;

  @override
  Future<List<CommunityContact>> fetchDeviceContacts() async {
    return List<CommunityContact>.unmodifiable(_contacts);
  }

  @override
  Stream<void>? watchContactsChanged() => null;
}

class NativeDeviceContactsService implements DeviceContactsService {
  const NativeDeviceContactsService();

  @override
  Stream<void>? watchContactsChanged() =>
      device_contacts.FlutterContacts.onDatabaseChange;

  @override
  Future<List<CommunityContact>> fetchDeviceContacts() async {
    final rawContacts = await device_contacts.FlutterContacts.getAll(
      properties: const {device_contacts.ContactProperty.phone},
    );

    final result = <CommunityContact>[];
    for (final contact in rawContacts) {
      final id = contact.id;
      final name = contact.displayName?.trim() ?? '';
      final phone =
          contact.phones.isEmpty ? null : contact.phones.first.number.trim();
      if (id == null || name.isEmpty || phone == null || phone.isEmpty) {
        // Skip contacts with no id, no name, or no phone number -- there's
        // nothing to message them with.
        continue;
      }

      result.add(
        CommunityContact(
          id: 'device-$id',
          name: name,
          phoneNumber: phone,
          avatarLabel: _avatarLabelForName(name),
          accentColor: _accentColorForName(name),
          about: 'Hey there! I am using WhatsWave.',
          isOnWhatsWave: false, // Enriched separately via phoneDirectory.
        ),
      );
    }

    result.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return result;
  }

  // Same deterministic derivation used in FakeAuthRepository/
  // FirebaseAuthRepository, so device contacts look visually consistent
  // with everything else in the app.
  String _avatarLabelForName(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'WW';
    }
    if (parts.length == 1) {
      final clean = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return clean.isEmpty
          ? 'WW'
          : clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _accentColorForName(String name) {
    const palette = <Color>[
      AppPalette.emerald,
      AppPalette.green,
      AppPalette.sky,
      AppPalette.purple,
      AppPalette.amber,
    ];
    final hash = name.codeUnits.fold<int>(0, (value, unit) => value + unit);
    return palette[hash % palette.length];
  }
}
