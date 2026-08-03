import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Debug-only screen that connects to a LiveKit room using a manually
/// generated test token (see config/README.md -- LIVEKIT_URL /
/// LIVEKIT_TEST_TOKEN) and renders the local camera preview.
///
/// This is deliberately NOT wired into CallsController or the real call
/// flow. It exists purely to prove the livekit_client SDK, camera/mic
/// permissions, and video rendering pipeline actually work in this app
/// before doing the much larger work of replacing CallsController's
/// Timer-based simulation with real LiveKit session state. Production
/// calling needs per-user tokens minted server-side (a Cloud Function,
/// which needs Blaze) -- never a hardcoded test token like this one.
class LiveKitTestScreen extends StatefulWidget {
  const LiveKitTestScreen({super.key});

  @override
  State<LiveKitTestScreen> createState() => _LiveKitTestScreenState();
}

class _LiveKitTestScreenState extends State<LiveKitTestScreen> {
  static const _url = String.fromEnvironment('LIVEKIT_URL');
  static const _token = String.fromEnvironment('LIVEKIT_TEST_TOKEN');

  lk.Room? _room;
  lk.LocalVideoTrack? _localVideoTrack;
  String _status = 'Not connected';
  bool _isConnecting = false;
  String? _errorMessage;
  String? _warningMessage;

  @override
  void dispose() {
    _room?.disconnect();
    _room?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_url.isEmpty || _token.isEmpty) {
      setState(() {
        _errorMessage =
            'LIVEKIT_URL / LIVEKIT_TEST_TOKEN are not set in config/dev.json.';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _warningMessage = null;
      _status = 'Connecting...';
    });

    try {
      final room = lk.Room();
      await room.connect(_url, _token);

      // Camera capture is unavailable on the iOS Simulator (no real
      // AVCaptureDevice), so it's expected to throw there. Caught
      // separately so mic-only + the connection itself can still be
      // verified on Simulator; a real device is required for video.
      lk.LocalTrackPublication? cameraPub;
      String? warning;
      try {
        cameraPub = await room.localParticipant?.setCameraEnabled(true);
      } catch (e) {
        warning = 'Camera unavailable (expected on iOS Simulator): $e';
      }

      await room.localParticipant?.setMicrophoneEnabled(true);

      if (!mounted) {
        return;
      }
      setState(() {
        _room = room;
        _localVideoTrack = cameraPub?.track as lk.LocalVideoTrack?;
        _status = 'Connected to room "${room.name}"';
        _warningMessage = warning;
        _isConnecting = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.toString();
        _status = 'Connection failed';
        _isConnecting = false;
      });
    }
  }

  Future<void> _disconnect() async {
    final room = _room;
    setState(() {
      _room = null;
      _localVideoTrack = null;
      _status = 'Disconnected';
      _warningMessage = null;
    });
    await room?.disconnect();
    await room?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = _localVideoTrack;

    return Scaffold(
      appBar: AppBar(title: const Text('LiveKit test (debug)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_status, style: theme.textTheme.titleMedium),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (_warningMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _warningMessage!,
                  style: TextStyle(color: theme.colorScheme.tertiary),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(
                    key: const Key('livekit_test_connect_button'),
                    onPressed:
                        _isConnecting || _room != null ? null : _connect,
                    child: _isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Connect'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    key: const Key('livekit_test_disconnect_button'),
                    onPressed: _room == null ? null : _disconnect,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: track == null
                    ? const Center(
                        child: Text('No local video track yet.'),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: lk.VideoTrackRenderer(track),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
