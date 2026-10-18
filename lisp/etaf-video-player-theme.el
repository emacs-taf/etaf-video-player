;;; etaf-video-player-theme.el --- Palette and ETAF UI theme for etaf-video-player -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The player renders its own surface instead of borrowing the user's Emacs
;; theme, so it looks the same in every session.  `etaf-video-player-color' is
;; the palette lookup used by the Views; `etaf-video-player-theme-defaults'
;; projects the same palette onto the ETAF UI token contract consumed by
;; etaf-ui Components (buttons, ranges, icons, dividers).  Both appearances
;; share one layout and paint four depth steps -- page, card, raised surface
;; and control track -- so panes stay visually separated in either mode.  The
;; video stage paints near-black in the dark appearance (one immersive
;; surface around the picture) and a shallow grey in the light one, where a
;; full dark block would weigh the whole column down; the picture keeps its
;; own letterbox either way.

;;; Code:

(require 'etaf)

(defgroup etaf-video-player nil
  "Video player built with ETAF and Ebox."
  :group 'applications)

(defconst etaf-video-player--palettes
  '((dark
     ;; depth: page < card < raised < track
     :bg "#191a1c" :surface "#202225" :panel2 "#25272b" :panel3 "#2b2e33"
     :hover "#2a2d31" :line "#303338"
     :ink "#E9EDF4" :muted "#9AA4B4" :dim "#6B7484"
     :accent "#5B8DEF" :accent-soft "#18243C"
     :stage "#000000" :playing "#5B8DEF"
     :gold "#E8B45C" :ok "#4FB477" :warn "#E8B45C"
     :danger "#FF7A7A" :danger-bg "#3A1D22" :info "#6FB4E8")
    (light
     ;; page grey, cards white, one grey step below and a control track
     :bg "#ECEEF2" :surface "#FFFFFF" :panel2 "#F5F6F9" :panel3 "#E3E6EC"
     :hover "#F0F2F6" :line "#DADEE5"
     :ink "#171A20" :muted "#5B6472" :dim "#8B93A0"
     :accent "#2F6BE8" :accent-soft "#E6EDFC"
     :stage "#E2E5EB" :playing "#2F6BE8"
     :gold "#B07A16" :ok "#2E7D4F" :warn "#B07A16"
     :danger "#C0392B" :danger-bg "#FBE4E2" :info "#2C6FA8"))
  "Palette of every supported appearance, keyed by mode.
The four depth keys are shared by both appearances: `:bg' is the page shell,
`:surface' is a pane or card, `:panel2' is a raised surface such as the header
or the footer, and `:panel3' is a control track and disabled fill.")

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
         (surface (etaf-video-player-color :surface mode))
         (panel2 (etaf-video-player-color :panel2 mode))
         (panel3 (etaf-video-player-color :panel3 mode))
         (ink (etaf-video-player-color :ink mode))
         (line (etaf-video-player-color :line mode))
         (muted (etaf-video-player-color :muted mode))
         (dim (etaf-video-player-color :dim mode))
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
     :ink ink :paper bg :panel surface :line line :muted muted
     :accent accent :accent-soft accent-soft
     :ui-fg ink :ui-bg bg :ui-border line :ui-muted-fg muted
     :ui-disabled-fg dim :ui-disabled-bg panel3 :ui-disabled-border line
     :ui-accent accent :ui-accent-fg "#FFFFFF" :ui-accent-soft-bg accent-soft
     :ui-button-primary-fg "#FFFFFF" :ui-button-primary-bg accent
     :ui-button-secondary-fg accent :ui-button-secondary-bg accent-soft
     :ui-button-ghost-fg muted
     :ui-success-fg ok :ui-success-bg ok-bg :ui-success-border ok-border
     :ui-danger-fg danger :ui-danger-bg danger-bg :ui-danger-border danger-border
     :ui-warning-fg warn :ui-warning-bg warn-bg :ui-warning-border warn-border
     :ui-info-fg info :ui-info-bg info-bg :ui-info-border info-border
     :ui-panel-fg ink :ui-panel-bg surface :ui-panel-border line
     :ui-divider-bg line :ui-progress-track panel3
     :ui-range-track panel3 :ui-range-fill accent
     :ui-table-border line :ui-table-selected-fg accent
     :ui-table-selected-bg accent-soft
     :ui-shell-bg panel2 :ui-shell-fg ink :ui-shell-muted-fg muted
     :ui-shell-item-fg muted :ui-shell-item-minimized-fg dim
     :ui-window-bg bg :ui-window-fg ink :ui-window-border line
     :ui-window-title-bg panel2 :ui-window-title-fg muted
     :ui-window-title-active-fg ink
     :ui-picker-item-bg surface :ui-picker-item-fg ink
     :ui-picker-item-muted-fg muted
     :ui-pagination-muted-fg muted
     :ui-data-grid-error-fg danger
     :ui-checkbox-enabled-fg ink :ui-checkbox-disabled-fg dim)))

(provide 'etaf-video-player-theme)
;;; etaf-video-player-theme.el ends here
