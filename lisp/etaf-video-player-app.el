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
(require 'etaf)

(defconst etaf-video-player--buffer-name "*Video Player*"
  "Name of the single application buffer.")

(defconst etaf-video-player--hud-ref 'etaf-video-player-hud
  "Retained Host reference of the status line.")

(defconst etaf-video-player--hud-interval 0.25
  "Seconds between status line refreshes.")

(defconst etaf-video-player--speeds '(0.5 1 2 4 8)
  "Playback rates offered by the speed commands.")

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
    (define-key map (kbd "F") #'etaf-video-player-fit)
    (define-key map (kbd "o") #'etaf-video-player-open-file)
    (define-key map (kbd "u") #'etaf-video-player-open-url)
    (define-key map (kbd "d") #'etaf-video-player-demo)
    (define-key map (kbd "?") #'etaf-video-player--help-command)
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
           (define-key map (kbd "F") #'etaf-video-player-fit)
           (define-key map (kbd "o") #'etaf-video-player-open-file)
           (define-key map (kbd "u") #'etaf-video-player-open-url)
           (define-key map (kbd "d") #'etaf-video-player-demo)
           (define-key map (kbd "?") #'etaf-video-player--help-command)
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
record owns the canvas size, the playback rate, the audio state and the
status line."
  buffer spec handle
  columns rows speed audio volume
  columns-ref rows-ref speed-ref audio-ref volume-ref
  hud-text hud-text-ref hud-timer
  sample sample-fps)

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

(defun etaf-video-player--window-grid (window aspect)
  "Return the (COLUMNS . ROWS) fitting WINDOW for an ASPECT frame.
One row is reserved for the status line."
  (let* ((frame (window-frame window))
         (cell-aspect (/ (float (frame-char-height frame))
                         (max 1 (frame-char-width frame))))
         (max-columns (max 8 (window-body-width window)))
         (max-rows (max 3 (1- (window-body-height window))))
         (scale (* aspect cell-aspect))
         (columns (min max-columns (max 8 (floor (* max-rows scale)))))
         (rows (max 3 (min max-rows (floor (/ columns scale))))))
    (cons columns rows)))

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

(defun etaf-video-player--hud (player state)
  "Return PLAYER's one-line status text for STATE."
  (let ((spec (etaf-video-player--player-spec player)))
    (format "%s %s/%s  %2.0ffps  dropped %d  %dx%d  src %sx%s  vol %d%%  %s  %sx"
            (cond ((plist-get state :ended) "ended")
                  ((plist-get state :playing) "playing")
                  (t "paused"))
            (etaf-video-player--clock (plist-get state :position))
            (etaf-video-player--clock (plist-get state :duration))
            (etaf-video-player--sampled-fps player state)
            (or (plist-get state :dropped) 0)
            (etaf-video-player--player-columns player)
            (etaf-video-player--player-rows player)
            (or (plist-get spec :width) "?")
            (or (plist-get spec :height) "?")
            (etaf-video-player--player-volume player)
            (if (etaf-video-player--player-audio player) "sound" "mute")
            (format "%s" (etaf-video-player--player-speed player)))))

(defun etaf-video-player--player-render (player)
  "Publish PLAYER's status line from the live video state."
  (let ((state (etaf-video-player--state player)))
    (setf (etaf-video-player--player-hud-text player)
          (etaf-video-player--hud player state))
    (when-let* ((runtime (etaf-runtime-for-buffer
                          (etaf-video-player--player-buffer player))))
      (etaf-runtime-update-host-content
       runtime etaf-video-player--hud-ref
       (etaf-video-player--player-hud-text player)))))

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
    (buffer spec columns rows speed audio volume)
  "Create a player for BUFFER, SPEC, COLUMNS, ROWS, SPEED, AUDIO and VOLUME.
The retained refs returned here are closed over by the application View."
  (let ((player (etaf-video-player--player--make
                 :buffer buffer :spec spec
                 :handle (make-symbol "etaf-video-player")
                 :columns columns :rows rows :speed speed
                 :audio (and audio t) :volume volume
                 :hud-text "paused 00:00/--:--")))
    (setf (etaf-video-player--player-columns-ref player) (etaf-ref columns)
          (etaf-video-player--player-rows-ref player) (etaf-ref rows)
          (etaf-video-player--player-speed-ref player) (etaf-ref speed)
          (etaf-video-player--player-audio-ref player) (etaf-ref (and audio t))
          (etaf-video-player--player-volume-ref player) (etaf-ref volume)
          (etaf-video-player--player-hud-text-ref player)
          (etaf-ref (etaf-video-player--player-hud-text player)))
    player))

(defun etaf-video-player--view (player)
  "Return the mountable View of PLAYER."
  (etaf-view
   (flex :flex-direction 'column :width '(vw 100)
         :background-color "#0B0C0E" :color "#C9CDD3"
     (etaf-video :src (etaf-video-player--player-spec player)
                 :mode 'image
                 :columns (etaf-value (etaf-video-player--player-columns-ref player))
                 :rows (etaf-value (etaf-video-player--player-rows-ref player))
                 :speed (etaf-value (etaf-video-player--player-speed-ref player))
                 :audio (etaf-value (etaf-video-player--player-audio-ref player))
                 :volume (etaf-value (etaf-video-player--player-volume-ref player))
                 :device-pixel-ratio etaf-video-player-device-pixel-ratio
                 :autoplay t
                 :handle (etaf-video-player--player-handle player))
     (box :height '(lh 1) :width '(vw 100) :wrap-mode 'none :overflow 'hidden
       (text :id "hud" :ref etaf-video-player--hud-ref
             (expr (etaf-value (etaf-video-player--player-hud-text-ref player))))))))

(defun etaf-video-player--window-size-changed (frame)
  "Refit every video player shown on FRAME after a window resize."
  (dolist (window (window-list frame))
    (with-current-buffer (window-buffer window)
      (when etaf-video-player--player
        (etaf-video-player--refit etaf-video-player--player window)))))

(defun etaf-video-player--refit (player window)
  "Fit PLAYER to WINDOW and republish its canvas size."
  (when-let* ((runtime (etaf-runtime-for-buffer (etaf-video-player--player-buffer player))))
    (etaf-runtime-refit runtime (window-body-width window t) (window-body-height window)))
  (let* ((spec (etaf-video-player--player-spec player))
         (grid (etaf-video-player--window-grid
                window (etaf-video-player--aspect spec))))
    (unless (equal grid (cons (etaf-video-player--player-columns player)
                              (etaf-video-player--player-rows player)))
      (etaf-video-player--player-set-grid player (car grid) (cdr grid)))))

(defun etaf-video-player--player-set-grid (player columns rows)
  "Resize PLAYER's canvas to COLUMNS by ROWS and restart the producer."
  (unless (and (integerp columns) (> columns 0) (integerp rows) (> rows 0))
    (user-error "Canvas size must be positive integers: %S by %S" columns rows))
  (unless (and (= columns (etaf-video-player--player-columns player))
               (= rows (etaf-video-player--player-rows player)))
    (setf (etaf-video-player--player-columns player) columns
          (etaf-video-player--player-rows player) rows)
    (etaf-set-value (etaf-video-player--player-columns-ref player) columns)
    (etaf-set-value (etaf-video-player--player-rows-ref player) rows)))

(defun etaf-video-player--player-set-speed (player speed)
  "Set PLAYER's rate to SPEED, a positive number."
  (unless (and (numberp speed) (> speed 0))
    (user-error "Playback speed must be a positive number: %S" speed))
  (setf (etaf-video-player--player-speed player) speed)
  (etaf-set-value (etaf-video-player--player-speed-ref player) speed))

(defun etaf-video-player--player-set-volume (player volume)
  "Set PLAYER's audio volume to VOLUME, from 0 to 100."
  (unless (and (numberp volume) (<= 0 volume 100))
    (user-error "Audio volume must be between 0 and 100: %S" volume))
  (setf (etaf-video-player--player-volume player) volume)
  (etaf-set-value (etaf-video-player--player-volume-ref player) volume))

(defun etaf-video-player--player-set-audio (player audio)
  "Turn PLAYER's audio sidecar on (non-nil) or off (nil)."
  (setf (etaf-video-player--player-audio player) (and audio t))
  (etaf-set-value (etaf-video-player--player-audio-ref player) (and audio t)))

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
         (spec (etaf-video-source-info source)))
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
           (grid (if (and (integerp (plist-get hints :columns))
                          (integerp (plist-get hints :rows)))
                     (cons (plist-get hints :columns) (plist-get hints :rows))
                   (etaf-video-player--window-grid
                    window (etaf-video-player--aspect spec))))
           (player (etaf-video-player--player-create
                    buffer spec (car grid) (cdr grid) speed audio volume)))
      (condition-case problem
          (progn
            (with-current-buffer buffer
              (setq-local etaf-video-player--player player)
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
              (use-local-map etaf-video-player-mode-map)
              (etaf-mount buffer (etaf-video-player--view player)
                          (list :viewport-width (window-body-width window t)
                                :viewport-height (window-body-height window))))
            (let ((display-buffer-overriding-action '((display-buffer-same-window))))
              (pop-to-buffer buffer))
            (when-let* ((shown (get-buffer-window buffer t)))
              (set-window-hscroll shown 0))
            (etaf-video-player--install-size-hook)
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

(defun etaf-video-player--teardown (buffer player)
  "Release PLAYER and close BUFFER without signaling."
  (when player
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
    (etaf-video-player--player-set-grid player columns rows)
    (etaf-video-player--player-render player))
  t)

(defun etaf-video-player-fit ()
  "Fit the current player's canvas to the window showing it."
  (interactive)
  (let* ((player (etaf-video-player--current))
         (window (get-buffer-window (etaf-video-player--player-buffer player) t)))
    (if window
        (progn
          (etaf-video-player--refit player window)
          t)
      (user-error "The video player buffer is not shown in a window"))))

(defun etaf-video-player-state ()
  "Return the current player's state as a detached plist.
Keys are `:source', `:playing', `:position', `:duration', `:speed',
`:columns', `:rows', `:mode' (requested, always `image'), `:render-mode'
(the effective mode, `ascii' on a terminal), `:fps' (display rate),
`:presented-fps', `:source-fps', `:source-width', `:source-height',
`:received', `:presented', `:dropped', `:audio', `:volume' and `:ended'.
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
          :ended (plist-get state :ended))))

(defun etaf-video-player--forward-command ()
  "Seek five seconds forward."
  (interactive)
  (etaf-video-player-seek
   (+ (plist-get (etaf-video-player-state) :position) 5)))

(defun etaf-video-player--backward-command ()
  "Seek five seconds backward."
  (interactive)
  (etaf-video-player-seek
   (- (plist-get (etaf-video-player-state) :position) 5)))

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
  (message (concat "Video player: SPC play/pause, n step, f/b +-5s, +/- speed, "
                   "[/] volume, a sound, 1-4 grid, F fit, o open, u url, "
                   "d demo, q close")))

(provide 'etaf-video-player-app)
;;; etaf-video-player-app.el ends here
