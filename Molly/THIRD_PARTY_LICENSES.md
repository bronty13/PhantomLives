# Third-party licenses

## ffmpeg / ffprobe (bundled)

Molly bundles native **ffmpeg** and **ffprobe** binaries to decode and encode
video for the GIF Studio (teaser GIFs, MP4 clips, frame thumbnails). They are
invoked as separate subprocesses — Molly's own source is not linked against
ffmpeg and is unaffected by ffmpeg's license.

These are **GPL** static builds (they include `libx264`, which is GPL-licensed),
so the bundled ffmpeg/ffprobe binaries are covered by the **GNU General Public
License, version 2 or later**.

- **Windows (x86_64):** [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds)
  — `ffmpeg-master-latest-win64-gpl`.
- **macOS (arm64):** [OSXExperts](https://www.osxexperts.net/) — ffmpeg 7.x arm64 GPL build.

Corresponding source for the bundled ffmpeg is available from the upstream
FFmpeg project (<https://ffmpeg.org/download.html>) and from the build providers
linked above. FFmpeg is © the FFmpeg developers; see <https://ffmpeg.org/legal.html>.

The binaries are downloaded and bundled at release time by
`.github/workflows/release-molly.yml`; they are not committed to this repository.
