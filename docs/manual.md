# ETAF Video Player manual

## Playing a video

`etaf-video-player-open-file` plays a local file with sound;
`etaf-video-player-open-url` (`u`) plays an HTTP(S) URL as a stream: ffmpeg
decodes it directly, so nothing is downloaded first.  Seeking needs the server
to support range requests, and a dropped connection is retried for up to five
seconds.  ffmpeg's HTTP reader reads the lowercase `http_proxy` environment
variable when a proxy is needed.  `etaf-video-player-demo` plays a generated
30 second test pattern and needs no file.  All three create one buffer named
`*Video Player*` and reuse it: opening another source closes the previous
player first.  `etaf-video-player-close` (also `q`) cancels the status timer,
destroys the native session and its audio sidecar, and unmounts the ETAF
Runtime.

The player buffer hides its cursor, so no cursor frame flashes around the
picture.

The window is a themed shell: a header with the live playback status, the
video canvas fitted to the window and kept at its original aspect ratio, a
progress bar you can click or drag to seek, and a transport row with
play/pause, ±5 s, volume and mute controls.  The play/pause and sound glyphs
change with the state, and the progress bar moves through retained geometry
instead of republishing the View.

Playback starts immediately. `SPC` pauses and resumes, `n` pauses and presents
exactly one more frame, `f` and `b` seek five seconds, and `+`/`-` step through
0.5x, 1x, 2x, 4x and 8x. Pausing releases the producer and the audio sidecar,
and resuming starts a new producer at the pause position, so a long pause
never makes playback jump forward to catch up. Seeking and rate changes
restart the producer at the current position too, so they are safe while
paused. When the file ends the last picture stays visible and the status line
shows `ended`; `SPC` replays from the start.

The producer's own frame rate may be lower or higher than
`etaf-video-display-fps` (30 by default). Display always claims only the newest
complete frame, so a slower display drops frames instead of replaying a
backlog; the status line's `dropped` counter reports how many. The rate shown
in the status line is the number of frames presented in the last sample
window, not the timer rate, so a canvas too large for the display cost reports
a lower number instead of a hopeful one.

## Image frames

Decoding, scaling and publication belong to the native `etaf-video` Component,
which this application places in a layout with `:mode 'image`; see the ETAF
manual for the full contract.  On a graphical frame ffmpeg emits one JPEG per
frame at the canvas pixel size and the Component publishes it as an image
display on a single character cell, so frame cost does not grow with the
number of cells and a full-window canvas stays smooth.  On a terminal the
Component falls back to a density-ramp canvas (`etaf-video-player-state`
reports `:render-mode 'ascii`), so the same command still works over SSH.

Retina screens stay sharp because the producer decodes at the display's device
pixel ratio: the canvas is `columns` by `rows` character cells, and the frames
are produced at `columns * char-width * ratio` by `rows * char-height * ratio`
pixels and drawn back down at `1 / ratio`.  `frame-scale-factor` supplies the
ratio (2 on Retina); set `etaf-video-player-device-pixel-ratio` to 1 to force
logical-pixel frames (softer, cheaper), or to a fixed number for testing.
Changing the variable applies to the next session restart (a resize, mode or
source change).  This is the only mode this application uses; the density ramp
and true-color half blocks belong to the companion `etaf-ascii-video` player.

Character cells are about twice as tall as wide, so the default fitting keeps
the video aspect ratio by sampling `rows * aspect * 2` columns. The built-in
demo is 640x360; a file's real size comes from ffprobe, and the source
defaults are 640x360 when ffprobe is unavailable.

## Sound

An ffplay sidecar plays the source's audio track.  It starts with playback,
restarts at the current position when the volume changes, is released on
pause, and follows `a` and the volume keys:

| Key | Action |
| --- | --- |
| `[` / `]` | lower or raise the volume by 10 |
| `a` | toggle sound |

`etaf-video-player-volume` (default 100) and `etaf-video-player-audio`
(default t) set the initial state for new players; `:volume` and `:audio` in a
source plist override them for one session.  A source that reports no audio
stream stays silent, and so does a missing ffplay — the status line's `mute`
or `sound` word reports the requested state.  ffplay is part of the normal
ffmpeg installation; `etaf-video-ffplay-program` points at another one.

## Keys

| Key | Action |
| --- | --- |
| `SPC` | play or pause |
| `n` | one frame while paused |
| `f`, `b` | +5 s / -5 s |
| `+`, `-` | next / previous rate |
| `[`, `]` | volume down / up |
| `a` | toggle sound |
| `1` .. `4` | 64, 96, 128, 176 columns |
| `F` | fit to the window |
| `o`, `u`, `d` | open a file / open a URL / demo |
| `?`, `q` | help / close |

`F` and `etaf-video-player-fit` reserve one row for the status line and refit
the ETAF viewport before changing the grid. The same fitting runs
automatically through `window-size-change-functions` when the window changes
size, so a resized frame keeps a canvas that fits.

## Scripting

`etaf-video-player-open` accepts a file name or a plist, so a session can be
built without prompts:

```elisp
(etaf-video-player-open '(:file "clip.mp4" :columns 100 :rows 28 :volume 60))
(etaf-video-player-seek 12.5)
(etaf-video-player-set-speed 0.5)
(etaf-video-player-set-audio nil)
(etaf-video-player-set-volume 0)
(etaf-video-player-state)
;; => (:source "clip.mp4" :playing t :position 12.5 :duration 300.0 ...)
```

Every control function operates on the current buffer's player and signals
`user-error` elsewhere, so scripts should call them from the player buffer or
from an interactive command bound there. `etaf-video-player-state` returns a
detached plist; the interesting keys are `:playing`, `:position`, `:duration`,
`:render-mode`, `:source-width`, `:source-height`, `:received`, `:presented`,
`:dropped`, `:audio`, `:volume` and `:ended`.

| Variable | Meaning |
| --- | --- |
| `etaf-video-player-audio` | play sound for new players, default t |
| `etaf-video-player-volume` | initial volume for new players, 0 to 100 |
| `etaf-video-player-device-pixel-ratio` | image device pixel ratio; nil derives it from the frame |
| `etaf-video-player-grid-presets` | character to canvas width, used by `1`-`4` |
| `etaf-video-display-fps` | display timer rate, default 30 (ETAF) |
| `etaf-video-ffmpeg-program` | ffmpeg name or path; use a wrapper to add decoder options (ETAF) |
| `etaf-video-ffprobe-program` | ffprobe name or path; optional (ETAF) |
| `etaf-video-ffplay-program` | ffplay name or path used for sound (ETAF) |

The native Component passes ffmpeg the documented argument shape
`-hide_banner -loglevel error [-ss START] -readrate SPEED -i INPUT -vf
scale=PIXEL-WIDTH:PIXEL-HEIGHT:flags=lanczos -q:v 3 -f image2pipe -c:v mjpeg -`,
with `-f lavfi -i testsrc2=size=640x360:rate=30 -t 30` for the demo instead of
`-i INPUT`. A wrapper set through `etaf-video-ffmpeg-program` receives these
arguments unchanged. The audio sidecar receives
`-nodisp -autoexit -loglevel error -volume VOLUME [-ss POSITION] TARGET`.

## Troubleshooting

- `ffmpeg is not available`: install ffmpeg or set
  `etaf-video-ffmpeg-program` to its absolute path.
- No sound: install ffplay or set `etaf-video-ffplay-program`; check the
  volume keys and that the source has an audio stream.  The status line shows
  `sound` or `mute` for the requested state.
- `Video file is not readable`: the path is wrong or the file is not a local
  readable file; use `etaf-video-player-open-url` for network streams.
- A URL does not play: check the network and, behind a proxy, `ffmpeg`'s
  lowercase `http_proxy` / `https_proxy` environment variables. Non-HTTP(S)
  schemes are rejected before any process starts.
- No total duration in the status line: ffprobe is missing or the container
  does not report one; playback still works.
- The picture looks squashed: the canvas no longer matches the video aspect
  ratio. Press `F` or call `etaf-video-player-fit`.
- The picture is soft on a Retina screen: check
  `etaf-video-player-device-pixel-ratio` (nil means automatic) and remember
  that the change applies on the next session restart.
- The picture lags after resizing or switching monitors: the grid refits
  automatically, and a session restart is part of that change.
