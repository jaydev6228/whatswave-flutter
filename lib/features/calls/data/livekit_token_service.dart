import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:http/http.dart' as http;

/// Thrown when a call token could not be obtained.
///
/// Carries the HTTP status code -- never the response body. The body reaches
/// telemetry via `CallsController`'s `recordError`, which forwards
/// `error.toString()` to Crashlytics, so anything the token server echoes
/// back (headers, auth diagnostics, upstream errors) would leave the device.
/// The status code is all the app actually branches on.
class CallTokenException implements Exception {
  const CallTokenException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// The server verifies that the signed-in user is really a party to the
  /// call before minting a `roomJoin` grant (see
  /// server/livekit-token/api/token.js), and answers 403 when they are not.
  bool get isNotAParticipant => statusCode == 403;

  @override
  String toString() => statusCode == null
      ? 'CallTokenException: $message'
      : 'CallTokenException($statusCode): $message';
}

/// Mints the per-user token a client needs to join a call room.
///
/// An interface rather than a bare class so tests can stand one in --
/// `CallsController` otherwise has no way to exercise its own connect path
/// without a live token server. Mirrors `CallSignalingService` /
/// `MediaUploader` elsewhere in this codebase.
abstract class CallTokenService {
  Future<String> fetchToken(String roomName);
}

/// Fetches a real per-user LiveKit access token from the deployed
/// server/livekit-token Vercel function, authenticated with the caller's
/// own Firebase ID token. See server/livekit-token/README.md.
class LiveKitTokenService implements CallTokenService {
  LiveKitTokenService({
    required this.tokenServerUrl,
    fb_auth.FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
  })  : _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _httpClient = httpClient ?? http.Client();

  final String tokenServerUrl;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final http.Client _httpClient;

  @override
  Future<String> fetchToken(String roomName) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const CallTokenException(
        'Must be signed in to fetch a call token.',
      );
    }

    final idToken = await user.getIdToken();
    final response = await _httpClient.post(
      Uri.parse(tokenServerUrl),
      headers: <String, String>{
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, String>{'roomName': roomName}),
    );

    if (response.statusCode != 200) {
      // Status code only -- see CallTokenException's doc comment.
      throw CallTokenException(
        'Token server rejected the request.',
        statusCode: response.statusCode,
      );
    }

    final Object? decoded = jsonDecode(response.body);
    final token = decoded is Map<String, dynamic>
        ? decoded['token'] as String?
        : null;
    if (token == null || token.isEmpty) {
      throw const CallTokenException(
        'Token server response did not include a token.',
      );
    }
    return token;
  }
}
