# Changelog

## Unreleased

### Added

- `etaf-video-player-doctor` reports ffmpeg, ffprobe and SQLite availability in the
  same shape as `etaf-install-doctor`, so the installer can show what is missing
  before the player opens.

### Fixed

- Declare the `etaf-db` dependency. Playback history requires it, but the header
  omitted it, so `package.el` could install the player without it.

## Unreleased

### Fixed

- The open prompt reads file names the way `find-file` does: a pasted
  absolute or `~` path is accepted instead of being refused with
  "(match required)" because it does not match the current directory's
  completions.

- A source typed as `~/Videos/clip.mp4` or a name relative to the calling
  buffer plays the file instead of falling back to default metadata; the
  player resolves the name before the decoder opens it.

### Added

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
- A playlist sidebar: open several sources as one queue, click an item to
  play it, move with next/previous, and let a finished item advance per the
  loop mode (off, list, one).  Shuffle is a toggle; enqueue and remove edit
  the queue without interrupting the running item.
- A themed application shell with an etaf-ui transport: header status, a
  `etaf-range` progress bar you can click or drag to seek, and buttons for
  play/pause, ±5 s, volume and mute.  The play/pause and sound glyphs follow
  the live state through retained Host updates, so the View is never
  republished for a playback second.
- Subtitles: a local video loads the first readable `.srt` or `.vtt` track
  beside it (including `movie.zh.srt`) and shows one line under the canvas;
  `c` hides, shows or loads a track and `etaf-video-player-subtitle-load`
  attaches one from Lisp.  Malformed cues are skipped and inline markup is
  stripped.
- Resume: local playback positions persist in a small `etaf-db` SQLite
  database (`etaf-video-player-history-file`); reopening continues past five
  seconds unless the record is near the end, and the database fails open so
  playback never depends on it.
- Screenshots: `S` decodes the current frame with ffmpeg into a PNG beside the
  video (or the temporary directory for a stream) in the background.
- `etaf-video-player-state` exposes the live player as plain data for scripts
  and tests.
- Acceptance scenarios over fake ffmpeg, ffprobe and ffplay fixtures plus
  gated real-ffmpeg demo and screenshot scenarios, so the public path stays
  testable without a decoder, network or sound card.

### Changed

- `?`, `C-c h` and the header help button share a searchable, themed modal
  inside the player. Concise labels follow the effective bindings; Escape
  exits one layer at a time, and clicking outside closes help without
  changing playback or splitting the window.

- The three-pane shell was rebuilt around a four-step depth palette: the
  page, panes, header and transport each paint one step, the details pane
  groups facts into 视频信息/播放设置/画布 sections with aligned values, and
  the transport is a full-width timeline with a centred control row.  The
  light appearance no longer paints every surface the same near-white, and
  the stage follows the appearance (near-black dark, shallow grey light)
  while letterbox frames stay black.
- The header reports only the playback status; the frame-rate sample moved out
  of the status line, and the key-hint footer shrank to the common keys.
- Narrow windows use a short hint footer and drop the loop/shuffle buttons
  without changing the underlying keys.
- The player buffer no longer shows a mode line.
- The playlist sidebar draws a count badge instead of a bare number.

### Fixed

- The minibuffer and echo area borrow window lines without refitting the
  canvas: the player keeps the size it committed until the prompt closes.
