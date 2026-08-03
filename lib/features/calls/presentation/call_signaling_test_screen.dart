import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/firestore_call_signaling_service.dart';
import '../domain/call_history_entry.dart';
import '../domain/call_signal.dart';

/// Debug-only screen for testing Calls Slice B2 (Firestore call signaling)
/// in isolation, before it's wired into CallsController. Lets you place a
/// call to any uid (including your own, for a same-device smoke test) and
/// watch both the outgoing call's status and any incoming call addressed
/// to you. No LiveKit/media involved -- this only proves the signaling
/// plumbing (create/read/update a `calls` doc, security rules) works.
class CallSignalingTestScreen extends StatefulWidget {
  const CallSignalingTestScreen({super.key});

  @override
  State<CallSignalingTestScreen> createState() =>
      _CallSignalingTestScreenState();
}

class _CallSignalingTestScreenState extends State<CallSignalingTestScreen> {
  final _service = FirestoreCallSignalingService();
  final _calleeUidController = TextEditingController();

  StreamSubscription<CallSignal?>? _incomingSubscription;
  StreamSubscription<CallSignal?>? _outgoingSubscription;
  CallSignal? _incomingCall;
  CallSignal? _outgoingCall;
  String? _errorMessage;
  bool _isPlacingCall = false;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final uid = _myUid;
    if (uid != null) {
      _incomingSubscription = _service.watchIncomingCall(uid).listen(
        (signal) => setState(() => _incomingCall = signal),
        onError: (Object error) =>
            setState(() => _errorMessage = 'Incoming-call watch failed: $error'),
      );
    }
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _outgoingSubscription?.cancel();
    _calleeUidController.dispose();
    super.dispose();
  }

  Future<void> _placeCall() async {
    final calleeUid = _calleeUidController.text.trim();
    if (calleeUid.isEmpty) {
      setState(() => _errorMessage = 'Enter a callee uid first.');
      return;
    }

    setState(() {
      _isPlacingCall = true;
      _errorMessage = null;
    });

    try {
      final signal = await _service.placeCall(
        calleeUid: calleeUid,
        type: CallType.video,
      );
      _outgoingSubscription?.cancel();
      _outgoingSubscription = _service.watchCall(signal.id).listen(
        (updated) => setState(() => _outgoingCall = updated),
      );
      setState(() {
        _outgoingCall = signal;
        _isPlacingCall = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'placeCall failed: $error';
        _isPlacingCall = false;
      });
    }
  }

  Future<void> _updateOutgoingStatus(CallSignalStatus status) async {
    final call = _outgoingCall;
    if (call == null) {
      return;
    }
    await _service.updateStatus(call.id, status);
  }

  Future<void> _updateIncomingStatus(CallSignalStatus status) async {
    final call = _incomingCall;
    if (call == null) {
      return;
    }
    await _service.updateStatus(call.id, status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = _myUid;

    return Scaffold(
      appBar: AppBar(title: const Text('Call signaling test (debug)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Your uid', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    uid ?? 'Not signed in',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (uid != null)
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: uid)),
                  ),
              ],
            ),
            const Divider(height: 32),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
            ],
            Text('Place a call', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              key: const Key('call_signaling_callee_uid_field'),
              controller: _calleeUidController,
              decoration: const InputDecoration(
                labelText: 'Callee uid',
                hintText: 'Paste a uid (yours, or a second account\'s)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('call_signaling_place_call_button'),
              onPressed: _isPlacingCall ? null : _placeCall,
              child: _isPlacingCall
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Place call'),
            ),
            if (_outgoingCall != null) ...[
              const SizedBox(height: 12),
              _CallSignalCard(
                title: 'Outgoing call',
                signal: _outgoingCall!,
                actions: [
                  OutlinedButton(
                    onPressed: () =>
                        _updateOutgoingStatus(CallSignalStatus.ended),
                    child: const Text('End'),
                  ),
                ],
              ),
            ],
            const Divider(height: 32),
            Text('Incoming call', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_incomingCall == null)
              Text(
                'No incoming call.',
                style: theme.textTheme.bodyMedium,
              )
            else
              _CallSignalCard(
                title: 'Incoming',
                signal: _incomingCall!,
                actions: [
                  FilledButton(
                    onPressed: () =>
                        _updateIncomingStatus(CallSignalStatus.accepted),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () =>
                        _updateIncomingStatus(CallSignalStatus.declined),
                    child: const Text('Decline'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CallSignalCard extends StatelessWidget {
  const _CallSignalCard({
    required this.title,
    required this.signal,
    required this.actions,
  });

  final String title;
  final CallSignal signal;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('Call id: ${signal.id}'),
            Text('Caller: ${signal.callerUid}'),
            Text('Callee: ${signal.calleeUid}'),
            Text('Status: ${signal.status.name}'),
            const SizedBox(height: 12),
            Row(children: actions),
          ],
        ),
      ),
    );
  }
}
