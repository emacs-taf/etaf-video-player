;;; etaf-video-player-theme.el --- Palette and ETAF UI theme for etaf-video-player -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The player renders its own surface instead of borrowing the user's Emacs
;; theme, so it looks the same in every session.  `etaf-video-player-color' is
;; the palette lookup used by the Views; `etaf-video-player-theme-defaults'
;; projects the same palette onto the ETAF UI token contract consumed by
;; etaf-ui Components (buttons, ranges, icons, dividers).  Both palettes share
;; one layout, and the video canvas keeps its own darker stage surface because
;; letterbox bars must never compete with the picture.

;;; Code:

(require 'etaf)

(defgroup etaf-video-player nil
  "Video player built with ETAF and Ebox."
  :group 'applications)

(defconst etaf-video-player--palettes
  '((dark :bg "#0E1013" :surface "#15181D" :panel "#15181D" :panel2 "#1B1F26" :panel3 "#232832"
          :line "#262B34" :ink "#E9ECF1" :muted "#98A0AC" :dim "#6A727E"
          :accent "#5B8DEF" :accent-soft "#1A2436" :hover "#1B1F26"
          :stage "#050607" :playing "#5B8DEF" :gold "#E8B45C" :ok "#4FB477"
          :warn "#E8B45C" :danger "#FF7A7A" :danger-bg "#3A1D22" :info "#6FB4E8")
    (light :bg "#FFFFFF" :surface "#F6F7F9" :panel "#F6F7F9" :panel2 "#EFF1F4" :panel3 "#E4E7EB"
           :line "#E1E4E9" :ink "#1B1F24" :muted "#5C6470" :dim "#8A919C"
           :accent "#2F6FED" :accent-soft "#E8EFFD" :hover "#F0F2F5"
           :stage "#101318" :playing "#2F6FED" :gold "#B07A16" :ok "#2E7D4F"
           :warn "#B07A16" :danger "#C0392B" :danger-bg "#FBE4E2" :info "#2C6FA8"))
  "Palette of every supported appearance, keyed by mode.")

(defcustom etaf-video-player-theme-mode 'dark
  "Appearance used by a new player.
`dark' (default) renders the player's own dark surface; `light' uses the
light palette.  The video canvas keeps its dark stage in both modes.  This is
independent of the active Emacs theme."
  :type '(choice (const :tag "Dark" dark) (const :tag "Light" light))
  :group 'etaf-video-player)

(defun etaf-video-player-color (key &optional mode)
  "Return the palette color named KEY.
MODE defaults to `etaf-video-player-theme-mode'.  An unknown KEY signals an
error instead of returning a fallback, because a typo would otherwise paint
an invisible surface."
  (let* ((mode (if (eq (or mode etaf-video-player-theme-mode) 'light)
                   'light 'dark))
         (palette (cdr (assq mode etaf-video-player--palettes)))
         (color (plist-get palette key)))
    (unless (and (keywordp key) color)
      (error "Unknown video player color: %S" key))
    color))

(defun etaf-video-player-theme-defaults (&optional mode)
  "Return the ETAF UI token plist for MODE.
MODE defaults to `etaf-video-player-theme-mode'.  The application passes the
result to `etaf-theme-provide' so shared etaf-ui Components use the same
colors as the player's own Views."
  (let* ((dark (not (eq (or mode etaf-video-player-theme-mode) 'light)))
         (bg (etaf-video-player-color :bg mode))
         (panel (etaf-video-player-color :panel mode))
         (panel3 (etaf-video-player-color :panel3 mode))
         (ink (etaf-video-player-color :ink mode))
         (line (etaf-video-player-color :line mode))
         (muted (etaf-video-player-color :muted mode))
         (accent (etaf-video-player-color :accent mode))
         (accent-soft (etaf-video-player-color :accent-soft mode))
         (ok (etaf-video-player-color :ok mode))
         (ok-bg (if dark "#17301F" "#E3F3E8"))
         (ok-border (if dark "#2E5C3F" "#A9D8BB"))
         (danger (etaf-video-player-color :danger mode))
         (danger-bg (etaf-video-player-color :danger-bg mode))
         (danger-border (if dark "#7A2A2C" "#E8B4AE"))
         (warn (etaf-video-player-color :warn mode))
         (warn-bg (if dark "#33280F" "#FBF0DA"))
         (warn-border (if dark "#6B5423" "#E0C48A"))
         (info (etaf-video-player-color :info mode))
         (info-bg (if dark "#14232F" "#E4F0FA"))
         (info-border (if dark "#2C4E66" "#A8CBE6")))
    (list
     :ink ink :paper bg :panel panel :line line :muted muted
     :accent accent :accent-soft accent-soft
     :ui-fg ink :ui-bg bg :ui-border line :ui-muted-fg muted
     :ui-disabled-fg muted :ui-disabled-bg panel :ui-disabled-border line
     :ui-accent accent :ui-accent-fg "#FFFFFF" :ui-accent-soft-bg accent-soft
     :ui-button-primary-fg "#FFFFFF" :ui-button-primary-bg accent
     :ui-button-secondary-fg accent :ui-button-secondary-bg accent-soft
     :ui-button-ghost-fg muted
     :ui-success-fg ok :ui-success-bg ok-bg :ui-success-border ok-border
     :ui-danger-fg danger :ui-danger-bg danger-bg :ui-danger-border danger-border
     :ui-warning-fg warn :ui-warning-bg warn-bg :ui-warning-border warn-border
     :ui-info-fg info :ui-info-bg info-bg :ui-info-border info-border
     :ui-panel-fg ink :ui-panel-bg panel :ui-panel-border line
     :ui-divider-bg line :ui-progress-track panel3
     :ui-range-track panel3 :ui-range-fill accent
     :ui-table-border line :ui-table-selected-fg accent
     :ui-table-selected-bg accent-soft
     :ui-shell-bg panel :ui-shell-fg ink :ui-shell-muted-fg muted
     :ui-shell-item-fg muted :ui-shell-item-minimized-fg muted
     :ui-window-bg bg :ui-window-fg ink :ui-window-border line
     :ui-window-title-bg panel :ui-window-title-fg muted
     :ui-window-title-active-fg ink
     :ui-picker-item-bg panel :ui-picker-item-fg ink
     :ui-picker-item-muted-fg muted
     :ui-pagination-muted-fg muted
     :ui-data-grid-error-fg danger
     :ui-checkbox-enabled-fg ink :ui-checkbox-disabled-fg muted)))

(provide 'etaf-video-player-theme)
;;; etaf-video-player-theme.el ends here
