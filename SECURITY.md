# Security Policy

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Email **jaydevbaloliya@gmail.com** with:

- what the issue is
- how to reproduce it
- what an attacker could achieve

You should get an acknowledgement within a few days. Please give a
reasonable window to address it before disclosing publicly.

## What is and is not protected

WhatsWave encrypts chat **content** end to end using the Signal Protocol
(`libsignal_protocol_dart`). Being precise about the boundary matters more
than the claim:

**Encrypted end to end**
- 1:1 message text, via a pairwise X3DH + Double Ratchet session
- Group message text, via per-member sender keys distributed over those
  pairwise sessions
- Attachment metadata carried with a message: filenames, captions, voice
  note durations, and location coordinates
- Attachment **bytes** in Storage: each file is encrypted with a random
  per-attachment key (AES-256-CTR with an HMAC-SHA256 over the ciphertext)
  before upload, and that key travels only inside the encrypted message
  envelope. The MAC is verified before any plaintext is written, so a
  tampered download never reaches the viewer
- At rest on the device: the Signal session store, the local decrypted
  message store, and the chat inbox cache, all sealed with a key held in
  the iOS Keychain / Android Keystore

**Not encrypted, by design**
- **Metadata.** Who messages whom, when, how often, group membership,
  group names and descriptions, display names, typing indicators, read
  state and reactions are all plaintext in Firestore. A hostile server
  learns the social graph. This is the significant limitation.
- **Status updates and communities.** Story content and community
  announcements are still plaintext.
- **Calls.** LiveKit's transport encryption (DTLS-SRTP) protects the wire,
  but the media server can decrypt. LiveKit supports true end-to-end
  encryption via `E2EEOptions`; this app does not use it yet.
- **Decrypted media on disk.** Opening an encrypted attachment writes a
  decrypted copy to the temp directory so the OS viewer can read it. It is
  deleted on sign-out, but it is plaintext while it exists.

**Key handling**
- Private keys never leave the device. Only public key material
  (`signalIdentities`, `signalPreKeys`) is published.
- The identity key can be backed up under a passphrase (Argon2id, 64 MiB).
  Session state deliberately is not: restoring a stale ratchet desyncs it
  permanently, so a restore rebuilds sessions from scratch.
- Safety numbers are shown on a 1:1 contact's info screen, so two people
  can compare them out of band. A changed identity key changes the number,
  which is what makes a man-in-the-middle or a failed restore detectable
  rather than silent.

**Known gaps worth stating**
- Single device per account. There is no device linking, and a reinstall
  without the passphrase backup means a new identity and a changed safety
  number for every contact.
- No server-side rate limiting, so a client can drain somebody's one-time
  pre-key pool. New sessions then fall back to the signed pre-key --
  degraded, not broken, and self-healing on the next top-up.
- `libsignal_protocol_dart` is a third-party pure-Dart implementation of
  the protocol, not Signal's own audited code. It has not been
  independently reviewed as deployed here.

## Scope

This is a personal project with no production deployment, so there is no
bug bounty and no formal SLA. Reports are still taken seriously —
particularly anything involving credentials, Firebase rules, or data
belonging to one user being reachable by another.

## Out of scope

- Findings that require a rooted/jailbroken device or a physically
  compromised phone
- Issues in third-party dependencies (report those upstream)
- Missing hardening that has no demonstrated impact
