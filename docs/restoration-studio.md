# Desktop Restoration Studio

This feature is an **initial working FFmpeg preprocessing pass**, not an LTX-2.5
integration. It is exposed from the desktop shell and compact UI.

## Requirements and run

Install FFmpeg on the desktop and make sure `ffmpeg` is on PATH. Open
Restoration Studio, provide an existing local video file and a **different**
output `.mp4` path. Select output width, optionally deinterlace, adjust
denoising, and run. Processing is cancellable and displays FFmpeg status.
Original audio streams are copied without re-encoding when compatible with MP4.
Some audio codecs cannot be muxed into MP4; in those cases FFmpeg will fail and
the user must transcode/remux separately. Source video is never overwritten
(the source/output path check is a basic guard and should be hardened with
canonical path checks before exposing processing to untrusted inputs).

The filters are bwdif, hqdn3d, Lanczos scaling, SAR normalization and optional
grayscale preservation. Output is H.264 8-bit SDR at the source frame rate.
This operation does **not** restore ground-truth lost image detail.

## Proposed second stage: local GPU inference, no ComfyUI

* Use a separate local Python/C++ worker with an explicit versioned
  `/health`, `/capabilities`, `/jobs` protocol and per-job process isolation.
* Audit current LTX model licenses, supported conditioning, and checkpoint
  variants rather than assuming a specific LTX-2.5 colorization LoRA, HDR node,
  text encoder or tiled decoder exists.
* Preserve source timestamps and aspect ratio; detect telecine/interlacing,
  chroma noise and scene boundaries before denoising.
* Add prompt timelines with model/provider/version/seed provenance.
  Expose separate **faithful restoration** and **creative reconstruction**
  modes. Colorization always marked inferred, never historically verified.
* Test shot boundary consistency, motion/face drift and flicker against a
  reproducible evaluation set. Keep an untouched comparison preview.
* Add 16-bit linear intermediate handling, color-managed grading, explicit
  Rec.2020/PQ or HLG transfer and mastering metadata only after measurement.
  Expanding SDR into a PQ file cannot recover missing highlight information.
* Use chunked processing with overlapping context, bounded VRAM jobs, progress,
  resumable manifests and GPU capability checks. 20–30 GB VRAM is a planning
  estimate, not a validated requirement for all models.
* Later integrate media library browsing with NoMercy through an explicit
  authorized API client, subject to its API/compatibility and license.
* Later add hosted IRC, watch parties, polls, stats and recommendations, with
  explicit opt-in and no unconsented sharing of chat data.

## Verification still needed

Run `dart format lib/restoration lib/ui/restoration_studio.dart lib/ui/home_screen.dart`,
`flutter analyze`, `flutter test` and a real FFmpeg sample encode on Linux.
No GPU restoration model or IRC/watch-party backend is bundled by this PR.
