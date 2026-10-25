import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A directory inside the app's **real** application-support directory,
/// emptied first so the flow starts from a fresh-install state.
///
/// Real on purpose: the whole reason these flows exist is that they run
/// against the real sqflite plugin and the real sandbox, neither of which a
/// widget test touches (`test/flutter_test_config.dart` stubs both out).
///
/// Registers its own teardown, so a failed flow does not leak state into the
/// next one.
Future<String> freshInstallDirectory(String name) async {
  final root = p.join((await getApplicationSupportDirectory()).path, name);
  final directory = Directory(root);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  await directory.create(recursive: true);
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return root;
}

/// Every byte this directory holds, for asserting that something is *not*
/// stored in the clear. Concatenated rather than read file by file because
/// sqflite may still have the row in a `-wal` sidecar.
Future<String> allBytesAsText(String directory) async {
  final buffer = StringBuffer();
  for (final entity in Directory(directory).listSync(recursive: true)) {
    if (entity is File) {
      buffer.write(String.fromCharCodes(entity.readAsBytesSync()));
    }
  }
  return buffer.toString();
}
