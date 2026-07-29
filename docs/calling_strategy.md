# Calling strategy

## Goal

Support both simulated calls in early phases and real production calling later without rewriting the screens.

## App-side layers

### Call presentation

- Call history page
- Incoming call sheet
- Active audio call screen
- Active video call screen
- Permission prompts and failure states

### Call application

- Start outgoing call
- Accept call
- Decline call
- End call
- Track duration and call state
- Write call history

### Call services

- `CallSignalingService`
- `CallMediaService`
- `CallPermissionsService`
- `CallDeviceService`

## Suggested roadmap

### Slice 1

- Simulated audio call
- Simulated video call
- Call history
- Permission guidance UI

### Slice 2

- Local camera and microphone permissions
- State machine for ringing, connecting, connected, ended, failed
- Better active call layout

### Slice 3

- Real signaling service
- Real media service
- Push invite handling
- Platform integrations

## Provider options

### Provider-backed

- LiveKit
- Stream
- Twilio

### Self-managed

- WebRTC-based media stack
- Your own signaling service
- TURN/STUN infrastructure

## Platform responsibilities

### iOS

- CallKit adapter
- PushKit / VoIP notification handling
- Audio session handling

### Android

- Telecom or self-managed calling integration
- Foreground service and notification policy
- Audio routing management

## Non-negotiables

- Screen code should never know which provider is used
- Call state should be serializable for restore/debug logging
- Failures must map to user-facing states
- Missed, rejected, failed, and completed calls all need history records
