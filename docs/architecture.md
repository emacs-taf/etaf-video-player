# ETAF Video Player architecture

## Responsibilities

`etaf-video-player` is an application. It owns the buffer, the fitted canvas
size, the audio state and volume, the status line and the keys. Decoding,
Retina-sharp image frames, the audio sidecar and publication belong to ETAF's
native `etaf-video` Component, which this application places in a View and
drives through its public handle control functions. No framework mechanism is
re-implemented here.

| Module | Owns |
| --- | --- |
| `etaf-video-player-app` | player state (canvas, rate, audio, volume, status), the View, the buffer, the keymap, window fitting and the public commands |

The root entry re-exports the supported subset; everything unlisted is
internal.

## Data flow

1. `etaf-video-player-open` normalizes and probes the source once through
   `etaf-video-source-info`, fits a canvas to the selected window and mounts a
   View with the native `etaf-video` Component (`:mode 'image`) plus a status
   text Host.
2. The Component owns the playback session: ffmpeg decodes at the device pixel
   size, the session keeps only the newest complete frame, and each displayed
   frame is published through `etaf-runtime-update-host-content` as one image
   cell.  The optional ffplay sidecar follows the same play/pause state.
3. The application refreshes the status Host from `etaf-video-state` four
   times per second, so the frame path stays free of status work.
4. Controls are declarative or imperative depending on the fact: canvas size,
   rate, audio and volume are View props (changing a prop restarts or retunes
   the session at the current position), while play/pause, step and seek call
   the Component's handle functions.
5. `etaf-video-player-close` cancels the status timer and unmounts the Runtime,
   which destroys the session and its sidecar. A failed open runs the same
   teardown, so no partial player survives a `user-error`.

## Invariants

- **One owner per fact.** The native session owns decoding, position, pacing
  and audio; the application owns canvas size, rate, volume and status text;
  ETAF owns publication. The View never decodes and commands never write
  buffer text directly.
- **Retina is a producer fact.** The session decodes at
  `columns * char-width * ratio` by `rows * char-height * ratio` device pixels
  and the image is drawn at `1 / ratio`, so the window system never upscales
  the picture.  `etaf-video-player-device-pixel-ratio` overrides the frame's
  `frame-scale-factor`, and the change applies on the next session restart.
- **Probe once.** `etaf-video-source-info` returns authoritative metadata that
  the Component accepts as its source, so resizing or restarting a video does
  not repeat the ffprobe call.
- **Latest frame wins.** The session retains at most one complete frame; a slow
  display drops frames and the clock advances from delivered frames, so
  playback never replays a backlog.
- **Pause does not catch up.** Pausing releases the producer and the audio
  sidecar and remembers the position; resuming spawns a producer with `-ss
  POSITION` instead of continuing a wall-clock-paced one, so a long pause never
  produces a fast-forward burst.
- **Cleanup is unconditional.** Every open failure, close and buffer kill
  cancels the status timer and unmounts the Runtime, destroying the session,
  the producer and the audio sidecar with it.

## Measured behavior

The player's frame cost is the native Component's cost.  Image frames publish
one image cell per frame, so publication does not grow with the number of
cells.  On the reference machine (M-series Mac, 150x44 full-window canvas,
1080p source, foreground playback) a 68 s clip runs with Emacs at about 55-60%
of one core and ffmpeg at 45-70% in 2x image mode, and with Emacs unchanged
and ffmpeg at 16-33% in 1x image mode: at real speed the per-frame retained
publication and redisplay are the bottleneck, not the decoded resolution, and
a smaller decoded pixel size relieves only ffmpeg.  The Component flushes the
previous frame after publishing a new one and on teardown, because Emacs
caches images by spec; a 40 s 1080p session plateaus at about 700 MB of RSS
instead of growing linearly.

Falling back to the density ramp is the expensive mode.  A full-window mono
canvas runs Emacs at about 82-96% of one core, and CPU profiling attributes
about 31% of that to `ebox--flex-item-slot-footprint-safe-p` calling
`ebox--string-pixel-width` to re-measure the whole screen's text on every
frame.  The first knobs are `etaf-video-display-fps` (30 to 24 or 15) and the
canvas size; lowering the device pixel ratio only relieves ffmpeg.

The status line refreshes four times per second from plain state and adds no
work to the frame path.
