;;; etaf-video-player-tests.el --- Public acceptance scenarios -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Public-entry scenarios for the player.  Decoding, image frames, the audio
;; sidecar and publication belong to the native `etaf-video' Component, so
;; this suite drives it through the application entry only.  The producer,
;; metadata and audio are the repository's fake fixtures, so the suite needs
;; no real decoder, no network, no sound and no graphical frame; one gated
;; scenario runs the real ffmpeg path.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'etaf-video-player)

(defconst etaf-video-player-tests--fixtures
  (expand-file-name "fixtures"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Fixture directory beside the test source.")

(defconst etaf-video-player-tests--ffmpeg
  (expand-file-name "fake-ffmpeg.py" etaf-video-player-tests--fixtures)
  "Executable fixture standing in for ffmpeg.")

(defconst etaf-video-player-tests--ffprobe
  (expand-file-name "fake-ffprobe.py" etaf-video-player-tests--fixtures)
  "Executable fixture standing in for ffprobe.")

(defconst etaf-video-player-tests--ffplay
  (expand-file-name "fake-ffplay.py" etaf-video-player-tests--fixtures)
  "Executable fixture standing in for ffplay.")

(defconst etaf-video-player-tests--input
  (expand-file-name "fake-ffmpeg.py" etaf-video-player-tests--fixtures)
  "An existing file accepted as the video input; the fixture ignores it.")

(defun etaf-video-player-tests--log ()
  "Return a fresh log path for recorded fixture invocations."
  (make-temp-file "etaf-video-player-log-"))

(defun etaf-video-player-tests--runs (log)
  "Return the recorded fixture invocations in LOG as argument lists."
  (when (file-exists-p log)
    (mapcar (lambda (line) (split-string line "\000" t))
            (split-string
             (with-temp-buffer
               (insert-file-contents log)
               (buffer-string))
             "\n" t))))

(defun etaf-video-player-tests--argument (arguments flag)
  "Return the value following FLAG in ARGUMENTS, or nil."
  (cadr (member flag arguments)))

(defun etaf-video-player-tests--ffplay-pids (log)
  "Return every recorded ffplay process id in LOG."
  (when (file-exists-p log)
    (let (pids)
      (with-temp-buffer
        (insert-file-contents log)
        (goto-char (point-min))
        (while (re-search-forward "^pid=\\([0-9]+\\)$" nil t)
          (push (string-to-number (match-string 1)) pids)))
      (nreverse pids))))

(defun etaf-video-player-tests--ffplay-arguments (log)
  "Return the last recorded ffplay argument list in LOG, or nil."
  (car (last (cl-remove-if-not (lambda (arguments) (member "-nodisp" arguments))
                               (etaf-video-player-tests--runs log)))))

(defun etaf-video-player-tests--ffplay-runs (log)
  "Return the number of recorded ffplay invocations in LOG."
  (length (cl-remove-if-not (lambda (arguments) (member "-nodisp" arguments))
                            (etaf-video-player-tests--runs log))))

(defun etaf-video-player-tests--cleanup ()
  "Close any leftover player without signaling."
  (when-let* ((buffer (get-buffer "*Video Player*")))
    (with-current-buffer buffer
      (condition-case nil
          (etaf-video-player-close)
        (error nil)))))

(defun etaf-video-player-tests--wait (predicate &optional seconds)
  "Wait until PREDICATE is non-nil for at most SECONDS, then retry once.
Return PREDICATE's final value."
  (let ((deadline (+ (float-time) (or seconds 5))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.02)
      (sleep-for 0.01))
    (funcall predicate)))

(defun etaf-video-player-tests--state ()
  "Return the live player state."
  (etaf-video-player-state))

(defun etaf-video-player-tests--visible (line)
  "Return LINE's active characters without EBox display padding.
EBox pads rows with `space' display characters for background painting and
for centering; those characters are not video pixels, on either side."
  (let ((position 0) (end (length line)) start cut)
    (while (< position end)
      (let* ((display (get-text-property position 'display line))
             (padding (and (consp display) (eq (car display) 'space))))
        (cond ((and padding (null start)) nil)
              ((null start) (setq start position))
              ((and padding (null cut)) (setq cut position)))
        (setq position (or (next-property-change position line end) end))))
    (substring-no-properties line (or start 0) (or cut end))))

(defun etaf-video-player-tests--grid (rows)
  "Return the first ROWS visible canvas lines of the player buffer.
The shell puts a header above the canvas, so the canvas is located by the
first line that carries video characters instead of by line number."
  (with-current-buffer "*Video Player*"
    (let* ((lines (split-string (buffer-string) "\n"))
           (start (cl-position-if
                   (lambda (line)
                     (let ((visible (etaf-video-player-tests--visible line)))
                       (string-match-p "[@▀]" visible)))
                   lines)))
      (mapconcat #'etaf-video-player-tests--visible
                 (cl-subseq lines (or start 0) (+ (or start 0) rows))
                 "\n"))))

(defun etaf-video-player-tests--image-cell ()
  "Return non-nil when the buffer publishes one image display cell."
  (with-current-buffer "*Video Player*"
    (let ((text (buffer-string))
          (position 0)
          found)
      (while (and (< position (length text)) (null found))
        (when (imagep (get-text-property position 'display text))
          (setq found t))
        (setq position (or (next-property-change position text)
                           (length text))))
      found)))

(defmacro etaf-video-player-tests--with-graphics (&rest body)
  "Run BODY as if the frame could show images at the frame's scale factor."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'display-graphic-p)
              (lambda (&optional _frame) t)))
     ,@body))

(defmacro etaf-video-player-tests--with-retina (&rest body)
  "Run BODY as on a graphical Retina frame with a device pixel ratio of two."
  (declare (indent 0))
  `(etaf-video-player-tests--with-graphics
     (cl-letf (((symbol-function 'frame-scale-factor)
                (lambda (&optional _frame) 2.0)))
       ,@body)))

(defmacro etaf-video-player-tests--with-fixture (log settings &rest body)
  "Run BODY with the fake decoder fixtures and SETTINGS bound.
LOG receives the recorded ffmpeg invocations.  SETTINGS is a list of ENV=VALUE
strings for the fixtures."
  (declare (indent 2))
  `(let ((process-environment
          (append (cons (concat "FAKE_FFMPEG_LOG=" ,log) ,settings)
                  process-environment))
         (etaf-video-ffmpeg-program etaf-video-player-tests--ffmpeg)
         (etaf-video-ffprobe-program etaf-video-player-tests--ffprobe)
         (etaf-video-ffplay-program etaf-video-player-tests--ffplay))
     ,@body))

(ert-deftest etaf-video-player-tests-image-frames-publish-image-cells ()
  "Image frames are published as one scaled JPEG display per frame.
A graphical frame makes the native Component decode at the canvas pixel
size and publish an image cell instead of characters."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log)))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log
         (list "FAKE_FFMPEG_FRAMES=200" "FAKE_FFMPEG_INTERVAL=0.02"
               "FAKE_FFPROBE_DURATION=4.0" "FAKE_FFPROBE_FPS=50/1")
         (etaf-video-player-tests--with-graphics
           (etaf-video-player-open
            (list :file etaf-video-player-tests--input :columns 16 :rows 4))
           (should (etaf-video-player-tests--wait
                    (lambda () (>= (plist-get (etaf-video-player-tests--state) :presented) 1))))
           (should (eq 'image (plist-get (etaf-video-player-tests--state) :render-mode)))
           (should (etaf-video-player-tests--image-cell))
           (let* ((arguments (car (last (etaf-video-player-tests--runs log))))
                  (scale (cl-find-if (lambda (argument)
                                       (string-prefix-p "scale=" argument))
                                     arguments)))
             (should (equal "mjpeg" (etaf-video-player-tests--argument arguments "-c:v")))
             (should (equal "3" (etaf-video-player-tests--argument arguments "-q:v")))
             (should (string-match-p "\\`scale=[0-9]+:[0-9]+:flags=lanczos\\'" scale)))
           (etaf-video-player-close)))
      (ignore-errors (delete-file log))
      (etaf-video-player-tests--cleanup))))

(defun etaf-video-player-tests--scale-size (log)
  "Return the last recorded `scale=W:H' producer size in LOG as (W . H)."
  (let* ((arguments (car (last (etaf-video-player-tests--runs log))))
         (scale (cl-find-if (lambda (argument)
                              (string-prefix-p "scale=" argument))
                            arguments)))
    (when (and scale
               (string-match "\\`scale=\\([0-9]+\\):\\([0-9]+\\)" scale))
      (cons (string-to-number (match-string 1 scale))
            (string-to-number (match-string 2 scale))))))

(ert-deftest etaf-video-player-tests-retina-frames-scale-by-device-pixel-ratio ()
  "Retina frames are produced at twice the logical canvas.
The producer receives device-resolution pixels and the image is drawn back
down at one over the ratio, so the window system never upscales the picture."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log))
        (columns 16)
        (rows 4)
        logical)
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log
         (list "FAKE_FFMPEG_FRAMES=200" "FAKE_FFMPEG_INTERVAL=0.02"
               "FAKE_FFPROBE_DURATION=4.0" "FAKE_FFPROBE_FPS=50/1")
         ;; The same environment without the Retina factor is the baseline.
         (etaf-video-player-tests--with-graphics
           (etaf-video-player-open
            (list :file etaf-video-player-tests--input
                  :columns columns :rows rows))
           (should (etaf-video-player-tests--wait
                    (lambda () (etaf-video-player-tests--scale-size log))))
           (setq logical (etaf-video-player-tests--scale-size log))
           (etaf-video-player-close))
         (etaf-video-player-tests--with-retina
           (etaf-video-player-open
            (list :file etaf-video-player-tests--input
                  :columns columns :rows rows))
           (should (etaf-video-player-tests--wait
                    (lambda ()
                      (let ((size (etaf-video-player-tests--scale-size log)))
                        (and size
                             (= (car size) (* 2 (car logical)))
                             (= (cdr size) (* 2 (cdr logical))))))))
           (etaf-video-player-close)))
      (ignore-errors (delete-file log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-falls-back-to-ascii-on-terminal ()
  "Without a graphical frame the player falls back to a density ramp.
The requested mode stays `image' while the effective render mode and the
decoded format follow the canvas that is actually available."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log))
        (columns 16)
        (rows 4))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log
         (list "FAKE_FFMPEG_PATTERN=columns" "FAKE_FFMPEG_FRAMES=200"
               "FAKE_FFMPEG_INTERVAL=0.02"
               "FAKE_FFPROBE_DURATION=4.0" "FAKE_FFPROBE_FPS=50/1")
         (etaf-video-player-open
          (list :file etaf-video-player-tests--input
                :columns columns :rows rows))
         (should (etaf-video-player-tests--wait
                  (lambda () (>= (plist-get (etaf-video-player-tests--state) :presented) 1))))
         (should (eq 'image (plist-get (etaf-video-player-tests--state) :mode)))
         (should (eq 'ascii (plist-get (etaf-video-player-tests--state) :render-mode)))
         (let* ((ramp etaf-video-density-ramp)
                (last (1- (length ramp)))
                (expected (mapconcat
                           (lambda (_row)
                             (apply #'string
                                    (cl-loop for x below columns
                                             for value = (floor (* x 255) (1- columns))
                                             for index = (floor (+ (* value last) 127) 255)
                                             collect (aref ramp index))))
                           (number-sequence 1 rows) "\n")))
           (should (equal expected (etaf-video-player-tests--grid rows))))
         (should (equal "gray"
                        (etaf-video-player-tests--argument
                         (car (last (etaf-video-player-tests--runs log))) "-pix_fmt")))
         (etaf-video-player-close))
      (ignore-errors (delete-file log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-audio-sidecar-follows-playback ()
  "Audio playback runs one ffplay sidecar while playing and releases it.
A source that reports an audio stream starts the sidecar with the documented
arguments; pausing terminates it, and turning sound off keeps it stopped."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log))
        (audio-log (etaf-video-player-tests--log)))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log (list "FAKE_FFMPEG_FRAMES=400" "FAKE_FFMPEG_INTERVAL=0.02"
                   "FAKE_FFPROBE_AUDIO=1"
                   (concat "FAKE_FFPLAY_LOG=" audio-log))
         (etaf-video-player-open
          (list :file etaf-video-player-tests--input :columns 8 :rows 2))
         (should (etaf-video-player-tests--wait
                  (lambda () (etaf-video-player-tests--ffplay-pids audio-log))))
         (let ((arguments (etaf-video-player-tests--ffplay-arguments audio-log)))
           (should (member "-nodisp" arguments))
           (should (member "-autoexit" arguments))
           (should (equal "100" (etaf-video-player-tests--argument arguments "-volume"))))
         ;; Pausing releases the sidecar.
         (let ((pid (car (last (etaf-video-player-tests--ffplay-pids audio-log)))))
           (etaf-video-player-toggle-playback)
           (should (etaf-video-player-tests--wait
                    (lambda () (null (process-attributes pid))))))
         ;; Sound off stays silent when playback resumes.
         (let ((runs (etaf-video-player-tests--ffplay-runs audio-log)))
           (etaf-video-player-set-audio nil)
           (etaf-video-player-toggle-playback)
           (sleep-for 0.2)
           (should (= runs (etaf-video-player-tests--ffplay-runs audio-log))))
         ;; Sound on starts one sidecar again.
         (etaf-video-player-set-audio t)
         (should (etaf-video-player-tests--wait
                  (lambda ()
                    (let ((pid (car (last (etaf-video-player-tests--ffplay-pids audio-log)))))
                      (and pid (process-attributes pid))))))
         (etaf-video-player-close))
      (ignore-errors (delete-file log))
      (ignore-errors (delete-file audio-log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-volume-commands-restart-sidecar ()
  "The volume commands change the level and apply it to the running sound.
The sidecar restarts at the same position with the documented volume."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log))
        (audio-log (etaf-video-player-tests--log)))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log (list "FAKE_FFMPEG_FRAMES=400" "FAKE_FFMPEG_INTERVAL=0.02"
                   "FAKE_FFPROBE_AUDIO=1"
                   (concat "FAKE_FFPLAY_LOG=" audio-log))
         (etaf-video-player-open
          (list :file etaf-video-player-tests--input :columns 8 :rows 2
                :volume 30))
         (should (= 30 (plist-get (etaf-video-player-tests--state) :volume)))
         (should (etaf-video-player-tests--wait
                  (lambda () (etaf-video-player-tests--ffplay-pids audio-log))))
         (let ((window (get-buffer-window "*Video Player*" t)))
           (should window)
           (with-selected-window window
             (execute-kbd-macro (kbd "]"))))
         (should (= 40 (plist-get (etaf-video-player-tests--state) :volume)))
         (should (etaf-video-player-tests--wait
                  (lambda ()
                    (equal "40"
                           (etaf-video-player-tests--argument
                            (etaf-video-player-tests--ffplay-arguments audio-log)
                            "-volume")))))
         (with-selected-window (get-buffer-window "*Video Player*" t)
           (execute-kbd-macro (kbd "[")))
         (should (= 30 (plist-get (etaf-video-player-tests--state) :volume)))
         (should-error (etaf-video-player-set-volume 101) :type 'user-error)
         (etaf-video-player-close))
      (ignore-errors (delete-file log))
      (ignore-errors (delete-file audio-log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-controls-pause-step-seek-speed ()
  "Pause, step, seek and speed keep the reported state honest.
A paused position freezes, a step presents exactly one more frame, and the
next producer starts with the documented seek and read-rate arguments."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log)))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log (list "FAKE_FFMPEG_FRAMES=400" "FAKE_FFMPEG_INTERVAL=0.02"
                   "FAKE_FFPROBE_DURATION=8.0" "FAKE_FFPROBE_FPS=50/1")
         (etaf-video-player-open
          (list :file etaf-video-player-tests--input :columns 16 :rows 4))
         (should (etaf-video-player-tests--wait
                  (lambda () (>= (plist-get (etaf-video-player-tests--state) :presented) 1))))
         (etaf-video-player-toggle-playback)
         (should-not (plist-get (etaf-video-player-tests--state) :playing))
         (let ((paused (plist-get (etaf-video-player-tests--state) :position))
               (presented (plist-get (etaf-video-player-tests--state) :presented)))
           (sleep-for 0.15)
           (should (= paused (plist-get (etaf-video-player-tests--state) :position)))
           (etaf-video-player-step)
           (should (etaf-video-player-tests--wait
                    (lambda ()
                      (> (plist-get (etaf-video-player-tests--state) :presented)
                         presented))))
           (should-not (plist-get (etaf-video-player-tests--state) :playing)))
         (etaf-video-player-seek 1.0)
         (should (= 1.0 (plist-get (etaf-video-player-tests--state) :position)))
         (etaf-video-player-toggle-playback)
         (should (plist-get (etaf-video-player-tests--state) :playing))
         (should (etaf-video-player-tests--wait
                  (lambda ()
                    (equal "1.0"
                           (etaf-video-player-tests--argument
                            (car (last (etaf-video-player-tests--runs log))) "-ss")))
                  3))
         (etaf-video-player-set-speed 2)
         (should (= 2 (plist-get (etaf-video-player-tests--state) :speed)))
         (should (etaf-video-player-tests--wait
                  (lambda ()
                    (equal "2"
                           (etaf-video-player-tests--argument
                            (car (last (etaf-video-player-tests--runs log))) "-readrate")))
                  3))
         (etaf-video-player-toggle-playback))
      (ignore-errors (delete-file log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-finishes-and-restarts ()
  "A producer that runs out of frames ends the player and keeps its picture.
Toggling playback afterwards restarts from the beginning."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log)))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log (list "FAKE_FFMPEG_FRAMES=2" "FAKE_FFMPEG_INTERVAL=0.01"
                   "FAKE_FFPROBE_DURATION=1.0" "FAKE_FFPROBE_FPS=50/1")
         (etaf-video-player-open
          (list :file etaf-video-player-tests--input :columns 8 :rows 2))
         (should (etaf-video-player-tests--wait
                  (lambda () (plist-get (etaf-video-player-tests--state) :ended))))
         (should-not (plist-get (etaf-video-player-tests--state) :playing))
         (etaf-video-player-toggle-playback)
         (should (plist-get (etaf-video-player-tests--state) :playing))
         (should-not (plist-get (etaf-video-player-tests--state) :ended))
         (etaf-video-player-close))
      (ignore-errors (delete-file log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-streams-http-url ()
  "An HTTP(S) source reaches ffmpeg as a reconnecting stream.
A non-HTTP scheme is rejected before any process starts."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log)))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log (list "FAKE_FFMPEG_FRAMES=40" "FAKE_FFMPEG_INTERVAL=0.02"
                   "FAKE_FFPROBE_DURATION=4.0" "FAKE_FFPROBE_FPS=50/1")
         (etaf-video-player-open-url "https://example.invalid/video.mp4")
         (should (etaf-video-player-tests--wait
                  (lambda () (>= (plist-get (etaf-video-player-tests--state) :presented) 1))))
         (should (equal "https://example.invalid/video.mp4"
                        (plist-get (etaf-video-player-tests--state) :source)))
         (let ((arguments (car (last (etaf-video-player-tests--runs log)))))
           (should (member "https://example.invalid/video.mp4" arguments))
           (should (equal "1" (etaf-video-player-tests--argument arguments "-reconnect"))))
         (should-error (etaf-video-player-open-url "ftp://example.invalid/v.mp4")
                       :type 'user-error)
         (etaf-video-player-close))
      (ignore-errors (delete-file log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-rejects-invalid-sources ()
  "Invalid sources and a missing ffmpeg fail before anything is left behind.
Every rejection signals `user-error', the state API refuses a foreign buffer,
and no application buffer survives a failed open."
  (etaf-video-player-tests--cleanup)
  (should-error (etaf-video-player-open 42) :type 'user-error)
  (should-error (etaf-video-player-open '(:file "/definitely/missing.mp4"))
                :type 'user-error)
  (should-error (etaf-video-player-open '(:file)) :type 'user-error)
  (let ((etaf-video-ffmpeg-program "etaf-video-player-missing-ffmpeg")
        (etaf-video-ffprobe-program "etaf-video-player-missing-ffprobe"))
    (should-error (etaf-video-player-open '(:demo :columns 8 :rows 3))
                  :type 'user-error))
  (should-not (get-buffer "*Video Player*"))
  (with-temp-buffer
    (should-error (etaf-video-player-state) :type 'user-error))
  (etaf-video-player-tests--cleanup))

(ert-deftest etaf-video-player-tests-documented-keys-reach-player ()
  "The documented keys drive the player instead of the renderer's own map.
Every binding is exercised through the command loop; closing with `q' leaves
no buffer behind."
  (etaf-video-player-tests--cleanup)
  (let ((log (etaf-video-player-tests--log)))
    (unwind-protect
        (etaf-video-player-tests--with-fixture
         log (list "FAKE_FFMPEG_FRAMES=400" "FAKE_FFMPEG_INTERVAL=0.02"
                   "FAKE_FFPROBE_DURATION=8.0" "FAKE_FFPROBE_FPS=50/1")
         (etaf-video-player-open
          (list :file etaf-video-player-tests--input :columns 16 :rows 4))
         (should (etaf-video-player-tests--wait
                  (lambda () (>= (plist-get (etaf-video-player-tests--state) :presented) 1))))
         (with-current-buffer "*Video Player*"
           (execute-kbd-macro (kbd "SPC")))
         (should-not (plist-get (etaf-video-player-tests--state) :playing))
         (with-current-buffer "*Video Player*"
           (execute-kbd-macro (kbd "a")))
         (should-not (plist-get (etaf-video-player-tests--state) :audio))
         (let ((presented (plist-get (etaf-video-player-tests--state) :presented)))
           (with-current-buffer "*Video Player*"
             (execute-kbd-macro (kbd "n")))
           (should (etaf-video-player-tests--wait
                    (lambda ()
                      (> (plist-get (etaf-video-player-tests--state) :presented)
                         presented)))))
         (with-current-buffer "*Video Player*"
           (execute-kbd-macro (kbd "SPC")))
         (should (plist-get (etaf-video-player-tests--state) :playing))
         (with-current-buffer "*Video Player*"
           (execute-kbd-macro (kbd "q")))
         (should-not (get-buffer "*Video Player*")))
      (ignore-errors (delete-file log))
      (etaf-video-player-tests--cleanup))))

(ert-deftest etaf-video-player-tests-plays-demo-with-real-ffmpeg ()
  "The built-in demo plays through a real ffmpeg when one is installed.
This scenario is skipped on machines without ffmpeg; the fixture scenarios
above still cover the full public path there."
  (skip-unless (executable-find "ffmpeg"))
  (etaf-video-player-tests--cleanup)
  (unwind-protect
      (progn
        (etaf-video-player-demo)
        (etaf-video-player-set-grid 48 14)
        (should (etaf-video-player-tests--wait
                 (lambda () (>= (plist-get (etaf-video-player-tests--state) :presented) 2))
                 10))
        (should (= 30 (plist-get (etaf-video-player-tests--state) :source-fps)))
        (should (equal 640 (plist-get (etaf-video-player-tests--state) :source-width))))
    (etaf-video-player-tests--cleanup)))

(provide 'etaf-video-player-tests)
;;; etaf-video-player-tests.el ends here
