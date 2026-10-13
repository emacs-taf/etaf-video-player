;;; etaf-video-player-app.el --- Buffers, keys and commands for etaf-video-player -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; The application face of the player: the mountable View over the native
;; `etaf-video' Component and the status Host, the buffer keymap, window
;; fitting and the public commands listed in the root entry.  Decoding,
;; Retina-sharp image frames, the audio sidecar and publication belong to
;; ETAF; this module keeps the canvas size, playback rate, volume, the status
;; line and the user's keys.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-video-player-theme)
(require 'etaf-video-player-views)
(require 'etaf-video-player-subtitle)
(require 'etaf-video-player-history)

(defconst etaf-video-player--buffer-name "*Video Player*"
  "Name of the single application buffer.")

(defconst etaf-video-player--hud-ref 'etaf-video-player-hud
  "Retained Host reference of the status line.")

(defconst etaf-video-player--time-ref 'etaf-video-player-time
  "Retained Host reference of the elapsed playback clock.")

(defconst etaf-video-player--duration-ref 'etaf-video-player-duration
  "Retained Host reference of the total playback clock.")

(defconst etaf-video-player--volume-ref 'etaf-video-player-volume-text
  "Retained Host reference of the volume percentage.")

(defconst etaf-video-player--progress-fill-ref 'etaf-video-player-progress-fill
  "Retained Host reference of the progress bar fill.")

(defconst etaf-video-player--subtitle-ref 'etaf-video-player-subtitle
  "Retained Host reference of the subtitle line under the canvas.")

(defconst etaf-video-player--hint-line
  (concat "SPC 播放/暂停 · f/b ±5s · <> 上/下条 · +/- 速度 · [ ] 音量"
          " · o 打开 · T 主题 · ? 全部键位 · q 关闭")
  "One-line key hint shown in the footer.")

(defconst etaf-video-player--hint-line-compact
  "SPC 播放 · f/b ±5s · +/- 速度 · ? 键位 · q 关闭"
  "Short footer hint used when the window hides the playlist column.")

(defconst etaf-video-player--hud-interval 0.25
  "Seconds between status line refreshes.")

(defconst etaf-video-player--stage-top-fallback 1
  "Canvas row used before the stage Host has been measured.
It clears the header row because the layout constants put the body right
under the one-row header; without it an unmeasured canvas paints inside the
header in batch and headless runs.")

(defconst etaf-video-player--speeds '(0.5 1 2 4 8)
  "Playback rates offered by the speed commands.")

(defconst etaf-video-player--resume-min-seconds 5
  "Saved positions at or below this many seconds restart from zero.")

(defconst etaf-video-player--resume-end-margin 10
  "Saved positions within this many seconds of the end restart from zero.")

(defconst etaf-video-player--history-interval 5
  "Seconds between playback-position writes while playing.")

(defconst etaf-video-player--volume-step 10
  "Volume change applied by the volume keys.")

(defvar etaf-video-player-grid-presets
  '((?1 . 64) (?2 . 96) (?3 . 128) (?4 . 176))
  "Grid width presets reached by the `1' to `4' keys.
Keys are characters, values are canvas widths in character cells; the row
count follows the video aspect.")

(defvar etaf-video-player-audio t
  "Whether new players play their source's audio track.
A sound card and ffplay are required; sources without an audio stream stay
silent and the status line reports `sound' only while a sidecar runs.")

(defvar etaf-video-player-volume 100
  "Initial audio volume for new players, from 0 to 100.")

(defcustom etaf-video-player-display-fps 24
  "Maximum presentation rate for a new player, in frames per second.
The producer keeps real-time playback; when presentation cannot keep up,
the newest decoded frame wins instead of accumulating a backlog."
  :type '(integer :tag "Frames per second")
  :group 'etaf-video-player)

(defvar etaf-video-player-device-pixel-ratio nil
  "Device pixels per logical pixel for image frames.
Nil derives the ratio from `frame-scale-factor' (2 on Retina), so frames are
produced at device resolution instead of being upscaled and blurred; 1 forces
logical-pixel frames.  The change applies to the next session restart.")

(defvar etaf-video-player-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") #'etaf-video-player-toggle-playback)
    (define-key map (kbd "n") #'etaf-video-player-step)
    (define-key map (kbd "f") #'etaf-video-player--forward-command)
    (define-key map (kbd "b") #'etaf-video-player--backward-command)
    (define-key map (kbd "+") #'etaf-video-player--speed-up-command)
    (define-key map (kbd "-") #'etaf-video-player--speed-down-command)
    (define-key map (kbd "[") #'etaf-video-player--volume-down-command)
    (define-key map (kbd "]") #'etaf-video-player--volume-up-command)
    (define-key map (kbd "a") #'etaf-video-player--toggle-audio-command)
    (define-key map (kbd "1") #'etaf-video-player--preset-command)
    (define-key map (kbd "2") #'etaf-video-player--preset-command)
    (define-key map (kbd "3") #'etaf-video-player--preset-command)
    (define-key map (kbd "4") #'etaf-video-player--preset-command)
    (define-key map (kbd ">") #'etaf-video-player-next)
    (define-key map (kbd "<") #'etaf-video-player-previous)
    (define-key map (kbd "L") #'etaf-video-player-toggle-loop)
    (define-key map (kbd "s") #'etaf-video-player-toggle-shuffle)
    (define-key map (kbd "F") #'etaf-video-player-fit)
    (define-key map (kbd "T") #'etaf-video-player--toggle-theme)
    (define-key map (kbd "o") #'etaf-video-player-open-file)
    (define-key map (kbd "u") #'etaf-video-player-open-url)
    (define-key map (kbd "c") #'etaf-video-player--subtitle-toggle-command)
    (define-key map (kbd "S") #'etaf-video-player-save-screenshot)
    (define-key map (kbd "d") #'etaf-video-player-demo)
    (define-key map (kbd "C-c h") #'etaf-video-player--help-command)
    (define-key map (kbd "q") #'etaf-video-player-close)
    map)
  "Keymap of a buffer opened by `etaf-video-player-open'.")

(defvar etaf-video-player--command-maps
  (list
   (cons 'etaf-video-player--player
         (let ((map (make-sparse-keymap)))
           ;; The renderer's minor-mode map owns these keys and wins over a
           ;; major-mode map; an `emulation-mode-map-alists' entry wins over
           ;; every minor mode, so the application replaces them here.
           (set-keymap-parent map etaf-video-player-mode-map)
           (define-key map (kbd "SPC") #'etaf-video-player-toggle-playback)
           (define-key map (kbd "n") #'etaf-video-player-step)
           (define-key map (kbd "f") #'etaf-video-player--forward-command)
           (define-key map (kbd "b") #'etaf-video-player--backward-command)
           (define-key map (kbd "+") #'etaf-video-player--speed-up-command)
           (define-key map (kbd "-") #'etaf-video-player--speed-down-command)
           (define-key map (kbd "[") #'etaf-video-player--volume-down-command)
           (define-key map (kbd "]") #'etaf-video-player--volume-up-command)
           (define-key map (kbd "a") #'etaf-video-player--toggle-audio-command)
           (define-key map (kbd "1") #'etaf-video-player--preset-command)
           (define-key map (kbd "2") #'etaf-video-player--preset-command)
           (define-key map (kbd "3") #'etaf-video-player--preset-command)
           (define-key map (kbd "4") #'etaf-video-player--preset-command)
           (define-key map (kbd ">") #'etaf-video-player-next)
           (define-key map (kbd "<") #'etaf-video-player-previous)
           (define-key map (kbd "L") #'etaf-video-player-toggle-loop)
           (define-key map (kbd "s") #'etaf-video-player-toggle-shuffle)
           (define-key map (kbd "F") #'etaf-video-player-fit)
           (define-key map (kbd "T") #'etaf-video-player--toggle-theme)
           (define-key map (kbd "o") #'etaf-video-player-open-file)
           (define-key map (kbd "u") #'etaf-video-player-open-url)
           (define-key map (kbd "c") #'etaf-video-player--subtitle-toggle-command)
           (define-key map (kbd "S") #'etaf-video-player-save-screenshot)
           (define-key map (kbd "d") #'etaf-video-player-demo)
           (define-key map (kbd "C-c h") #'etaf-video-player--help-command)
           (define-key map (kbd "q") #'etaf-video-player-close)
           map)))
  "Application bindings that must beat the renderer's own minor-mode map.
The alist's key is `etaf-video-player--player', the buffer-local variable
every application buffer owns, so the entry is active exactly there.")

(defvar-local etaf-video-player--player nil
  "Player owned by the current application buffer.")

(defvar etaf-video-player--size-hook-installed nil
  "Whether the window size hook was installed.")

(cl-defstruct (etaf-video-player--player (:constructor etaf-video-player--player--make))
  "Application state for one video player buffer.
Playback lives in the native `etaf-video' session addressed by HANDLE; this
record owns the playlist, the current item, the canvas size, the playback
rate, the audio state and the status line."
  buffer spec handle queue index loop shuffle
  columns rows speed audio volume window-rows
  subtitle subtitle-file subtitle-on
  history-at
  spec-ref columns-ref rows-ref speed-ref audio-ref volume-ref
  queue-ref index-ref loop-ref shuffle-ref theme-ref layout-ref
  playing playing-ref progress-ref hud-text clock-text duration-text
  volume-text hud-timer sample sample-fps ended-seen explicit-grid stage-ref)

(defun etaf-video-player--current ()
  "Return the current buffer's player, or signal `user-error'."
  (or etaf-video-player--player
      (user-error "Not an etaf-video-player buffer")))

(defun etaf-video-player--clock (seconds)
  "Format SECONDS as a playback clock, or `--:--' when it is nil."
  (if (numberp seconds)
      (let* ((whole (max 0 (floor seconds)))
             (hours (/ whole 3600))
             (minutes (/ (% whole 3600) 60))
             (rest (% whole 60)))
        (if (> hours 0)
            (format "%d:%02d:%02d" hours minutes rest)
          (format "%02d:%02d" minutes rest)))
    "--:--"))

(defun etaf-video-player--aspect (spec)
  "Return SPEC's video aspect ratio as a float."
  (let ((width (plist-get spec :width))
        (height (plist-get spec :height)))
    (if (and (numberp width) (numberp height) (> width 0) (> height 0))
        (/ (float width) height)
      (/ 16.0 9))))

(defconst etaf-video-player--initial-columns 16
  "Canvas width used until the first stage measurement completes.")
(defconst etaf-video-player--initial-rows 9
  "Canvas height used until the first stage measurement completes.")

(defun etaf-video-player--grid-for-stage (player size)
  "Return the (COLUMNS . ROWS) canvas that fits PLAYER's measured stage SIZE.
SIZE is the stage Host's committed (PIXELS . ROWS), so the application
converts the renderer's own geometry to character cells instead of deriving
layout from window character columns.  The canvas keeps the source aspect."
  (when-let* ((width (car-safe size))
              (height-rows (cdr-safe size))
              (buffer (etaf-video-player--player-buffer player))
              (window (and (buffer-live-p buffer) (get-buffer-window buffer t)))
              (frame (and window (window-frame window))))
    (let* ((aspect (etaf-video-player--aspect (etaf-video-player--player-spec player)))
           (cell-width (max 1 (frame-char-width frame)))
           (cell-height (max 1 (frame-char-height frame)))
           (available-width (float (max 1 width)))
           (available-height (float (max 1 (* height-rows cell-height))))
           (fit-height (min available-height (/ available-width aspect)))
           (fit-width (* fit-height aspect))
           (columns (max 1 (floor fit-width cell-width)))
           (rows (max 1 (floor fit-height cell-height))))
      (cons (min columns (max 1 (floor available-width cell-width)))
            (min rows (max 1 height-rows))))))

(defun etaf-video-player--stage-facts (player runtime)
  "Return PLAYER's stage geometry as a plist, or nil before it is painted.
The plist carries the stage Host's committed `:width' in pixels, `:rows', and
its `:left' pixel and `:top' row origin in the window.  These are renderer
facts: the application never derives them from window character columns."
  (when-let* ((size (etaf-host-ref-size runtime etaf-video-player--stage-ref))
              (buffer (etaf-video-player--player-buffer player))
              (window (and (buffer-live-p buffer) (get-buffer-window buffer t)))
              (bounds (etaf-host-ref-bounds runtime etaf-video-player--stage-ref))
              (posn (and bounds (posn-at-point (car bounds) window))))
    (let* ((origin (posn-x-y posn))
           (cell-height (max 1 (frame-char-height (window-frame window)))))
      (list :width (car size) :rows (cdr size)
            :left (car origin) :top (floor (cdr origin) cell-height)))))

(defun etaf-video-player--sync-layout (player)
  "Publish PLAYER's framework viewport and fit its canvas to the stage.
The viewport is the renderer's own display-safe size, so the responsive
panes and the canvas follow the framework's layout instead of a second,
application-owned geometry.  An explicitly requested grid keeps its size but
still centers inside the measured stage."
  (when-let* ((buffer (etaf-video-player--player-buffer player))
              (runtime (and (buffer-live-p buffer)
                            (etaf-runtime-for-buffer buffer)))
              (mounted (and runtime (etaf-runtime-mounted-p runtime))))
    (let ((viewport (etaf-runtime-viewport runtime)))
      (unless (equal viewport
                     (etaf-value (etaf-video-player--player-layout-ref player)))
        (etaf-set-value (etaf-video-player--player-layout-ref player) viewport)
        (etaf-runtime-flush runtime)))
    (when-let* ((facts (etaf-video-player--stage-facts player runtime))
                (window (get-buffer-window buffer t))
                (frame (window-frame window)))
      (let* ((grid (if (etaf-video-player--player-explicit-grid player)
                       (cons (etaf-video-player--player-columns player)
                             (etaf-video-player--player-rows player))
                     (etaf-video-player--grid-for-stage
                      player (cons (plist-get facts :width)
                                   (plist-get facts :rows))))))
        (when grid
          ;; The canvas is one root-level absolute plane, so its offset is a
          ;; window-pixel pair; both terms are measured, never estimated from
          ;; window character counts.
          (let* ((cell-width (max 1 (frame-char-width frame)))
                 (left (+ (plist-get facts :left)
                          (max 0 (floor (- (plist-get facts :width)
                                           (* (car grid) cell-width))
                                        2))))
                 (top (+ (plist-get facts :top)
                         (max 0 (/ (- (plist-get facts :rows) (cdr grid)) 2)))))
            (unless (equal (cons left top)
                           (etaf-value (etaf-video-player--player-stage-ref player)))
              (etaf-set-value (etaf-video-player--player-stage-ref player)
                              (cons left top))))
          (unless (etaf-video-player--player-explicit-grid player)
            (etaf-video-player--player-set-grid player (car grid) (cdr grid))))))
    t))

(defun etaf-video-player--rows-for-columns (aspect columns)
  "Return the row count of an ASPECT frame COLUMNS cells wide."
  (let ((scale (* aspect (/ (float (frame-char-height (selected-frame)))
                            (max 1 (frame-char-width (selected-frame)))))))
    (max 3 (round (/ columns scale)))))

(defun etaf-video-player--state (player)
  "Return PLAYER's native video state as a detached plist."
  (etaf-video-state (etaf-video-player--player-handle player)))

(defun etaf-video-player--sampled-fps (player state)
  "Update PLAYER's presented frame rate sample from STATE and return it."
  (let* ((now (float-time))
         (presented (plist-get state :presented))
         (sample (etaf-video-player--player-sample player))
         (fps (or (etaf-video-player--player-sample-fps player) 0.0)))
    (when (or (null sample) (>= (- now (car sample)) 0.5))
      (when sample
        (setq fps (/ (float (- presented (cdr sample)))
                     (max 0.001 (- now (car sample))))))
      (setf (etaf-video-player--player-sample player) (cons now presented)
            (etaf-video-player--player-sample-fps player) fps))
    fps))

(defun etaf-video-player--hud (state)
  "Return the one-line playback status for STATE.
The clocks live in the transport bar, so the header reports the state
alone instead of repeating the timeline."
  (cond ((plist-get state :ended) "已结束")
        ((plist-get state :playing) "播放中")
        (t "已暂停")))

(defun etaf-video-player--player-render (player)
  "Publish PLAYER's transport and status text from the live video state.
One batched retained update refreshes the clock, the play/pause glyph, the
volume and sound labels; the progress fill moves through its retained
geometry, so the View is never republished for a playback second."
  (let* ((state (etaf-video-player--state player))
         (runtime (etaf-runtime-for-buffer
                   (etaf-video-player--player-buffer player)))
         (playing (and (plist-get state :playing) t))
         (duration (plist-get (etaf-video-player--player-spec player) :duration)))
    ;; Keep the frame-rate sample fresh for `etaf-video-player-state' even
    ;; though the header no longer displays it.
    (etaf-video-player--sampled-fps player state)
    ;; Persist the playback position on a slow cadence while playing.
    (when (plist-get state :playing)
      (etaf-video-player--player-record-position player state))
    ;; The play/pause control is a reactive toggle: writing its source
    ;; repaints one icon through the retained update path instead of
    ;; publishing the View.
    (unless (eq playing (etaf-video-player--player-playing player))
      (setf (etaf-video-player--player-playing player) playing)
      (etaf-set-value (etaf-video-player--player-playing-ref player) playing))
    (when runtime
      (etaf-video-player--publish-status player runtime state duration))
    ;; Advance once when the item ends; the flag clears as soon as a new
    ;; item is not ended, so a manual replay rearms it.
    (if (plist-get state :ended)
        (unless (etaf-video-player--player-ended-seen player)
          (setf (etaf-video-player--player-ended-seen player) t)
          (when (buffer-live-p (etaf-video-player--player-buffer player))
            (etaf-video-player--player-advance player)))
      (setf (etaf-video-player--player-ended-seen player) nil))))

(defun etaf-video-player--subtitle-display-text (player position)
  "Return the subtitle line PLAYER shows at POSITION, possibly empty."
  (let ((cues (etaf-video-player--player-subtitle player)))
    (if (and cues (etaf-video-player--player-subtitle-on player))
        (or (etaf-video-player-subtitle-text-at cues position) "")
      "")))

(defun etaf-video-player--player-set-subtitle (player cues file)
  "Install CUES from FILE into PLAYER; both nil clears the track.
A non-nil CUES starts shown; the transport repaints on the next tick."
  (setf (etaf-video-player--player-subtitle player) cues
        (etaf-video-player--player-subtitle-file player) file
        (etaf-video-player--player-subtitle-on player) (and cues t)))

(defun etaf-video-player--player-adopt-subtitle (player spec)
  "Load the subtitle file beside SPEC into PLAYER when one exists.
A broken track only leaves the player without subtitles; it never breaks
playback."
  (let* ((file (and (eq (plist-get spec :kind) 'file)
                    (etaf-video-player-subtitle-beside (plist-get spec :file))))
         (cues (and file (ignore-errors (etaf-video-player-subtitle-parse file)))))
    (etaf-video-player--player-set-subtitle player cues file)))

(defun etaf-video-player--player-source-file (player)
  "Return the local file PLAYER is watching, or nil."
  (let ((spec (etaf-video-player--player-spec player)))
    (and (eq (plist-get spec :kind) 'file) (plist-get spec :file))))

(defun etaf-video-player--player-record-position (player state &optional force)
  "Save PLAYER's playback position from STATE.
Writes are throttled to `etaf-video-player--history-interval' unless FORCE
is non-nil (queue switches and closing).  Only local files carry history."
  (when-let* ((file (etaf-video-player--player-source-file player)))
    (let ((now (float-time))
          (position (or (plist-get state :position) 0)))
      (when (and (numberp position)
                 (> position 0)
                 (or force
                     (>= (- now (or (etaf-video-player--player-history-at player) 0))
                         etaf-video-player--history-interval)))
        (setf (etaf-video-player--player-history-at player) now)
        (etaf-video-player-history-record file position (plist-get state :duration))))))

(defun etaf-video-player--player-resume (player)
  "Continue PLAYER from its saved position when the record is useful.
Positions near the start or the end restart from zero, so a finished video
plays again instead of ending immediately."
  (when-let* ((file (etaf-video-player--player-source-file player))
              (record (etaf-video-player-history-position file))
              (position (car record))
              ((numberp position))
              ((> position etaf-video-player--resume-min-seconds)))
    (let* ((spec (etaf-video-player--player-spec player))
           (duration (or (plist-get spec :duration) (cdr record))))
      (when (or (not (numberp duration))
                (<= duration 0)
                (< position (- duration etaf-video-player--resume-end-margin)))
        (etaf-video-seek (etaf-video-player--player-handle player) position)
        (message "从 %s 继续播放" (etaf-video-player--clock position))))))

(defun etaf-video-player--publish-status (player runtime state duration)
  "Publish PLAYER's status Hosts through the retained content boundary.
The texts live in plain fields and reach their Hosts in one explicit retained
content update.  Writing a reactive source here would re-render the
consuming Component and republish the tree on every playback second; the
progress fill stays a controlled value because the range moves it through
its own retained geometry binding."
  (let* ((position (or (plist-get state :position) 0))
         (hud (etaf-video-player--hud state))
         (clock-text (etaf-video-player--clock position))
         (duration-text (etaf-video-player--clock
                         (or (plist-get state :duration) duration)))
         (volume-text (format "%d%%" (etaf-video-player--player-volume player)))
         (subtitle-text (etaf-video-player--subtitle-display-text player position)))
    (setf (etaf-video-player--player-hud-text player) hud
          (etaf-video-player--player-clock-text player) clock-text
          (etaf-video-player--player-duration-text player) duration-text
          (etaf-video-player--player-volume-text player) volume-text)
    (when (and runtime (etaf-runtime-mounted-p runtime))
      (etaf-runtime-update-host-contents
       runtime
       (list (cons etaf-video-player--hud-ref hud)
             (cons etaf-video-player--time-ref clock-text)
             (cons etaf-video-player--duration-ref duration-text)
             (cons etaf-video-player--volume-ref volume-text)
             (cons etaf-video-player--subtitle-ref subtitle-text))))
    (etaf-set-value (etaf-video-player--player-progress-ref player)
                    (if (and (numberp duration) (> duration 0))
                        (max 0.0 (min 100.0 (* 100.0 (/ (float position) duration))))
                      0.0))))

(defun etaf-video-player--player-tick (player)
  "Refresh PLAYER's status line while its buffer is alive."
  (when (buffer-live-p (etaf-video-player--player-buffer player))
    (condition-case problem
        (etaf-video-player--player-render player)
      ((error quit)
       (when-let* ((timer (etaf-video-player--player-hud-timer player)))
         (cancel-timer timer)
         (setf (etaf-video-player--player-hud-timer player) nil))
       (message "etaf-video-player: %s" (error-message-string problem))))))

(cl-defun etaf-video-player--player-create
    (buffer queue &key speed audio volume columns rows index loop shuffle)
  "Create a player for BUFFER showing QUEUE.
QUEUE is a nonempty list of normalized source plists; INDEX selects the
starting item.  SPEED, AUDIO, VOLUME, COLUMNS, ROWS, LOOP and SHUFFLE
initialize the playback state."
  (let ((player (etaf-video-player--player--make
                 :buffer buffer
                 :queue queue :index (or index 0)
                 :spec (nth (or index 0) queue)
                 :loop (or loop 'none) :shuffle (and shuffle t)
                 :handle (make-symbol "etaf-video-player")
                 :columns columns :rows rows :speed speed
                 :audio (and audio t) :volume volume
                 :hud-text "已暂停"
                 :clock-text "00:00"
                 :duration-text "--:--"
                 :volume-text (format "%d%%" volume)))
        (playing-ref (etaf-ref nil))
        (theme-ref (etaf-ref (etaf-video-player-theme-defaults))))
    (setf (etaf-video-player--player-playing-ref player) playing-ref
          (etaf-video-player--player-theme-ref player) theme-ref
          (etaf-video-player--player-layout-ref player)
          (etaf-ref nil :test #'equal)
          (etaf-video-player--player-stage-ref player) (etaf-ref nil :test #'equal)
          (etaf-video-player--player-progress-ref player) (etaf-ref 0))
    (setf (etaf-video-player--player-spec-ref player)
          (etaf-ref (etaf-video-player--player-spec player))
          (etaf-video-player--player-columns-ref player) (etaf-ref columns)
          (etaf-video-player--player-rows-ref player) (etaf-ref rows)
          (etaf-video-player--player-speed-ref player) (etaf-ref speed)
          (etaf-video-player--player-audio-ref player) (etaf-ref (and audio t))
          (etaf-video-player--player-volume-ref player) (etaf-ref volume)
          (etaf-video-player--player-queue-ref player) (etaf-ref queue)
          (etaf-video-player--player-index-ref player) (etaf-ref (or index 0))
          (etaf-video-player--player-loop-ref player) (etaf-ref (or loop 'none))
          (etaf-video-player--player-shuffle-ref player) (etaf-ref (and shuffle t)))
    player))

(defun etaf-video-player--title (spec)
  "Return a short display title for normalized source SPEC."
  (pcase (plist-get spec :kind)
    ('file (file-name-nondirectory (or (plist-get spec :file) "")))
    ('url (or (plist-get spec :url) "stream"))
    (_ "内建演示")))

(defun etaf-video-player--player-select (player index &optional play)
  "Show QUEUE item INDEX in PLAYER, starting from the beginning.
An ordinary publication applies the new source, canvas size and index; the
native Component then rebuilds its session at position zero.  PLAY non-nil
starts the new item playing; otherwise it stays paused."
  (let* ((queue (etaf-video-player--player-queue player))
         (count (length queue))
         (index (max 0 (min (1- count) index)))
         (spec (nth index queue)))
    ;; Save where the outgoing item stopped before its session is replaced.
    (ignore-errors
      (etaf-video-player--player-record-position
       player (etaf-video-player--state player) t))
    (setf (etaf-video-player--player-index player) index
          (etaf-video-player--player-spec player) spec
          (etaf-video-player--player-ended-seen player) nil)
    (etaf-video-player--player-adopt-subtitle player spec)
    (etaf-batch
      (etaf-set-value (etaf-video-player--player-spec-ref player) spec)
      (etaf-set-value (etaf-video-player--player-index-ref player) index))
    ;; The source publication rebuilt the session synchronously; a requested
    ;; play now acts on the new item.
    (when play
      (ignore-errors (etaf-video-play (etaf-video-player--player-handle player))))
    ;; A different source has its own aspect ratio, so re-fit the canvas to
    ;; the measured stage unless the caller fixed the grid.
    (etaf-video-player--sync-layout player)
    (etaf-video-player--player-resume player)
    (etaf-video-player--player-render player)
    index))

(defun etaf-video-player--player-advance (player)
  "Advance PLAYER after its current item ended, honoring LOOP and SHUFFLE.
`none' stops at the last item, `one' repeats it and `all' wraps around."
  (let* ((count (length (etaf-video-player--player-queue player)))
         (index (etaf-video-player--player-index player))
         (loop (etaf-video-player--player-loop player)))
    (pcase loop
      ('one (etaf-video-player--player-select player index t))
      ((or 'all 'none)
       (let ((next (if (etaf-video-player--player-shuffle player)
                       (etaf-video-player--player-random-index player)
                     (1+ index))))
         (cond ((< next count)
                (etaf-video-player--player-select player next t))
               ((eq loop 'all)
                (etaf-video-player--player-select player 0 t))
               (t nil)))))))

(defun etaf-video-player--player-random-index (player)
  "Return a random queue index in PLAYER other than the current one."
  (let* ((queue (etaf-video-player--player-queue player))
         (count (length queue))
         (current (etaf-video-player--player-index player)))
    (if (<= count 1)
        0
      (let ((index (random count)))
        (while (= index current)
          (setq index (random count)))
        index))))

(defun etaf-video-player--source-label (spec)
  "Return SPEC's one-line origin label for the playlist and the details."
  (pcase (plist-get spec :kind)
    ('file
     (let ((directory (file-name-directory (or (plist-get spec :file) ""))))
       (if (or (null directory) (string-empty-p directory))
           "本地文件"
         (abbreviate-file-name (directory-file-name directory)))))
    ('url (or (plist-get spec :url) "网络流"))
    (_ "内建演示")))

(defun etaf-video-player--playlist-entries (player start count)
  "Return COUNT playlist entries of PLAYER from START as (POSITION . PLIST).
Each plist carries the display strings the playlist row needs, so the View
stays a pure function of its props."
  (cl-loop for position from start
           for item in (seq-drop (etaf-video-player--player-queue player) start)
           repeat count
           collect (cons position
                         (list :title (etaf-video-player--title item)
                               :subtitle (etaf-video-player--source-label item)
                               :duration (etaf-video-player--clock
                                          (plist-get item :duration))))))

(defun etaf-video-player--details-facts (spec index count)
  "Return the video information rows for SPEC at INDEX of COUNT."
  (let ((width (plist-get spec :width))
        (height (plist-get spec :height)))
    (list (cons "分辨率" (if (and width height)
                          (format "%s × %s" width height)
                        "未知"))
          (cons "时长" (etaf-video-player--clock (plist-get spec :duration)))
          (cons "播放位置" (format "%d / %d" (1+ index) count)))))

(defun etaf-video-player--details-playback (speed loop shuffle audio volume)
  "Return the playback-setting rows from the shared playback sources."
  (list (cons "速度" (format "%gx" (etaf-video-player--view-value speed)))
        (cons "循环" (pcase (etaf-video-player--view-value loop)
                       ('all "列表") ('one "单集") (_ "关闭")))
        (cons "随机" (if (etaf-video-player--view-value shuffle) "开" "关"))
        (cons "声音" (if (etaf-video-player--view-value audio) "开" "关"))
        (cons "音量" (format "%d%%" (etaf-video-player--view-value volume)))))

(defun etaf-video-player--details-canvas (columns rows ratio)
  "Return the canvas rows for COLUMNS by ROWS at device RATIO."
  (list (cons "尺寸" (format "%d × %d" columns rows))
        (cons "倍率" (if (numberp ratio)
                         (format "%gx" ratio)
                       "自动"))
        (cons "帧率上限" (format "%d fps" etaf-video-player-display-fps))))

(defun etaf-video-player--player-seek-relative (player delta)
  "Move PLAYER DELTA seconds from its current position and repaint."
  (let ((position (or (plist-get (etaf-video-player--state player) :position) 0))
        (duration (plist-get (etaf-video-player--player-spec player) :duration)))
    (etaf-video-seek (etaf-video-player--player-handle player)
                     (max 0 (min (or duration (+ position delta))
                                 (+ position delta))))
    (etaf-video-player--player-render player)))

(defun etaf-video-player--player-seek-percent (player percent)
  "Seek PLAYER to PERCENT of its duration and repaint the clock."
  (let ((duration (plist-get (etaf-video-player--player-spec player) :duration)))
    (when (and (numberp duration) (> duration 0))
      (etaf-video-seek (etaf-video-player--player-handle player)
                       (* duration (/ (float percent) 100)))
      (etaf-video-player--player-render player))))

(etaf-define-component etaf-video-player--shell (&key player)
  "Render the player shell for PLAYER with the application theme.
The shell is a fixed plane: a header row, a body that holds the playlist, the
stage and the details aside, a six-row transport bar and a hint footer.  The
window width decides which panes exist (the playlist from 100 columns, the
details from 150), and the canvas budget uses the same constants, so no pane
can push the bar off the window.  Playback values travel through retained
Host updates: the status line, the clock, the volume label, the progress fill
and the play/pause icon repaint without a View rebuild."
  :bindings ((theme (etaf-video-player--player-theme-ref player)))
  :setup
  (etaf-theme-provide theme)
  :render
  (let* ((_palette (etaf-value theme))
         (spec (etaf-value (etaf-video-player--player-spec-ref player)))
         (queue (etaf-value (etaf-video-player--player-queue-ref player)))
         (index (etaf-value (etaf-video-player--player-index-ref player)))
         (speed (etaf-video-player--player-speed-ref player))
         (loop (etaf-video-player--player-loop-ref player))
         (shuffle (etaf-video-player--player-shuffle-ref player))
         (volume (etaf-video-player--player-volume-ref player))
         (audio (etaf-video-player--player-audio-ref player))
         (columns (etaf-value (etaf-video-player--player-columns-ref player)))
         (canvas-rows (etaf-value (etaf-video-player--player-rows-ref player)))
         (handle (etaf-video-player--player-handle player))
         (layout (etaf-value (etaf-video-player--player-layout-ref player)))
         (stage-facts (etaf-value (etaf-video-player--player-stage-ref player)))
         (stage-left-px (or (car-safe stage-facts) 0))
         (stage-top-rows (or (cdr-safe stage-facts)
                             etaf-video-player--stage-top-fallback))
         (viewport-width (or (car-safe layout) 0))
         (viewport-rows (or (cdr-safe layout) 0))
         (sidebar (>= viewport-width etaf-video-player--sidebar-min-pixels))
         (details (>= viewport-width etaf-video-player--aside-min-pixels))
         (body-rows (max 1 (- viewport-rows etaf-video-player--chrome-rows)))
         (capacity (max 0 (/ (max 0 (- body-rows 5)) 2)))
         (visible (min capacity (length queue)))
         (start (if (<= visible 0)
                    0
                  (max 0 (min (- (length queue) visible) (- index (/ visible 2))))))
         (duration (plist-get spec :duration))
         (ratio (or etaf-video-player-device-pixel-ratio
                    (ignore-errors (frame-scale-factor))))
         (facts (etaf-video-player--details-facts spec index (length queue)))
         (playback (etaf-video-player--details-playback speed loop shuffle audio volume))
         (canvas-facts (etaf-video-player--details-canvas columns canvas-rows ratio))
         ;; One layer per region, so a frame repaints only the canvas plane
         ;; without re-composing surrounding flow content.  Lanes are 30ch playlist, 1ch gutter, stage, 1ch gutter,
         ;; 28ch details; every length is a design constant or the published
         ;; viewport, never a window character count.
         (stage-left-ch (if sidebar 31 1))
         (stage-right-ch (if details 29 1))
         (stage-left (list 'ch stage-left-ch))
         (stage-width (list 'calc (list '- (list 'px viewport-width)
                                        (list 'ch (+ stage-left-ch stage-right-ch)))))
         (details-left (list 'calc (list '- (list 'px viewport-width) (list 'ch 29))))
         (transport-top (+ 1 body-rows))
         (footer-top (+ transport-top etaf-video-player--bar-rows))
         ;; The subtitle line sits right under the picture; when the canvas
         ;; reaches the last body row it takes that row instead of leaving
         ;; the body.
         (subtitle-top (min (+ stage-top-rows canvas-rows 1) body-rows)))
    (etaf-view
     (box :position 'relative
           :on-direction #'etaf-video-player--direction
           :width (list 'px viewport-width)
           :height (list 'lh viewport-rows)
           :background-color (etaf-video-player-color :bg)
           :color (etaf-video-player-color :ink)
           :overflow 'hidden
       (etaf-video-player--view-header
        :position 'absolute :left '(px 0) :top '(lh 0)
        :width (list 'px viewport-width) :height '(lh 1)
        :title (etaf-video-player--title spec)
        :status-ref etaf-video-player--hud-ref
        :status (etaf-video-player--player-hud-text player)
        :on-toggle-theme (lambda () (etaf-video-player--toggle-theme))
        :on-help (lambda () (call-interactively #'etaf-help)))
       (etaf-video-player--view-playlist
        :if sidebar :position 'absolute :left '(ch 0) :top '(lh 1)
        :width '(ch 30) :height (list 'lh body-rows)
        :count (length queue)
        :entries (etaf-video-player--playlist-entries player start visible)
        :active index
        :summary (if (> (length queue) visible)
                     (format "%d–%d / %d" (1+ start) (+ start visible)
                             (length queue))
                   (format "%d 个视频" (length queue)))
        :on-press (lambda (position) (etaf-video-player-play-index position)))
       (box :position 'absolute :left stage-left :top '(lh 1)
            :width stage-width :height (list 'lh body-rows)
            :overflow 'hidden :background-color (etaf-video-player-color :stage)
            :ref etaf-video-player--stage-ref
            :id (symbol-name etaf-video-player--stage-ref))
       (etaf-video-player--view-details
        :if details :position 'absolute :left details-left :top '(lh 1)
        :width '(ch 28) :height (list 'lh body-rows)
        :title (etaf-video-player--title spec)
        :source (etaf-video-player--source-label spec)
        :facts facts :playback playback :canvas canvas-facts
        :on-toggle-theme (lambda () (etaf-video-player--toggle-theme)))
       ;; The canvas is a layer of its own; its offset is the measured stage
       ;; fact, not a chrome estimate.
       (etaf-video :position 'absolute
                   :left (list 'px stage-left-px)
                   :top (list 'lh stage-top-rows)
                   :src (etaf-value (etaf-video-player--player-spec-ref player))
                   :mode 'image
                   :columns columns
                   :rows canvas-rows
                   :speed speed
                   :audio audio
                   :volume volume
                   :device-pixel-ratio etaf-video-player-device-pixel-ratio
                   :display-fps etaf-video-player-display-fps
                   :autoplay t
                   :handle handle
                   :on-press (lambda () (etaf-video-toggle-playback handle)))
       (box :position 'absolute :left stage-left :top (list 'lh subtitle-top)
            :width stage-width :height '(lh 1)
            :overflow 'hidden :text-align 'center
            :color (etaf-video-player-color :ink)
         (text :ref etaf-video-player--subtitle-ref
               :id (symbol-name etaf-video-player--subtitle-ref) ""))
       (etaf-video-player--view-transport
        :position 'absolute :left '(px 0) :top (list 'lh transport-top)
        :width (list 'px viewport-width) :height (list 'lh etaf-video-player--bar-rows)
        :progress (etaf-video-player--player-progress-ref player)
        :playing-ref (etaf-video-player--player-playing-ref player)
        :time (etaf-video-player--player-clock-text player)
        :duration (or (etaf-video-player--player-duration-text player)
                      (etaf-video-player--clock duration))
        :time-ref etaf-video-player--time-ref
        :duration-ref etaf-video-player--duration-ref
        :volume-ref etaf-video-player--volume-ref
        :volume-text (etaf-video-player--player-volume-text player)
        :audio-ref (etaf-video-player--player-audio-ref player)
        :progress-fill-ref etaf-video-player--progress-fill-ref
        :speed speed
        :loop loop
        :shuffle shuffle
        :volume volume
        :on-toggle (lambda () (etaf-video-player-toggle-playback))
        :on-previous (lambda () (etaf-video-player-previous))
        :on-next (lambda () (etaf-video-player-next))
        :on-forward (lambda () (etaf-video-player--player-seek-relative player 5))
        :on-backward (lambda () (etaf-video-player--player-seek-relative player -5))
        :on-cycle-speed (lambda () (etaf-video-player-cycle-speed))
        :on-toggle-loop (lambda () (etaf-video-player-toggle-loop))
        :on-toggle-shuffle (lambda () (etaf-video-player-toggle-shuffle))
        :on-toggle-audio (lambda ()
                           (etaf-video-player-set-audio
                            (not (etaf-video-player--player-audio player))))
        :on-volume (lambda (percent) (etaf-video-player-set-volume percent))
        :on-seek (lambda (percent) (etaf-video-player--player-seek-percent player percent))
        :compact (not sidebar))
       (etaf-video-player--view-footer
        :position 'absolute :left '(px 0) :top (list 'lh footer-top)
        :width (list 'px viewport-width) :height '(lh 1)
        :hints (if sidebar etaf-video-player--hint-line
                 etaf-video-player--hint-line-compact))))))

(defun etaf-video-player--view (player)
  "Return the mountable View of PLAYER."
  (etaf-view (etaf-video-player--shell :player player)))

(defun etaf-video-player--show (buffer)
  "Show BUFFER in the selected window before mounting its View.
The native video Component measures its image canvas from the displayed
Host, so the buffer must already be on screen when the first session is
built; otherwise image frames are sized from font metrics and may exceed the
canvas."
  (let ((display-buffer-overriding-action '((display-buffer-same-window))))
    (pop-to-buffer buffer))
  (when-let* ((shown (get-buffer-window buffer t)))
    (set-window-hscroll shown 0))
  buffer)

(defun etaf-video-player--window-size-changed (frame)
  "Refit every video player shown on FRAME after a window resize.
Lines borrowed by the minibuffer keep the canvas the player committed."
  (dolist (window (window-list frame))
    (with-current-buffer (window-buffer window)
      (when etaf-video-player--player
        (unless (etaf-transient-space-borrowed-p
                 window (etaf-video-player--player-window-rows
                         etaf-video-player--player))
          (etaf-video-player--refit etaf-video-player--player window))))))

(defun etaf-video-player--refit (player window)
  "Refit PLAYER to WINDOW through the framework, then sync canvas and panes.
The renderer republishes the viewport; the application only reads the new
published size and measures the stage Host again."
  (setf (etaf-video-player--player-window-rows player) (window-body-height window))
  (when-let* ((buffer (etaf-video-player--player-buffer player))
              (runtime (and (buffer-live-p buffer)
                            (etaf-runtime-for-buffer buffer))))
    (etaf-refit runtime window)
    (etaf-video-player--sync-layout player)))

(defun etaf-video-player--player-set-grid (player columns rows &optional explicit)
  "Resize PLAYER's canvas to COLUMNS by ROWS and restart the producer.
EXPLICIT records a caller-fixed grid, which later layout syncs keep."
  (unless (and (integerp columns) (> columns 0) (integerp rows) (> rows 0))
    (user-error "Canvas size must be positive integers: %S by %S" columns rows))
  (when explicit
    (setf (etaf-video-player--player-explicit-grid player) t))
  (unless (and (= columns (etaf-video-player--player-columns player))
               (= rows (etaf-video-player--player-rows player)))
    (setf (etaf-video-player--player-columns player) columns
          (etaf-video-player--player-rows player) rows)
    (etaf-batch
      (etaf-set-value (etaf-video-player--player-columns-ref player) columns)
      (etaf-set-value (etaf-video-player--player-rows-ref player) rows))))

(defun etaf-video-player--player-set-speed (player speed)
  "Set PLAYER's rate to SPEED, a positive number."
  (unless (and (numberp speed) (> speed 0))
    (user-error "Playback speed must be a positive number: %S" speed))
  (setf (etaf-video-player--player-speed player) speed)
  (etaf-set-value (etaf-video-player--player-speed-ref player) speed))

(defun etaf-video-player--player-set-volume (player volume)
  "Set PLAYER's volume source, shared by the video and the controlled range.
The shell never reads this source; only the Component prop and range fill
update, so changing volume cannot republish the shell."
  (unless (and (numberp volume) (<= 0 volume 100))
    (user-error "Audio volume must be between 0 and 100: %S" volume))
  (setf (etaf-video-player--player-volume player) volume)
  (etaf-set-value (etaf-video-player--player-volume-ref player) volume)
  volume)

(defun etaf-video-player--player-set-audio (player audio)
  "Set PLAYER's shared sound source without republishing the shell."
  (setf (etaf-video-player--player-audio player) (and audio t))
  (etaf-set-value (etaf-video-player--player-audio-ref player) (and audio t))
  (and audio t))

(defun etaf-video-player--remap-canvas-face ()
  "Paint this buffer's unpainted cells with the application surface color.
Ebox paints whole character cells, so a window body that is not a whole
number of cells keeps a sub-cell remainder at its right or bottom edge.
Remapping the default face shows the application surface there instead of
the frame's."
  (face-remap-set-base 'default (list :background (etaf-video-player-color :surface))))

(defvar etaf-video-player--frame-background nil
  "Saved (FRAME . BACKGROUND) while a player paints the frame's edges.")

(defun etaf-video-player--adopt-frame-background (frame)
  "Paint FRAME's unpaintable edge cells with the player surface color.
Emacs reserves the last character cell of every line and any partial bottom
line, and buffer text cannot paint those pixels; they show the frame
background.  A player that owns the frame therefore adopts the surface
color while it is open.  Save the previous value once and restore it in
`etaf-video-player--restore-frame-background'."
  (when (and (frame-live-p frame) (display-graphic-p frame))
    (unless etaf-video-player--frame-background
      (setq etaf-video-player--frame-background
            (cons frame (ignore-errors (face-attribute 'default :background frame)))))
    ;; Painting the frame edge is best-effort: a frame that cannot carry
    ;; the attribute simply keeps its own background.
    (ignore-errors
      (set-face-attribute 'default frame
                          :background (etaf-video-player-color :surface)))
    t))

(defun etaf-video-player--restore-frame-background ()
  "Restore the frame background saved by the player, once."
  (when-let* ((saved etaf-video-player--frame-background))
    (setq etaf-video-player--frame-background nil)
    (when (and (frame-live-p (car saved)) (cdr saved))
      (ignore-errors
        (set-face-attribute 'default (car saved) :background (cdr saved))))
    t))

(defun etaf-video-player--toggle-theme ()
  "Switch the player between the dark and light palette."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (next (if (eq etaf-video-player-theme-mode 'dark) 'light 'dark)))
    (setq etaf-video-player-theme-mode next)
    (etaf-set-value (etaf-video-player--player-theme-ref player)
                    (etaf-video-player-theme-defaults next))
    (etaf-video-player--remap-canvas-face)
    (when-let* ((buffer (etaf-video-player--player-buffer player))
                (window (and (buffer-live-p buffer)
                             (get-buffer-window buffer t))))
      (etaf-video-player--adopt-frame-background (window-frame window)))
    t))

(defun etaf-video-player--player-close (player)
  "Release PLAYER's status timer and buffer state."
  (when-let* ((timer (etaf-video-player--player-hud-timer player)))
    (cancel-timer timer)
    (setf (etaf-video-player--player-hud-timer player) nil)))

(defun etaf-video-player--install-size-hook ()
  "Install the application's window size hook once."
  (unless etaf-video-player--size-hook-installed
    (add-hook 'window-size-change-functions #'etaf-video-player--window-size-changed)
    (setq etaf-video-player--size-hook-installed t)))

;;;###autoload
(defun etaf-video-player-open (&optional source)
  "Open the video player and return its buffer.
SOURCE is nil for the built-in demo, a file name, an HTTP(S) URL, or a plist
accepted by `etaf-video-source-info'.  The hints `:columns' and `:rows'
(canvas size in character cells), `:speed' (playback rate), `:audio' and
`:volume' are read from the plist form.  Image frames need a graphical frame;
elsewhere the native Component falls back to a density-ramp canvas.  The
canvas is fitted to the selected window unless both size hints are given.  An
existing player is closed first; unreadable files, non-HTTP(S) URLs and
unsupported sources signal `user-error' before any process starts."
  (interactive (list (let ((name (read-file-name "Video file (empty for demo): " nil nil nil)))
                       (if (string-empty-p name) nil name))))
  (let* ((hints (and (consp source) source))
         (speed (or (plist-get hints :speed) 1))
         (audio (if (plist-member hints :audio)
                    (plist-get hints :audio)
                  etaf-video-player-audio))
         (volume (or (plist-get hints :volume) etaf-video-player-volume))
         (sources (or (plist-get hints :playlist) (list source)))
         (index (or (plist-get hints :index) 0))
         (queue (mapcar #'etaf-video-source-info sources)))
    (unless queue
      (user-error "A video player needs at least one item in its playlist"))
    (unless (and (integerp index) (<= 0 index) (< index (length queue)))
      (user-error "Playlist index is outside the queue: %S" index))
    (unless (and (numberp speed) (> speed 0))
      (user-error "Playback speed must be a positive number: %S" speed))
    (unless (and (numberp volume) (<= 0 volume 100))
      (user-error "Audio volume must be between 0 and 100: %S" volume))
    (when (get-buffer etaf-video-player--buffer-name)
      (with-current-buffer (get-buffer etaf-video-player--buffer-name)
        (when etaf-video-player--player
          (etaf-video-player-close))))
    (let* ((buffer (get-buffer-create etaf-video-player--buffer-name))
           (window (selected-window))
           (explicit (and (integerp (plist-get hints :columns))
                          (integerp (plist-get hints :rows))))
           (grid (if explicit
                     (cons (plist-get hints :columns) (plist-get hints :rows))
                   (cons etaf-video-player--initial-columns
                         etaf-video-player--initial-rows)))
           (player (etaf-video-player--player-create
                    buffer queue
                    :speed speed :audio audio :volume volume
                    :columns (car grid) :rows (cdr grid)
                    :index index
                    :loop (or (plist-get hints :loop) 'none)
                    :shuffle (plist-get hints :shuffle))))
      (setf (etaf-video-player--player-explicit-grid player) (and explicit t))
      (etaf-video-player--player-adopt-subtitle player (etaf-video-player--player-spec player))
      (condition-case problem
          (progn
            (with-current-buffer buffer
              (setq-local etaf-video-player--player player)
              (setq-local mode-line-format nil)
              (setq-local truncate-lines t)
              (setq-local auto-hscroll-mode nil)
              ;; A video frame owns the whole canvas; a bar or box cursor over
              ;; an image cell would flash a border around the picture.
              (setq-local cursor-type nil)
              (setq-local emulation-mode-map-alists
                          (cons 'etaf-video-player--command-maps
                                (remq 'etaf-video-player--command-maps
                                      emulation-mode-map-alists)))
              (setq-local buffer-display-table
                          (let ((table (copy-sequence (or standard-display-table
                                                          (make-display-table)))))
                            (set-display-table-slot table 'truncation ?\s)
                            table))
              (etaf-video-player--remap-canvas-face)
              (add-hook 'kill-buffer-hook #'etaf-video-player--kill-buffer-cleanup nil t)
              (use-local-map etaf-video-player-mode-map))
            (etaf-video-player--show buffer)
            (etaf-video-player--adopt-frame-background (window-frame window))
            (etaf-mount buffer (etaf-video-player--view player))
            (etaf-video-player--install-size-hook)
            (etaf-video-player--sync-layout player)
            (etaf-video-player--player-resume player)
            (setf (etaf-video-player--player-hud-timer player)
                  (run-at-time 0.0 etaf-video-player--hud-interval
                               #'etaf-video-player--player-tick player))
            buffer)
        ((error)
         (etaf-video-player--teardown buffer player)
         (signal (car problem) (cdr problem)))))))

;;;###autoload
(defun etaf-video-player-open-file (file)
  "Play the local video FILE in the video player."
  (interactive "fVideo file: ")
  (etaf-video-player-open (list :file file)))

;;;###autoload
(defun etaf-video-player-open-url (url)
  "Play the HTTP(S) video stream URL in the video player.
The stream is decoded directly by ffmpeg, so nothing is downloaded first.
Seeking depends on the server supporting range requests; a dropped
connection is retried up to five seconds."
  (interactive "sVideo URL: ")
  (etaf-video-player-open (list :url url)))

;;;###autoload
(defun etaf-video-player-demo ()
  "Play the built-in generated test pattern."
  (interactive)
  (etaf-video-player-open '(:demo)))

(defun etaf-video-player--kill-buffer-cleanup ()
  "Release the player's frame paint and timer when its buffer is killed."
  (etaf-video-player--restore-frame-background)
  (when etaf-video-player--player
    (ignore-errors (etaf-video-player--player-close etaf-video-player--player))))

(defun etaf-video-player--teardown (buffer player)
  "Release PLAYER and close BUFFER without signaling."
  (etaf-video-player--restore-frame-background)
  (when player
    ;; Closing is the last chance to save where playback stopped.
    (ignore-errors
      (etaf-video-player--player-record-position
       player (etaf-video-player--state player) t))
    (ignore-errors (etaf-video-player--player-close player)))
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq-local etaf-video-player--player nil)
      (ignore-errors
        (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
          (etaf-unmount runtime)))
      (kill-buffer buffer))))

(defun etaf-video-player-close ()
  "Close the video player in the current buffer."
  (interactive)
  (etaf-video-player--teardown (current-buffer) etaf-video-player--player)
  t)

(defun etaf-video-player-toggle-playback ()
  "Toggle the current player between playing and paused."
  (interactive)
  (let ((player (etaf-video-player--current)))
    (etaf-video-toggle-playback (etaf-video-player--player-handle player))
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-step ()
  "Pause the current player and present exactly one more frame."
  (interactive)
  (let ((player (etaf-video-player--current)))
    (etaf-video-step (etaf-video-player--player-handle player))
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-seek (seconds)
  "Move the current player to SECONDS and restart decoding there."
  (interactive "nSeconds: ")
  (let ((player (etaf-video-player--current)))
    (etaf-video-seek (etaf-video-player--player-handle player) seconds)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-set-speed (speed)
  "Set the current player's rate to SPEED, a positive number."
  (interactive "nPlayback speed: ")
  (let ((player (etaf-video-player--current)))
    (etaf-video-player--player-set-speed player speed)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-set-volume (volume)
  "Set the current player's audio volume to VOLUME, from 0 to 100."
  (interactive "nAudio volume (0-100): ")
  (let ((player (etaf-video-player--current)))
    (etaf-video-player--player-set-volume player volume)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-set-audio (audio)
  "Turn the current player's audio on (non-nil) or off (nil).
Sources that report no audio stream stay silent either way, and pressing `a'
toggles the same state."
  (interactive "P")
  (let ((player (etaf-video-player--current)))
    (etaf-video-player--player-set-audio player audio)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-set-grid (columns rows)
  "Resize the current player's canvas to COLUMNS by ROWS cells."
  (interactive "nColumns: \nnRows: ")
  (let ((player (etaf-video-player--current)))
    (etaf-video-player--player-set-grid player columns rows t)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-fit ()
  "Fit the current player's canvas to the window showing it."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (window (get-buffer-window (etaf-video-player--player-buffer player) t)))
    (setf (etaf-video-player--player-explicit-grid player) nil)
    (if window
        (progn
          (etaf-video-player--refit player window)
          t)
      (user-error "The video player buffer is not shown in a window"))))

(defun etaf-video-player-next ()
  "Play the next playlist item.
The current item plays if it was playing; at the last item `loop' decides
whether playback wraps around or stops."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (count (length (etaf-video-player--player-queue player)))
         (index (etaf-video-player--player-index player))
         (playing (or (plist-get (etaf-video-player--state player) :playing)
                      (plist-get (etaf-video-player--state player) :ended))))
    (etaf-video-player--player-select
     player (if (< (1+ index) count) (1+ index) 0) playing))
  t)

(defun etaf-video-player-previous ()
  "Play the previous playlist item, wrapping around at the first one."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (count (length (etaf-video-player--player-queue player)))
         (index (etaf-video-player--player-index player))
         (playing (or (plist-get (etaf-video-player--state player) :playing)
                      (plist-get (etaf-video-player--state player) :ended))))
    (etaf-video-player--player-select player (mod (1- index) count) playing))
  t)

(defun etaf-video-player-play-index (index)
  "Play playlist item INDEX, starting from the beginning."
  (interactive "nPlaylist index: ")
  (etaf-video-player--player-select (etaf-video-player--current) index t)
  t)

(defun etaf-video-player-enqueue (source)
  "Append SOURCE to the current player's playlist.
SOURCE is anything `etaf-video-source-info' accepts."
  (interactive (list (read-file-name "Add video: " nil nil t)))
  (let* ((player (etaf-video-player--current))
         (spec (etaf-video-source-info source))
         (queue (append (etaf-video-player--player-queue player) (list spec))))
    (setf (etaf-video-player--player-queue player) queue)
    (etaf-set-value (etaf-video-player--player-queue-ref player) queue)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-remove (index)
  "Remove playlist item INDEX from the current player.
Removing the item that is playing selects the nearest remaining one; the
last remaining item cannot be removed."
  (interactive "nRemove playlist index: ")
  (let* ((player (etaf-video-player--current))
         (queue (etaf-video-player--player-queue player))
         (count (length queue))
         (index (max 0 (min (1- count) index))))
    (when (<= count 1)
      (user-error "The playlist has only one item"))
    (let ((remaining (append (seq-take queue index) (seq-drop queue (1+ index)))))
      (setf (etaf-video-player--player-queue player) remaining)
      (etaf-set-value (etaf-video-player--player-queue-ref player) remaining)
      (if (= index (etaf-video-player--player-index player))
          (etaf-video-player--player-select
           player (min index (1- (length remaining)))
           (plist-get (etaf-video-player--state player) :playing))
        (let ((current (etaf-video-player--player-index player)))
          (when (> current index) (cl-decf current))
          (setf (etaf-video-player--player-index player) current)
          (etaf-set-value (etaf-video-player--player-index-ref player) current)
          (etaf-video-player--player-render player)))))
  t)

(defun etaf-video-player-toggle-loop ()
  "Cycle the current player's loop mode: none, all, one."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (next (pcase (etaf-video-player--player-loop player)
                 ('none 'all) ('all 'one) (_ 'none))))
    (setf (etaf-video-player--player-loop player) next)
    (etaf-set-value (etaf-video-player--player-loop-ref player) next)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-toggle-shuffle ()
  "Toggle shuffle playback for the current player."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (next (not (etaf-video-player--player-shuffle player))))
    (setf (etaf-video-player--player-shuffle player) next)
    (etaf-set-value (etaf-video-player--player-shuffle-ref player) next)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-state ()
  "Return the current player's state as a detached plist.
Keys are `:source', `:playing', `:position', `:duration', `:speed',
`:columns', `:rows', `:mode' (requested, always `image'), `:render-mode'
(the effective mode, `ascii' on a terminal), `:fps' (display rate),
`:presented-fps', `:source-fps', `:source-width', `:source-height',
`:received', `:presented', `:dropped', `:audio', `:volume', `:subtitle-file'
(the loaded track or nil), `:subtitle-on' and `:ended'.
It reads the live player without changing it, and signals `user-error'
outside a player buffer."
  (let* ((player (etaf-video-player--current))
         (state (etaf-video-player--state player))
         (spec (etaf-video-player--player-spec player)))
    (list :source (plist-get state :source)
          :playing (plist-get state :playing)
          :position (plist-get state :position)
          :duration (plist-get state :duration)
          :speed (plist-get state :speed)
          :columns (etaf-video-player--player-columns player)
          :rows (etaf-video-player--player-rows player)
          :mode 'image
          :render-mode (plist-get state :mode)
          :fps (plist-get state :display-fps)
          :presented-fps (or (etaf-video-player--player-sample-fps player) 0.0)
          :source-fps (plist-get state :source-fps)
          :source-width (plist-get spec :width)
          :source-height (plist-get spec :height)
          :received (plist-get state :received)
          :presented (plist-get state :presented)
          :dropped (plist-get state :dropped)
          :audio (etaf-video-player--player-audio player)
          :volume (etaf-video-player--player-volume player)
          :title (etaf-video-player--title (etaf-video-player--player-spec player))
          :queue-length (length (etaf-video-player--player-queue player))
          :index (etaf-video-player--player-index player)
          :loop (etaf-video-player--player-loop player)
          :shuffle (and (etaf-video-player--player-shuffle player) t)
          :subtitle-file (etaf-video-player--player-subtitle-file player)
          :subtitle-on (and (etaf-video-player--player-subtitle-on player) t)
          :ended (plist-get state :ended))))

(defun etaf-video-player--forward-command ()
  "Seek five seconds forward."
  (interactive)
  (etaf-video-player-seek
   (+ (plist-get (etaf-video-player-state) :position) 5)))

(defun etaf-video-player--direction (direction)
  "Seek the media with DIRECTION and return the result symbol."
  (pcase direction
    ('left (etaf-video-player--backward-command) 'handled)
    ('right (etaf-video-player--forward-command) 'handled)
    (_ 'release)))

(defun etaf-video-player--backward-command ()
  "Seek five seconds backward."
  (interactive)
  (etaf-video-player-seek
   (- (plist-get (etaf-video-player-state) :position) 5)))

(defun etaf-video-player--next-speed (speed)
  "Return the next playback rate after SPEED."
  (or (cl-find-if (lambda (candidate) (> candidate speed))
                  etaf-video-player--speeds)
      (car etaf-video-player--speeds)))

(defun etaf-video-player-cycle-speed ()
  "Cycle the current player through the supported playback rates."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (speed (etaf-video-player--player-speed player))
         (next (etaf-video-player--next-speed speed)))
    (etaf-video-player-set-speed next))
  t)

(defun etaf-video-player--speed-up-command ()
  "Raise the playback rate to the next supported value."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (speed (etaf-video-player--player-speed player))
         (next (or (cl-find-if (lambda (candidate) (> candidate speed))
                               etaf-video-player--speeds)
                   (car (last etaf-video-player--speeds)))))
    (etaf-video-player-set-speed next)))

(defun etaf-video-player--speed-down-command ()
  "Lower the playback rate to the next supported value."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (speed (etaf-video-player--player-speed player))
         (next (or (car (last (cl-remove-if (lambda (candidate) (>= candidate speed))
                                            etaf-video-player--speeds)))
                   (car etaf-video-player--speeds))))
    (etaf-video-player-set-speed next)))

(defun etaf-video-player--volume-up-command ()
  "Raise the audio volume by one step, capped at 100."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (volume (min 100 (+ (etaf-video-player--player-volume player)
                             etaf-video-player--volume-step))))
    (etaf-video-player-set-volume volume)))

(defun etaf-video-player--volume-down-command ()
  "Lower the audio volume by one step, capped at 0."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (volume (max 0 (- (etaf-video-player--player-volume player)
                           etaf-video-player--volume-step))))
    (etaf-video-player-set-volume volume)))

(defun etaf-video-player--toggle-audio-command ()
  "Toggle the current player's audio sidecar."
  (interactive)
  (let ((player (etaf-video-player--current)))
    (etaf-video-player-set-audio (not (etaf-video-player--player-audio player)))))

;;;###autoload
(defun etaf-video-player-subtitle-load (file)
  "Load the subtitle FILE into the current player.
FILE must be a readable SubRip (`.srt') or WebVTT (`.vtt') track; it replaces
any current track and starts shown.  Signals `user-error' outside a player
buffer and `etaf-video-player-subtitle-error' when the file cannot be read.
Returns the parsed cues."
  (interactive
   (list (read-file-name
          "字幕文件: "
          (let ((spec (and etaf-video-player--player
                           (etaf-video-player--player-spec etaf-video-player--player))))
            (if (plist-get spec :file)
                (file-name-directory (plist-get spec :file))
              default-directory)))))
  (let* ((player (etaf-video-player--current))
         (cues (etaf-video-player-subtitle-parse file)))
    (etaf-video-player--player-set-subtitle player cues file)
    (etaf-video-player--player-render player)
    (message "字幕已加载：%s（%d 条）" (file-name-nondirectory file) (length cues))
    cues))

;;;###autoload
(defun etaf-video-player-save-screenshot (&optional file)
  "Save the current video frame as a PNG image.
FILE names the output image; nil writes a timestamped PNG beside the playing
file (or in the temporary directory for a stream).  The frame is decoded with
ffmpeg in the background at the current playback second, and the echo area
reports the result.  Returns the output path; signals `user-error' outside a
player or for the built-in demo, which has no frame to capture."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (state (etaf-video-player--state player))
         (spec (etaf-video-player--player-spec player))
         (position (or (plist-get state :position) 0))
         (source (pcase (plist-get spec :kind)
                   ('file (plist-get spec :file))
                   ('url (plist-get spec :url))
                   (_ nil)))
         (output (or file (etaf-video-player--screenshot-output spec))))
    (unless source
      (user-error "The built-in demo has no frame to capture"))
    (make-process
     :name "etaf-video-player-screenshot"
     :command (list etaf-video-ffmpeg-program
                    "-hide_banner" "-loglevel" "error"
                    "-ss" (format "%.3f" position)
                    "-i" source
                    "-frames:v" "1" "-y" output)
     :noquery t
     :sentinel (lambda (process event)
                 (when (memq (process-status process) '(exit signal))
                   (if (and (eq 'exit (process-status process))
                            (zerop (process-exit-status process))
                            (file-readable-p output))
                       (message "截图已保存：%s" output)
                     (message "截图失败：%s" (string-trim event))))))
    output))

(defun etaf-video-player--screenshot-output (spec)
  "Return the default PNG path for SPEC's current frame."
  (let ((base (pcase (plist-get spec :kind)
                ('file (file-name-base (plist-get spec :file)))
                ('url "stream")
                (_ "frame"))))
    (expand-file-name
     (format "%s-%s.png" base (format-time-string "%H%M%S"))
     (if (eq (plist-get spec :kind) 'file)
         (file-name-directory (plist-get spec :file))
       temporary-file-directory))))

(defun etaf-video-player--subtitle-toggle-command ()
  "Toggle subtitles for the current player.
With a track loaded the key hides and shows it; without one it loads the
track beside the video, or asks for a subtitle file when none exists."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (file (etaf-video-player--player-subtitle-file player)))
    (cond
     ((etaf-video-player--player-subtitle-on player)
      (setf (etaf-video-player--player-subtitle-on player) nil)
      (etaf-video-player--player-render player)
      (message "字幕已关闭"))
     (file
      (setf (etaf-video-player--player-subtitle-on player) t)
      (etaf-video-player--player-render player)
      (message "字幕已开启：%s" (file-name-nondirectory file)))
     (t
      (let* ((spec (etaf-video-player--player-spec player))
             (beside (and (eq (plist-get spec :kind) 'file)
                          (etaf-video-player-subtitle-beside (plist-get spec :file)))))
        (if beside
            (etaf-video-player-subtitle-load beside)
          (call-interactively #'etaf-video-player-subtitle-load)))))))

(defun etaf-video-player--preset-command ()
  "Apply the grid preset named by the key that invoked this command."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (key last-command-event)
         (columns (cdr (assq key etaf-video-player-grid-presets))))
    (unless columns
      (user-error "No video player grid preset for %S" key))
    (etaf-video-player-set-grid
     columns
     (etaf-video-player--rows-for-columns
      (etaf-video-player--aspect (etaf-video-player--player-spec player)) columns))))

(defun etaf-video-player--help-command ()
  "Show the video player key bindings."
  (interactive)
  (message (concat "视频播放器：SPC 播放/暂停 · n 单步 · f/b ±5s · <> 上/下条"
                   " · +/- 速度 · [ ] 音量 · a 声音 · 1-4 画布 · F 适配"
                   " · T 明暗主题 · o 打开 · u 网址 · d 演示 · q 关闭")))

(provide 'etaf-video-player-app)
;;; etaf-video-player-app.el ends here
