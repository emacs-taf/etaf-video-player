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
(require 'etaf-ui)
(require 'etaf-video-player-theme)

(defconst etaf-video-player--buffer-name "*Video Player*"
  "Name of the single application buffer.")

(defconst etaf-video-player--hud-ref 'etaf-video-player-hud
  "Retained Host reference of the status line.")

(defconst etaf-video-player--time-ref 'etaf-video-player-time
  "Retained Host reference of the playback clock.")

(defconst etaf-video-player--play-ref 'etaf-video-player-play
  "Retained Host reference of the play/pause glyph.")

(defconst etaf-video-player--volume-ref 'etaf-video-player-volume-text
  "Retained Host reference of the volume percentage.")

(defconst etaf-video-player--audio-ref 'etaf-video-player-audio-text
  "Retained Host reference of the sound glyph.")

(defconst etaf-video-player--progress-fill-ref 'etaf-video-player-progress-fill
  "Retained Host reference of the progress bar fill.")

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
    (define-key map (kbd ">") #'etaf-video-player-next)
    (define-key map (kbd "<") #'etaf-video-player-previous)
    (define-key map (kbd "l") #'etaf-video-player-toggle-loop)
    (define-key map (kbd "s") #'etaf-video-player-toggle-shuffle)
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
           (define-key map (kbd ">") #'etaf-video-player-next)
           (define-key map (kbd "<") #'etaf-video-player-previous)
           (define-key map (kbd "l") #'etaf-video-player-toggle-loop)
           (define-key map (kbd "s") #'etaf-video-player-toggle-shuffle)
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
record owns the playlist, the current item, the canvas size, the playback
rate, the audio state and the status line."
  buffer spec handle queue index loop shuffle
  columns rows speed audio volume
  spec-ref columns-ref rows-ref speed-ref audio-ref volume-ref
  queue-ref index-ref loop-ref shuffle-ref
  hud-text hud-text-ref hud-timer
  sample sample-fps ended-seen)

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
Four rows are reserved for the application chrome (header, progress bar,
transport row and the key hint footer) and four columns for the body's
horizontal padding, so the canvas never overflows the window."
  (let* ((frame (window-frame window))
         (width (window-body-width window))
         (chrome (+ 4 (if (>= width 100) 30 0) (if (>= width 150) 26 0)))
         (cell-aspect (/ (float (frame-char-height frame))
                         (max 1 (frame-char-width frame))))
         (max-columns (max 8 (- width chrome)))
         (max-rows (max 3 (- (window-body-height window) 4)))
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
  "Publish PLAYER's transport and status text from the live video state.
One batched retained update refreshes the clock, the play/pause glyph, the
volume and sound labels; the progress fill moves through its retained
geometry, so the View is never republished for a playback second."
  (let* ((state (etaf-video-player--state player))
         (runtime (etaf-runtime-for-buffer
                   (etaf-video-player--player-buffer player)))
         (playing (plist-get state :playing))
         (duration (plist-get (etaf-video-player--player-spec player) :duration)))
    (when runtime
      (setf (etaf-video-player--player-hud-text player)
            (etaf-video-player--hud player state))
      (etaf-runtime-update-host-contents
       runtime
       (list (cons etaf-video-player--hud-ref
                   (etaf-video-player--player-hud-text player))
             (cons etaf-video-player--time-ref
                   (format "%s / %s"
                           (etaf-video-player--clock (plist-get state :position))
                           (etaf-video-player--clock duration)))
             (cons etaf-video-player--play-ref (if playing "⏸" "▶"))
             (cons etaf-video-player--volume-ref
                   (format "%d%%" (etaf-video-player--player-volume player)))
             (cons etaf-video-player--audio-ref
                   (if (etaf-video-player--player-audio player) "🔊" "🔇"))))
      (when (and duration (> duration 0))
        (etaf-runtime-update-host-geometries
         runtime
         (list (cons etaf-video-player--progress-fill-ref
                     (list :width
                           (list '% (* 100.0
                                       (min 1.0
                                            (/ (float (or (plist-get state :position) 0))
                                               duration)))))))))
      ;; Advance once when the item ends; the flag clears as soon as a new
      ;; item is not ended, so a manual replay rearms it.
      (if (plist-get state :ended)
          (unless (etaf-video-player--player-ended-seen player)
            (setf (etaf-video-player--player-ended-seen player) t)
            (when (buffer-live-p (etaf-video-player--player-buffer player))
              (etaf-video-player--player-advance player)))
        (setf (etaf-video-player--player-ended-seen player) nil)))))

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
                 :hud-text "paused 00:00/--:--")))
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
          (etaf-video-player--player-shuffle-ref player) (etaf-ref (and shuffle t))
          (etaf-video-player--player-hud-text-ref player)
          (etaf-ref (etaf-video-player--player-hud-text player)))
    player))

(defun etaf-video-player--title (spec)
  "Return a short display title for normalized source SPEC."
  (pcase (plist-get spec :kind)
    ('file (file-name-nondirectory (or (plist-get spec :file) "")))
    ('url (or (plist-get spec :url) "stream"))
    (_ "内建演示")))

(defun etaf-video-player--player-grid (player window)
  "Return the (COLUMNS . ROWS) fitting WINDOW for PLAYER's current item."
  (etaf-video-player--window-grid
   window (etaf-video-player--aspect (etaf-video-player--player-spec player))))

(defun etaf-video-player--player-select (player index &optional play)
  "Show QUEUE item INDEX in PLAYER, starting from the beginning.
An ordinary publication applies the new source, canvas size and index; the
native Component then rebuilds its session at position zero.  PLAY non-nil
starts the new item playing; otherwise it stays paused."
  (let* ((queue (etaf-video-player--player-queue player))
         (count (length queue))
         (index (max 0 (min (1- count) index)))
         (spec (nth index queue))
         (buffer (etaf-video-player--player-buffer player))
         (window (or (and (buffer-live-p buffer)
                          (get-buffer-window buffer t))
                     (selected-window))))
    ;; A track change always starts at the beginning, so clear the position
    ;; before the source change makes the Component rebuild its session.
    (ignore-errors
      (etaf-video-seek (etaf-video-player--player-handle player) 0))
    (setf (etaf-video-player--player-index player) index
          (etaf-video-player--player-spec player) spec
          (etaf-video-player--player-ended-seen player) nil)
    (let* ((grid (etaf-video-player--player-grid player window))
           (columns (car grid))
           (rows (cdr grid)))
      (setf (etaf-video-player--player-columns player) columns
            (etaf-video-player--player-rows player) rows)
      (etaf-set-value (etaf-video-player--player-spec-ref player) spec)
      (etaf-set-value (etaf-video-player--player-columns-ref player) columns)
      (etaf-set-value (etaf-video-player--player-rows-ref player) rows))
    (etaf-set-value (etaf-video-player--player-index-ref player) index)
    ;; The source publication rebuilt the session synchronously; a requested
    ;; play now acts on the new item.
    (when play
      (ignore-errors (etaf-video-play (etaf-video-player--player-handle player))))
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

(etaf-define-component etaf-video-player--shell (&key player)
  "Render the player shell for PLAYER with the application theme.
The layout adapts to the window: the playlist sidebar appears from 100
columns, the details panel from 150.  High-frequency values (clock, glyphs,
progress) travel through retained Host updates; the playlist, speed, loop
and shuffle re-render because they change rarely."
  :setup
  (etaf-theme-provide (etaf-video-player-theme-defaults))
  :render
  (let* ((spec (etaf-value (etaf-video-player--player-spec-ref player)))
         (queue (etaf-value (etaf-video-player--player-queue-ref player)))
         (index (etaf-value (etaf-video-player--player-index-ref player)))
         (speed (etaf-value (etaf-video-player--player-speed-ref player)))
         (loop (etaf-value (etaf-video-player--player-loop-ref player)))
         (shuffle (etaf-value (etaf-video-player--player-shuffle-ref player)))
         (handle (etaf-video-player--player-handle player))
         (line (etaf-video-player-color :line))
         (panel (etaf-video-player-color :panel))
         (panel2 (etaf-video-player-color :panel2))
         (ink (etaf-video-player-color :ink))
         (muted (etaf-video-player-color :muted))
         (buffer (etaf-video-player--player-buffer player))
         (window (or (and (buffer-live-p buffer) (get-buffer-window buffer t))
                     (selected-window)))
         (width (window-body-width window))
         (sidebar (>= width 100))
         (details (>= width 150)))
    (etaf-view
     (flex :flex-direction 'column :width '(vw 100) :height '(vh 100)
           :background-color (etaf-video-player-color :bg) :color ink
       (flex :flex-direction 'row :height '(lh 1) :width 'stretch
             :padding '((lh 0) (ch 2)) :justify-content 'space-between
             :background-color panel
             :border-bottom (list '(px 1) 'solid line)
         (etaf-label :text "ETAF 视频播放器" :variant 'strong)
         (text :ref etaf-video-player--hud-ref :id "etaf-video-player-hud"
               (expr (etaf-value (etaf-video-player--player-hud-text-ref player)))))
       (flex :flex-grow 1 :flex-basis '(lh 0) :flex-direction 'row
             :min-width '(px 0)
         (column :if sidebar :width '(ch 30) :min-width '(ch 0)
                 :background-color panel :padding '((lh 1) (ch 1))
                 :overflow 'hidden
           (etaf-label :text (format "播放列表（%d）" (length queue))
                       :variant 'strong)
           (text " ")
           (expr (mapcar
                  (lambda (entry)
                    (let ((position (car entry))
                          (item (cdr entry)))
                      (etaf-view
                       (etaf-button
                        :key position
                        :label (format "%s %d  %s"
                                       (if (= position index) "▸" " ")
                                       (1+ position)
                                       (etaf-video-player--title item))
                        :variant (if (= position index) 'secondary 'ghost)
                        :on-press (lambda ()
                                    (etaf-video-player-play-index position))))))
                  (cl-loop for item in queue
                           for position from 0
                           collect (cons position item)))))
         (flex :flex-grow 1 :flex-basis '(ch 0) :min-width '(px 0)
               :flex-direction 'column :align-items 'center
               :justify-content 'center :padding '((lh 1) (ch 2))
           (etaf-video :src (etaf-value (etaf-video-player--player-spec-ref player))
                       :mode 'image
                       :columns (etaf-value (etaf-video-player--player-columns-ref player))
                       :rows (etaf-value (etaf-video-player--player-rows-ref player))
                       :speed (etaf-value (etaf-video-player--player-speed-ref player))
                       :audio (etaf-value (etaf-video-player--player-audio-ref player))
                       :volume (etaf-value (etaf-video-player--player-volume-ref player))
                       :device-pixel-ratio etaf-video-player-device-pixel-ratio
                       :autoplay t
                       :handle handle
                       :on-press (lambda () (etaf-video-toggle-playback handle))))
         (column :if details :width '(ch 26) :min-width '(ch 0)
                 :background-color panel :padding '((lh 1) (ch 1))
                 :overflow 'hidden
           (etaf-label :text "正在播放" :variant 'strong)
           (text " ")
           (text (expr (etaf-video-player--title spec)))
           (text " ")
           (text (expr (format "分辨率   %s × %s"
                               (or (plist-get spec :width) "?")
                               (or (plist-get spec :height) "?"))))
           (text (expr (format "时长     %s"
                               (etaf-video-player--clock
                                (plist-get spec :duration)))))
           (text (expr (format "列表     %d / %d"
                               (1+ index) (length queue))))
           (text (expr (format "速度     %sx" speed)))
           (text (expr (format "循环     %s"
                               (pcase loop
                                 ('all "列表") ('one "单曲") (_ "关闭")))))
           (text (expr (format "随机     %s" (if shuffle "开" "关"))))
           (text " ")
           (etaf-label :text "操作" :variant 'strong)
           (text "点列表   切换视频")
           (text "点画面   播放 / 暂停")
           (text "拖画面   拖动进度")
           (text "</>      上一条 / 下一条")
           (text "l / s    循环 / 随机")))
       (column :width 'stretch :padding '((lh 1) (ch 2)) :background-color panel2
               :min-width '(px 0)
         (etaf-range :min 0 :max 100 :value 0
                     :fill-ref etaf-video-player--progress-fill-ref
                     :label "播放进度"
                     :on-commit (lambda (percent)
                                  (let ((duration (plist-get (etaf-video-player--player-spec player)
                                                             :duration)))
                                    (when duration
                                      (etaf-video-seek handle
                                                       (* duration (/ percent 100.0)))))))
         (flex :flex-direction 'row :height '(lh 1) :gap '((lh 0) (ch 1))
               :align-items 'center :min-width '(px 0)
           (text :ref etaf-video-player--time-ref :id "etaf-video-player-time"
                 "0:00 / --:--")
           (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(px 0) "")
           (box :padding '((lh 0) (ch 1)) :background-color (etaf-video-player-color :panel)
                :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda () (etaf-video-player-previous))
             (text "⏮"))
           (box :padding '((lh 0) (ch 1)) :background-color (etaf-video-player-color :panel)
                :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda ()
                            (etaf-video-seek handle
                                             (max 0 (- (or (plist-get
                                                            (etaf-video-player--state player)
                                                            :position)
                                                           0)
                                                       5))))
             (text "⏪ 5s"))
           (box :background-color (etaf-video-player-color :accent)
                :padding '((lh 0) (ch 2)) :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda () (etaf-video-toggle-playback handle))
             (text :ref etaf-video-player--play-ref :id "etaf-video-player-play" "▶"))
           (box :padding '((lh 0) (ch 1)) :background-color (etaf-video-player-color :panel)
                :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda ()
                            (etaf-video-seek handle
                                             (+ (or (plist-get
                                                     (etaf-video-player--state player)
                                                     :position)
                                                    0)
                                                5)))
             (text "5s ⏩"))
           (box :padding '((lh 0) (ch 1)) :background-color (etaf-video-player-color :panel)
                :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda () (etaf-video-player-next))
             (text "⏭"))
           (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(px 0) "")
           (box :padding '((lh 0) (ch 1)) :background-color (etaf-video-player-color :panel)
                :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda ()
                            (etaf-video-player-set-volume
                             (max 0 (- (etaf-video-player--player-volume player) 10))))
             (text "音量−"))
           (box :padding '((lh 0) (ch 1)) :background-color (etaf-video-player-color :panel)
                :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda ()
                            (etaf-video-player-set-volume
                             (min 100 (+ (etaf-video-player--player-volume player) 10))))
             (text "音量+"))
           (text :ref etaf-video-player--volume-ref :id "etaf-video-player-volume-text"
                 "100%")
           (box :padding '((lh 0) (ch 1)) :background-color (etaf-video-player-color :panel)
                :pointer 'hand :role 'button :tab-index 0
                :on-press (lambda ()
                            (etaf-video-player-set-audio
                             (not (etaf-video-player--player-audio player)))
                            (etaf-video-player--player-render player))
             (text :ref etaf-video-player--audio-ref :id "etaf-video-player-audio-text" "🔊"))
           (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(px 0) "")
           (etaf-button :label (format "%sx" speed) :variant 'ghost
                        :on-press (lambda () (etaf-video-player-cycle-speed)))
           (etaf-button :label (pcase loop ('all "循环：列表") ('one "循环：单曲") (_ "循环：关"))
                        :variant (if (eq loop 'none) 'ghost 'secondary)
                        :on-press #'etaf-video-player-toggle-loop)
           (etaf-button :label "随机" :variant (if shuffle 'secondary 'ghost)
                        :on-press #'etaf-video-player-toggle-shuffle)))
       (flex :flex-direction 'row :height '(lh 1) :width 'stretch
             :padding '((lh 0) (ch 2)) :background-color panel
             :border-top (list '(px 1) 'solid line)
         (text :color muted
               "SPC 播放/暂停 · n 单步 · f/b ±5s · </> 上/下条 · +/- 速度 · [ ] 音量 · a 声音 · l 循环 · s 随机 · F 适配 · q 关闭"))))))

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
         (sources (or (plist-get hints :playlist) (list source)))
         (index (or (plist-get hints :index) 0))
         (queue (mapcar #'etaf-video-source-info sources))
         (spec (nth index queue)))
    (unless queue
      (user-error "A video player needs at least one item in its playlist"))
    (unless (and (numberp speed) (> speed 0))
      (user-error "Playback speed must be a positive number: %S" speed))
    (unless (and (numberp volume) (<= volume 100))
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
                    buffer queue
                    :speed speed :audio audio :volume volume
                    :columns (car grid) :rows (cdr grid)
                    :index index
                    :loop (or (plist-get hints :loop) 'none)
                    :shuffle (plist-get hints :shuffle))))
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
              (use-local-map etaf-video-player-mode-map))
            (etaf-video-player--show buffer)
            (etaf-mount buffer (etaf-video-player--view player)
                        (list :viewport-width (window-body-width window t)
                              :viewport-height (window-body-height window)))
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
          :title (etaf-video-player--title (etaf-video-player--player-spec player))
          :queue-length (length (etaf-video-player--player-queue player))
          :index (etaf-video-player--player-index player)
          :loop (etaf-video-player--player-loop player)
          :shuffle (and (etaf-video-player--player-shuffle player) t)
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
