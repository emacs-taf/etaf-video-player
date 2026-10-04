# Changelog

## Unreleased

### Added

- A themed application shell with an etaf-ui transport: header status, a
  `etaf-range` progress bar you can click or drag to seek, and buttons for
  play/pause, ±5 s, volume and mute.  The play/pause and sound glyphs follow
  the live state through retained Host updates, so the View is never
  republished for a playback second.

- Video playback in an ETAF buffer as sharp image frames with sound, built on
  the framework's native `etaf-video` Component: ffmpeg decodes at the
  display's device pixel ratio, an ffplay sidecar plays the source's audio, and
  every frame is one incremental publication of a fixed canvas Host.
- Local files, HTTP(S) streams and a generated built-in demo; play/pause,
  single-frame stepping, seeking, 0.5x to 8x rates, volume keys, a sound
  toggle, four grid presets and window fitting.
- Retina-sharp frames by default (`etaf-video-player-device-pixel-ratio` can
  force logical pixels) and an automatic density-ramp fallback when the frame
  cannot show images.
- `etaf-video-player-state` exposes the live player as plain data for scripts
  and tests.
- Acceptance scenarios over fake ffmpeg, ffprobe and ffplay fixtures plus one
  gated real-ffmpeg demo scenario, so the public path stays testable without a
  decoder, network or sound card.
