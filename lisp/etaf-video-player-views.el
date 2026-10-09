;;; etaf-video-player-views.el --- Video player presentation -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; The shell is one ETAF layout: a column that stretches to the viewport,
;; with a responsive body row that adds the playlist and the details pane
;; when the published viewport is wide enough.  Panes flow in their parent
;; instead of being positioned at character offsets, and the canvas Component
;; sits in a stage Host the application measures once per layout change.
;; Playback sources are read by their leaf Host bindings, never by the
;; shell's structural render.

;;; Code:
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-video-player-theme)

(defconst etaf-video-player--sidebar-width '(ch 30)
  "Width of the playlist column.")
(defconst etaf-video-player--sidebar-min-pixels 700
  "Published viewport width from which the playlist column is shown.")
(defconst etaf-video-player--aside-width '(ch 28)
  "Width of the details column.")
(defconst etaf-video-player--aside-min-pixels 1050
  "Published viewport width from which the details column is shown.")
(defconst etaf-video-player--bar-rows 6
  "Rows reserved for the transport panel.")
(defconst etaf-video-player--chrome-rows 10
  "Non-canvas rows: the shell pads, header, transport and footer.")

(defconst etaf-video-player--stage-ref 'etaf-video-player-stage
  "Host reference of the video stage, measured after each layout change.")

(defun etaf-video-player--stage-inset (stage-left stage-pixels columns)
  "Return the inline inset of a COLUMNS-wide canvas centered in the stage.
STAGE-LEFT and STAGE-PIXELS come from the measured stage Host, so the inset is
a renderer fact rather than a window-chrome estimate."
  (if (and (numberp stage-pixels) (> stage-pixels 0))
      `(calc (+ (px ,(or stage-left 0))
                (/ (- (px ,stage-pixels) (ch ,columns)) 2)))
    '(px 0)))

(defun etaf-video-player--view-value (value)
  "Read a display VALUE or source inside its consuming Host."
  (if (or (etaf-ref-p value) (etaf-computed-p value)) (etaf-value value) value))

(defun etaf-video-player--border (_side color)
  "Return a one-pixel solid border in COLOR."
  (list '(px 1) 'solid color))

(defun etaf-video-player--hover-surface ()
  "Return the shared hover surface."
  (list :background-color (etaf-video-player-color :hover)))

(etaf-define-component etaf-video-player--view-header
    (&key title status-ref status compact position left top width height)
  "Render the title and retained status in one stretched header row."
  :view
  (flex :position (or position 'static) :left (or left '(px 0)) :top (or top '(lh 0))
        :width (or width 'stretch) :height (or height '(lh 1)) :align-items 'center
        :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 2))
        :background-color (etaf-video-player-color :surface)
    (etaf-ui-icon :if (not compact) :name 'disc :set 'svg :size 0.9 :min-width 2
                  :color (etaf-video-player-color :accent))
    (box :if (not compact) :height '(lh 1) :font-weight 'bold
      (text "ETAF 视频播放器"))
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0)
         :height '(lh 1) :overflow 'hidden
      (text (expr title)))
    (box :width '(ch 32) :height '(lh 1) :text-align 'right :overflow 'hidden
         :font-size 16 :color (etaf-video-player-color :muted)
      (text :ref status-ref :id (symbol-name status-ref)
        (expr (etaf-video-player--view-value status))))))

(etaf-define-component etaf-video-player--view-track-row
    (&key position title subtitle duration active on-press)
  "Render one two-line playlist item with a stable full-row target."
  :view
  (flex :position 'relative :width 'stretch :height '(lh 2)
        :align-items 'center :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
        :role 'button :tab-index 0 :ref (intern (format "video-track-%d" position))
        :help-echo (format "播放第 %d 个：%s" (1+ position) title)
        :on-press on-press
        :hover-style (unless active (etaf-video-player--hover-surface))
        :background-color (etaf-video-player-color (if active :accent-soft :surface))
    (box :if active :position 'absolute :left '(px 0) :top '(lh 0)
         :width '(px 2) :height '(lh 2) :background-color (etaf-video-player-color :accent))
    (box :width '(ch 2) :height '(lh 1) :text-align 'center
         :color (etaf-video-player-color (if active :accent :dim))
      (text (expr (number-to-string (1+ position)))))
    (flex :flex-direction 'column :height '(lh 2) :min-width '(ch 0)
          :flex-grow 1 :flex-basis '(ch 0)
      (box :height '(lh 1) :overflow 'hidden :font-weight (if active 'bold 'normal)
           :color (etaf-video-player-color (if active :accent :ink))
        (text (expr title)))
      (box :height '(lh 1) :overflow 'hidden :font-size 16
           :color (etaf-video-player-color :muted)
        (text (expr subtitle))))
    (box :width '(ch 5) :height '(lh 1) :text-align 'right :font-size 16
         :color (etaf-video-player-color :muted)
      (text (expr duration)))))

(etaf-define-component etaf-video-player--view-playlist
    (&key count entries active summary on-press position left top width height)
  "Render the playlist column inside the responsive body row."
  :view
  (flex :position (or position 'static) :left (or left '(px 0)) :top (or top '(lh 0))
        :width (or width etaf-video-player--sidebar-width) :height (or height 'stretch)
        :flex-direction 'column :overflow 'hidden :padding '((lh 1) (ch 1))
        :background-color (etaf-video-player-color :surface)
    (flex :height '(lh 1) :gap '((lh 0) (ch 1)) :align-items 'center
      (etaf-ui-icon :name 'list :set 'svg :size 0.9 :min-width 2
                    :color (etaf-video-player-color :muted))
      (box :height '(lh 1) :font-weight 'bold (text "播放列表"))
      (box :height '(lh 1) :color (etaf-video-player-color :muted)
        (text (expr (number-to-string count)))))
    (box :height '(lh 1))
    (flex :flex-direction 'column :width 'stretch :flex-shrink 0
      (etaf-video-player--view-track-row :for (entry entries) :key (car entry)
       :position (car entry) :title (plist-get (cdr entry) :title)
       :subtitle (plist-get (cdr entry) :subtitle) :duration (plist-get (cdr entry) :duration)
       :active (= (car entry) active) :on-press (lambda () (funcall on-press (car entry)))))
    (box :flex-grow 1 :flex-basis '(lh 0) :min-height '(lh 0))
    (box :height '(lh 1) :font-size 16 :color (etaf-video-player-color :muted)
      (text (expr summary)))))

(etaf-define-component etaf-video-player--view-details
    (&key title source meta speed audio loop shuffle on-toggle-theme
          columns rows ratio fps position left top width height)
  "Render source information and retained playback settings."
  :view
  (flex :position (or position 'static) :left (or left '(px 0)) :top (or top '(lh 0))
        :width (or width etaf-video-player--aside-width) :height (or height 'stretch)
        :flex-direction 'column :overflow 'hidden
        :padding '((lh 1) (ch 1))
        :background-color (etaf-video-player-color :surface)
    (flex :height '(lh 1) :gap '((lh 0) (ch 1))
      (etaf-ui-icon :name 'play :set 'svg :size 0.9 :min-width 2
                    :color (etaf-video-player-color :accent))
      (box :height '(lh 1) :color (etaf-video-player-color :muted) (text "正在播放")))
    (box :height '(lh 1))
    (box :height '(lh 1) :overflow 'hidden :font-weight 'bold (text (expr title)))
    (box :height '(lh 1) :overflow 'hidden :font-size 16
         :color (etaf-video-player-color :muted) (text (expr source)))
    (etaf-divider)
    (box :height '(lh 3)
      (text (expr (mapconcat (lambda (row) (format "%s  %s" (car row) (cdr row))) meta "\n"))))
    (box :height '(lh 1)
      (text (expr (format "速度    %gx" (etaf-video-player--view-value speed)))))
    (box :height '(lh 1)
      (text (expr (format "循环    %s" (pcase (etaf-video-player--view-value loop)
                                          ('all "列表") ('one "单集") (_ "关闭"))))))
    (box :height '(lh 1)
      (text (expr (format "随机    %s" (if (etaf-video-player--view-value shuffle) "开" "关")))))
    (box :height '(lh 1)
      (text (expr (format "声音    %s" (if (etaf-video-player--view-value audio) "开" "关")))))
    (etaf-divider)
    (box :height '(lh 1) :font-weight 'bold :color (etaf-video-player-color :muted)
      (text "画布"))
    (box :height '(lh 1))
    (box :height '(lh 3) :overflow 'hidden :font-size 16
         :color (etaf-video-player-color :muted)
      (text (expr (format "尺寸    %d × %d 单元格\n倍率    %s\n帧率上限 %s"
                          columns rows
                          (if (numberp ratio) (format "%gx (设备像素)" ratio) "自动 (设备像素)")
                          (if fps (format "%d fps" fps) "默认")))))
    (box :flex-grow 1 :flex-basis '(lh 0) :min-height '(lh 0))
    (etaf-button :ref 'video-theme :label "明暗主题" :variant 'ghost
                 :help-echo "切换明暗配色 (T)" :on-press on-toggle-theme)))

(etaf-define-component etaf-video-player--view-control
    (&key icon label help on-press value ref)
  "Compose a shared SVG icon and optional caption at standard line height."
  :view
  (flex :width 'max-content :height '(lh 1) :align-items 'center
        :gap '((lh 0) (ch 1))
    (etaf-ui-toggle-icon :value (or value nil) :off icon :on icon :set 'svg :size 0.9
                         :min-width 3 :color (etaf-video-player-color :muted)
                         :on-color (etaf-video-player-color :accent)
                         :ref ref :help-echo help :on-press on-press)
    (box :if label :height '(lh 1) :font-size 16 :color (etaf-video-player-color :muted)
      (text (expr label)))))

(etaf-define-component etaf-video-player--view-progress
    (&key time-ref time progress progress-fill-ref on-seek)
  "Render a controlled timeline with leaf-bound clock and fill."
  :view
  (flex :position 'relative :width 'stretch :height '(lh 1) :gap '((lh 0) (ch 1)) :align-items 'center
    (box :width '(ch 13) :height '(lh 1) :text-align 'right :font-size 16
         :color (etaf-video-player-color :muted)
      (text :ref time-ref :id (symbol-name time-ref)
        (expr (etaf-video-player--view-value time))))
    (flex :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
      (etaf-range :min 0 :max 100 :value progress :bar-height 45
                  :fill-ref progress-fill-ref :ref 'etaf-video-player-progress
                  :label "播放进度，点击或拖动跳转"
                  :color (etaf-video-player-color :accent)
                  :track-color (etaf-video-player-color :panel3) :on-commit on-seek))))

(etaf-define-component etaf-video-player--view-transport-buttons
    (&key playing on-toggle on-previous on-next on-forward on-backward compact)
  "Keep transport targets stable in both wide and narrow bars."
  :view
  (flex :height '(lh 1) :width 'stretch :align-items 'center :justify-content 'center
        :gap (if compact '((lh 0) (ch 1)) '((lh 0) (ch 3)))
    (etaf-video-player--view-control :icon 'previous :ref 'video-previous
      :help "上一条 (<)" :on-press on-previous)
    (etaf-video-player--view-control :icon 'chevron-left :ref 'video-backward
      :label (unless compact "5s") :help "后退五秒 (b)" :on-press on-backward)
    (box :width '(ch 4) :height '(lh 1) :background-color (etaf-video-player-color :accent)
      (etaf-ui-toggle-icon :value playing :off 'play :on 'pause :set 'svg :size 0.9
                           :min-width 4 :ref 'video-play
                           :color "#FFFFFF" :on-color "#FFFFFF"
                           :help-echo "播放 / 暂停 (SPC)" :on-press on-toggle))
    (etaf-video-player--view-control :icon 'chevron-right :ref 'video-forward
      :label (unless compact "5s") :help "前进五秒 (f)" :on-press on-forward)
    (etaf-video-player--view-control :icon 'next :ref 'video-next
      :help "下一条 (>)" :on-press on-next)))

(etaf-define-component etaf-video-player--view-volume
    (&key audio volume volume-text volume-ref on-toggle-audio on-volume compact)
  "Compose mute, a controlled volume range and its retained percentage."
  :view
  (flex :position 'relative :height '(lh 1) :align-items 'center :justify-content 'end
        :gap '((lh 0) (ch 1))
    (etaf-ui-toggle-icon :value audio :off 'volume-mute :on 'volume
                         :set 'svg :size 0.9 :min-width 3 :ref 'video-audio
                         :color (etaf-video-player-color :muted)
                         :on-color (etaf-video-player-color :muted)
                         :help-echo "声音开关 (a)" :on-press on-toggle-audio)
    (flex :width (if compact '(ch 8) '(ch 12)) :height '(lh 1)
      (etaf-range :min 0 :max 100 :value volume :step 1 :bar-height 45
                  :ref 'etaf-video-player-volume :fill-ref 'video-volume-fill
                  :label "音量，点击或拖动调节"
                  :color (etaf-video-player-color :accent)
                  :track-color (etaf-video-player-color :panel3) :on-commit on-volume))
    (box :width '(ch 4) :height '(lh 1) :text-align 'right :font-size 16
         :color (etaf-video-player-color :muted)
      (text :ref volume-ref :id (symbol-name volume-ref)
        (expr volume-text)))))

(etaf-define-component etaf-video-player--view-transport
    (&key playing-ref title meta time time-ref volume-ref volume-text audio-ref
          progress progress-fill-ref speed loop shuffle volume
          on-toggle on-previous on-next on-forward on-backward on-seek
          on-cycle-speed on-toggle-loop on-toggle-shuffle on-toggle-audio on-volume compact
          position left top width height)
  "Render a fixed-height transport panel with independently retained controls."
  :view
  (box :position (or position 'relative) :left (or left '(px 0)) :top (or top '(lh 0))
       :width (or width 'stretch) :height (or height (list 'lh etaf-video-player--bar-rows))
       :padding '((lh 1) (ch 2)) :background-color (etaf-video-player-color :surface)
       :border-top (etaf-video-player--border 'top (etaf-video-player-color :line))
    (grid :width 'stretch :height '(lh 3)
          :grid-template-columns (if compact '((fr 1) (ch 26)) '((ch 26) (fr 1) (ch 26)))
          :gap '((lh 0) (ch 2)) :align-items 'center
      (box :if (not compact) :height '(lh 2) :overflow 'hidden
        (text :font-weight 'bold (expr title))
        (text :font-size 16 :color (etaf-video-player-color :muted) (expr (concat "\n" meta))))
      (flex :flex-direction 'column :height '(lh 3) :width 'stretch :min-width '(ch 0)
        (etaf-video-player--view-progress :time time :time-ref time-ref :progress progress
          :progress-fill-ref progress-fill-ref :on-seek on-seek)
        (box :height '(lh 1))
        (etaf-video-player--view-transport-buttons :playing playing-ref :compact compact
          :on-toggle on-toggle :on-previous on-previous :on-next on-next
          :on-forward on-forward :on-backward on-backward))
      (flex :flex-direction 'column :height '(lh 3) :width 'stretch
        (etaf-video-player--view-volume :audio audio-ref :volume volume :volume-ref volume-ref
          :volume-text volume-text
          :on-toggle-audio on-toggle-audio :on-volume on-volume :compact compact)
        (box :height '(lh 1))
        (flex :height '(lh 1) :align-items 'center :justify-content 'end
          :gap '((lh 0) (ch 1))
          (etaf-button :ref 'video-speed :variant 'ghost
            :label (format "%gx" (etaf-video-player--view-value speed))
            :help-echo "播放速度 (+ / -)" :on-press on-cycle-speed)
          (etaf-button :ref 'video-loop
            :label (pcase (etaf-video-player--view-value loop) ('all "循环列表") ('one "单集循环") (_ "不循环"))
            :variant (if (eq (etaf-video-player--view-value loop) 'none) 'ghost 'secondary)
            :help-echo "循环方式 (l)" :on-press on-toggle-loop)
          (etaf-video-player--view-control :icon 'shuffle :value shuffle :ref 'video-shuffle
            :help "随机播放 (s)" :on-press on-toggle-shuffle))))))

(etaf-define-component etaf-video-player--view-footer
    (&key hints position left top width height)
  "Render the fixed bottom hint row."
  :view
  (box :position (or position 'static) :left (or left '(px 0)) :top (or top '(lh 0))
       :width (or width 'stretch) :height (or height '(lh 1))
       :text-align 'center :overflow 'hidden :font-size 16
       :background-color (etaf-video-player-color :surface)
       :color (etaf-video-player-color :muted)
    (text (expr hints))))

(provide 'etaf-video-player-views)
;;; etaf-video-player-views.el ends here
