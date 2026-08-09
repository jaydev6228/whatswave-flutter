const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {logger} = require("firebase-functions");
const {initializeApp} = require("firebase-admin/app");
const {getStorage} = require("firebase-admin/storage");
const path = require("path");
const os = require("os");
const fs = require("fs/promises");
const ffmpeg = require("fluent-ffmpeg");

ffmpeg.setFfmpegPath(require("@ffmpeg-installer/ffmpeg").path);

initializeApp();

// Matches the two spots the Flutter app uploads real video attachments to:
//   chatMedia/{threadId}/{messageId}-{attachmentId}.{ext}   (FirestoreChatRepository)
//   statusMedia/{uid}/{fileName}                            (FirebaseStatusMediaStore)
const WATCHED_PREFIXES = ["chatMedia/", "statusMedia/"];
const VIDEO_EXTENSIONS = new Set([".mp4", ".mov", ".m4v", ".webm", ".avi"]);
const THUMBNAIL_SUFFIX = "_thumb.jpg";

/**
 * Generates a JPEG thumbnail for every video attachment uploaded to Storage,
 * written to a deterministic sibling path the Flutter client can look up
 * directly (see video_thumbnail_source.dart's resolveVideoThumbnailUrl) --
 * no Firestore write-back needed, so this has zero coupling to which
 * message/story document the video ends up attached to.
 *
 * Exists because no client-side Flutter package for extracting a video
 * frame could be made to compile on both iOS and Android in this project
 * (video_thumbnail's own Android build depends on the long-dead jcenter()
 * Maven repo) -- server-side generation sidesteps that entirely.
 */
exports.generateVideoThumbnail = onObjectFinalized(
  {
    // Must match the Storage bucket's own region (whatswave-dev-jaydev-ebae8
    // is in us-east1) -- a Storage trigger can't listen cross-region.
    region: "us-east1",
    memory: "1GiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    if (!filePath) {
      return;
    }

    if (!WATCHED_PREFIXES.some((prefix) => filePath.startsWith(prefix))) {
      return;
    }
    if (filePath.endsWith(THUMBNAIL_SUFFIX)) {
      // Avoid a self-triggering loop on the thumbnail we just uploaded.
      return;
    }

    const extension = path.extname(filePath).toLowerCase();
    const contentType = object.contentType || "";
    const isVideo =
      contentType.startsWith("video/") || VIDEO_EXTENSIONS.has(extension);
    if (!isVideo) {
      return;
    }

    const bucket = getStorage().bucket(object.bucket);
    const thumbnailPath =
      filePath.slice(0, filePath.length - extension.length) +
      THUMBNAIL_SUFFIX;

    const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "thumb-"));
    const localVideoPath = path.join(workDir, path.basename(filePath));
    const localThumbName = path.basename(thumbnailPath);

    try {
      await bucket.file(filePath).download({destination: localVideoPath});

      await new Promise((resolve, reject) => {
        ffmpeg(localVideoPath)
          .on("end", resolve)
          .on("error", reject)
          // Percentage-based rather than a fixed second, so a clip shorter
          // than a couple of seconds still gets a real mid-video frame
          // instead of ffmpeg clamping to the very end (or failing on a
          // timestamp past the video's duration).
          .screenshots({
            timestamps: ["10%"],
            filename: localThumbName,
            folder: workDir,
            size: "480x?",
          });
      });

      await bucket.upload(path.join(workDir, localThumbName), {
        destination: thumbnailPath,
        metadata: {contentType: "image/jpeg"},
      });

      logger.info(`Generated thumbnail: ${thumbnailPath}`);
    } catch (error) {
      // Best-effort -- a failed thumbnail (corrupt upload, unsupported
      // codec) shouldn't retry forever or alert anyone; the client already
      // falls back to a placeholder tile when no thumbnail is found.
      logger.error(`Thumbnail generation failed for ${filePath}`, error);
    } finally {
      await fs.rm(workDir, {recursive: true, force: true});
    }
  },
);
