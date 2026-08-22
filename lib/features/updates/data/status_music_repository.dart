import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/status_story.dart';

/// The catalog of tracks offered by the "Add music" picker -- separate
/// from [UpdatesRepository] since it's a read-only shared catalog, not
/// per-user story data.
abstract class StatusMusicRepository {
  Future<List<StatusMusicTrack>> fetchTracks();
}

/// A [StatusMusicTrack.previewAssetPath] is a Storage download URL for
/// every catalog track now that music always loads from the server, but a
/// bundled asset path (`assets/...`) can still show up from older
/// already-posted stories or test fixtures -- play either kind from the
/// one call site that needs a controller (the composer's preview player
/// and the story viewer's playback).
VideoPlayerController videoPlayerControllerForAudioPath(String path) {
  final uri = Uri.tryParse(path);
  if (uri != null && (uri.isScheme('HTTP') || uri.isScheme('HTTPS'))) {
    return VideoPlayerController.networkUrl(uri);
  }
  return VideoPlayerController.asset(path);
}

/// Firestore-backed catalog. Tracks are seeded server-side (Storage for the
/// audio files, one `statusMusicTracks/{trackId}` doc per track for
/// metadata) -- never written from the client, see firestore.rules.
class FirestoreStatusMusicRepository implements StatusMusicRepository {
  FirestoreStatusMusicRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<StatusMusicTrack>> fetchTracks() async {
    final snapshot = await _firestore.collection('statusMusicTracks').get();
    final tracks = <StatusMusicTrack>[];
    for (final doc in snapshot.docs) {
      final track = StatusMusicTrack.fromJson(doc.data());
      if (track != null) {
        tracks.add(track);
      }
    }
    return tracks;
  }
}

/// Demo/offline catalog -- same ids/titles/artists as the real Firestore
/// collection (so a picked track behaves identically either way), served
/// instantly with no network round trip. Deliberately has no
/// [StatusMusicTrack.previewAssetPath] -- the real Storage download URLs
/// are per-object bearer tokens (anyone holding one can fetch that file
/// with no auth check at all), so they only ever live in Firestore, never
/// baked into the app's own committed source. Demo/offline mode shows the
/// title, artist, and banner colors; it just can't play a preview.
class FakeStatusMusicRepository implements StatusMusicRepository {
  const FakeStatusMusicRepository();

  @override
  Future<List<StatusMusicTrack>> fetchTracks() async {
    return kFallbackStatusMusicTracks;
  }
}

/// See [FakeStatusMusicRepository]'s doc comment for why these have no
/// preview URL. Shared by that repository and, via
/// [MediaStatusComposerScreen]'s own default, by anything that opens the
/// composer without wiring a real `loadMusicTracks` loader (e.g. a widget
/// test).
const List<StatusMusicTrack> kFallbackStatusMusicTracks = <StatusMusicTrack>[
  StatusMusicTrack(
    id: 'hip-hop-02',
    title: 'Hip Hop 02',
    artist: 'Lily J',
    colorValue: 0xFF25D366,
    secondaryColorValue: 0xFFD9FBE8,
    bannerStyleId: 'cover',
  ),
  StatusMusicTrack(
    id: 'hazy-after-hours',
    title: 'Hazy After Hours',
    artist: 'Alejandro Magaña',
    colorValue: 0xFF58A6FF,
    secondaryColorValue: 0xFFDCEBFF,
    bannerStyleId: 'pulse',
  ),
  StatusMusicTrack(
    id: 'tech-house-vibes',
    title: 'Tech House Vibes',
    artist: 'Alejandro Magaña',
    colorValue: 0xFFFFC857,
    secondaryColorValue: 0xFFFFF1C5,
    bannerStyleId: 'cover',
  ),
  StatusMusicTrack(
    id: 'driving-ambition',
    title: 'Driving Ambition',
    artist: 'Ahjay Stelino',
    colorValue: 0xFF8C6BFF,
    secondaryColorValue: 0xFFE8DFFF,
    bannerStyleId: 'mix',
  ),
  StatusMusicTrack(
    id: 'beautiful-dream',
    title: 'Beautiful Dream',
    artist: 'Diego Nava',
    colorValue: 0xFF667781,
    secondaryColorValue: 0xFFE6EAEE,
    bannerStyleId: 'minimal',
  ),
  StatusMusicTrack(
    id: 'serene-view',
    title: 'Serene View',
    artist: 'Arulo',
    colorValue: 0xFFFF7AB6,
    secondaryColorValue: 0xFFFFDAEB,
    bannerStyleId: 'mix',
  ),
  StatusMusicTrack(
    id: 'valley-sunset',
    title: 'Valley Sunset',
    artist: 'Alejandro Magaña',
    colorValue: 0xFFFD8D4F,
    secondaryColorValue: 0xFFFFE4D0,
    bannerStyleId: 'pulse',
  ),
  StatusMusicTrack(
    id: 'gimme-that-groove',
    title: 'Gimme That Groove!',
    artist: 'Michael Ramir C.',
    colorValue: 0xFF3FC2D6,
    secondaryColorValue: 0xFFD9F7FB,
    bannerStyleId: 'cover',
  ),
  StatusMusicTrack(
    id: 'cat-walk',
    title: 'Cat Walk',
    artist: 'Arulo',
    colorValue: 0xFFF97316,
    secondaryColorValue: 0xFFFFE5D4,
    bannerStyleId: 'minimal',
  ),
  StatusMusicTrack(
    id: 'sports-highlights',
    title: 'Sports Highlights',
    artist: 'Ahjay Stelino',
    colorValue: 0xFF7C8BFF,
    secondaryColorValue: 0xFFE0E4FF,
    bannerStyleId: 'mix',
  ),
  StatusMusicTrack(
    id: 'latin-lovers',
    title: 'Latin Lovers',
    artist: 'Ahjay Stelino',
    colorValue: 0xFFE85D75,
    secondaryColorValue: 0xFFFCE1E6,
    bannerStyleId: 'pulse',
  ),
  StatusMusicTrack(
    id: 'spirit-in-the-woods',
    title: 'Spirit in the Woods',
    artist: 'Alejandro Magaña',
    colorValue: 0xFF4C9A6A,
    secondaryColorValue: 0xFFE1F3E7,
    bannerStyleId: 'cover',
  ),
  StatusMusicTrack(
    id: 'forest-treasure',
    title: 'Forest Treasure',
    artist: 'Alejandro Magaña',
    colorValue: 0xFF2E8B7A,
    secondaryColorValue: 0xFFDDF2EE,
    bannerStyleId: 'minimal',
  ),
  StatusMusicTrack(
    id: 'island-beat',
    title: 'Island Beat',
    artist: 'Arulo',
    colorValue: 0xFFFFB020,
    secondaryColorValue: 0xFFFFEDCC,
    bannerStyleId: 'mix',
  ),
  StatusMusicTrack(
    id: 'relaxing-in-nature',
    title: 'Relaxing in Nature',
    artist: 'Diego Nava',
    colorValue: 0xFF6FCF97,
    secondaryColorValue: 0xFFE3F8EB,
    bannerStyleId: 'pulse',
  ),
];
