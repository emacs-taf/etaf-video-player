;;; etaf-video-player-theme.el --- Palette and ETAF UI theme for etaf-video-player -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; The player renders its own dark surface instead of borrowing the user's
;; Emacs theme, so it looks the same in every session.  `etaf-video-player-color'
;; is the palette lookup used by the View; `etaf-video-player-theme-defaults'
;; projects the same palette onto the ETAF UI token contract consumed by
;; etaf-ui Components (buttons, ranges, labels, dividers).

;;; Code:

(require 'etaf)

(defconst etaf-video-player--palette
  '(:bg "#0B0D10" :panel "#141821" :panel2 "#1B2130" :line "#2A3242"
    :ink "#E9ECF1" :muted "#98A0AC" :dim "#6A7280"
    :accent "#5B8DEF" :accent-soft "#1A2740"
    :track "#232C3B" :playing "#5B8DEF" :ok "#4FB477" :danger "#FF7A7A")
  "The player's dark palette, keyed by keyword.")

(defun etaf-video-player-color (key)
  "Return the player palette color named KEY.
An unknown KEY signals an error instead of returning a fallback, because a
typo would otherwise paint an invisible surface."
  (or (plist-get etaf-video-player--palette key)
      (error "Unknown video player color: %S" key)))

(defun etaf-video-player-theme-defaults ()
  "Return the ETAF UI token plist for the player's dark surface.
The application passes the result to `etaf-theme-provide' so shared etaf-ui
Components use the same colors as the player's own View."
  (let ((accent (etaf-video-player-color :accent)))
    (list :ui-fg (etaf-video-player-color :ink)
          :ui-bg (etaf-video-player-color :bg)
          :ui-border (etaf-video-player-color :line)
          :ui-muted-fg (etaf-video-player-color :muted)
          :ui-disabled-fg (etaf-video-player-color :dim)
          :ui-disabled-bg (etaf-video-player-color :panel)
          :ui-disabled-border (etaf-video-player-color :line)
          :ui-accent accent
          :ui-accent-fg "#FFFFFF"
          :ui-accent-soft-bg (etaf-video-player-color :accent-soft)
          :ui-button-primary-fg "#FFFFFF"
          :ui-button-primary-bg accent
          :ui-button-secondary-fg accent
          :ui-button-secondary-bg (etaf-video-player-color :accent-soft)
          :ui-button-ghost-fg (etaf-video-player-color :muted)
          :ui-button-ghost-bg (etaf-video-player-color :panel)
          :ui-range-track (etaf-video-player-color :track)
          :ui-range-fill accent
          :ui-success-fg (etaf-video-player-color :ok)
          :ui-success-bg (etaf-video-player-color :panel2)
          :ui-success-border (etaf-video-player-color :line)
          :ui-danger-fg (etaf-video-player-color :danger)
          :ui-danger-bg (etaf-video-player-color :panel2)
          :ui-danger-border (etaf-video-player-color :line)
          :ui-warning-fg (etaf-video-player-color :muted)
          :ui-warning-bg (etaf-video-player-color :panel2)
          :ui-warning-border (etaf-video-player-color :line))))

(provide 'etaf-video-player-theme)
;;; etaf-video-player-theme.el ends here
