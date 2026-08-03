import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:http/http.dart' as http;

/// Fetches a real per-user LiveKit access token from the deployed
/// server/livekit-token Vercel function, authenticated with the caller's
/// own Firebase ID token. See server/livekit-token/README.md.
class LiveKitTokenService {
  LiveKitTokenService({
    required this.tokenServerUrl,
    fb_auth.FirebaseAuth? firebaseAuth,
    http.Client? httpClient,
  })  : _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _httpClient = httpClient ?? http.Client();

  final String tokenServerUrl;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final http.Client _httpClient;

  Future<String> fetchToken(String roomName) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('Must be signed in to fetch a LiveKit token.');
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
      throw StateError(
        'Token server returned ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null) {
      throw StateError('Token server response missing "token" field.');
    }
    return token;
  }
}
