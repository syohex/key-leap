;;; key-leap.el --- Leap between lines by typing keywords
;;; key-leap.el

;; Copyright (C) 2015  Martin Rykfors

;; Author: Martin Rykfors <martinrykfors@gmail.com>
;; Version: 0.2.1
;; Package-Requires: ((emacs "24.1"))
;; Keywords: point, location

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; key-leap-mode allows you to quickly jump to any visible line in a
;; window.  When key-leap-mode is enabled, it will populate the margin
;; of every line with an unique keyword.  By calling the
;; interactive command `key-leap-start-matching' the keywords become
;; active.  Typing the keyword of a line in this state will move the
;; point to the beginning of that line.

;; You can change the way key-leap-mode generates its keys by setting
;; the variable `key-leap-key-strings'.  This is a list of strings
;; that specify what chars to use for each position in the keys.
;; For example, adding this to your init file
;;
;; (setq key-leap-key-chars '("htn" "ao" "ht"))
;;
;; will make key-leap-mode generate and use the following keys:
;; hah hat hoh hot tah tat toh tot nah nat noh not

;; You are not restricted to just three-letter keywords.  By providing
;; 4 different strings, for instance, key-leap will use 4 letters for
;; every keyword.

;; You should provide a large enough number of different
;; characters for key-leap to use.  The number of combinations of
;; characters should be bigger than the number of possible visible
;; lines for your setup, but not too much bigger than that.

;; By default, key-leap-mode will generate 125 keywords from the
;; home-row of a qwerty keyboard layout, in a right-left-right fashion.

;; After leaping to a new line with `key-leap-start-matching', the
;; hook `key-leap-after-leap-hook' will be run.
;; Adding the following, for instance
;;
;; (add-hook 'key-leap-after-leap-hook 'back-to-indentation)
;;
;; will move the point to the first non-whitespace character on the
;; line after leaping.

;; When set to nil, `key-leap-upcase-active' will not make the active
;; parts of the keys upper-cased.  The default is t.

;; The faces for the active and inactive parts of the keys are
;; specified by the faces `key-leap-active' and `key-leap-inactive'
;; respectively.

(require 'linum)
(require 'cl)

;;; Code:

(defgroup key-leap nil
  "Leap to any visible line by typing a keyword.")

(defcustom key-leap-upcase-active t
  "If set to t, `key-leap-mode' will make active characters of the keys upper-cased when waiting for the key input."
  :group 'key-leap
  :type 'boolean
  :version "0.1.0")

(defface key-leap-inactive
  '((t :inherit (linum default)))
  "Face to use for the inactive parts of the keys."
  :group 'key-leap
  :version "0.1.0")

(defface key-leap-active
  '((t :inherit (linum default) :foreground "#FF0000"))
  "Face to use for the parts of the keys that are still being matched."
  :group 'key-leap
  :version "0.1.0")

(defcustom key-leap-key-strings '("hjkl;" "gfdsa" "hjkl;")
  "A list of strings from which the key-leap keys are constructed.  The first list specifies the characters to use for the first position of every key and so on."
  :group 'key-leap
  :type '(repeat string)
  :version "0.1.0")

(defvar key-leap--key-chars)

(defcustom key-leap-after-leap-hook nil
  "Hook that runs after key-leap-mode has jumped to a new line."
  :type 'hook
  :group 'key-leap
  :version "0.2.0")

(defun key-leap--tree-size (level)
  (reduce '* (mapcar 'length key-leap--key-chars) :start level))

(defun key-leap--tree-sizes ()
  (mapcar 'key-leap--tree-size (number-sequence 1 (length key-leap--key-chars))))

(defun key-leap--coords-from-index (index)
  (mapcar (lambda (level)
            (/ (mod index (key-leap--tree-size (- level 1))) (key-leap--tree-size level)))
          (number-sequence 1 (length key-leap--key-chars))))

(defun key-leap--index-from-key-string (key-string)
  (let* ((char-list (string-to-list key-string))
         (coordinates (mapcar* 'position char-list key-leap--key-chars)))
    (reduce '+ (mapcar* '* (key-leap--tree-sizes) coordinates))))

(defun key-leap--coords-to-string (coords)
  (apply 'string (mapcar* 'nth coords key-leap--key-chars)))

(setq key-leap--all-keys)
(setq key-leap--num-keys)

(defun key-leap--listify-string (s)
  (let ((len (length s)))
    (mapcar
     (lambda (n)
       (string-to-char (substring s n len)))
     (number-sequence 0 (- len 1)))))

(defun key-leap--cache-keys ()
  (setq key-leap--key-chars (mapcar 'key-leap--listify-string key-leap-key-strings))
  (setq key-leap--all-keys (apply 'vector (mapcar (lambda (n)
                                             (key-leap--coords-to-string (key-leap--coords-from-index n)))
                                           (number-sequence 0 (- (key-leap--tree-size 0) 1)))))
  (setq key-leap--num-keys (length key-leap--all-keys)))

(defvar key-leap--current-key "*")
(make-variable-buffer-local 'key-leap--current-key)

(defun key-leap--leap-to-current-key ()
  (goto-char (window-start))
  (forward-visible-line (key-leap--index-from-key-string key-leap--current-key))
  (run-hooks 'key-leap-after-leap-hook))

(defun key-leap--color-substring (str)
  (if (string-match (concat "\\(^" key-leap--current-key "\\)\\(.*\\)") str)
       (concat
          (propertize (match-string 1 str) 'face 'key-leap-inactive)
          (let* ((active-str (match-string 2 str))
                 (cased-str (if key-leap-upcase-active (upcase active-str) active-str)))
            (propertize cased-str 'face 'key-leap-active)))
    (propertize str 'face 'key-leap-inactive)))

(defvar key-leap--buffer-overlays nil "List of overlays present in the current buffer")
(make-variable-buffer-local 'key-leap--buffer-overlays)

(defun key-leap--place-overlay (win key-index)
  (let* ((ol (make-overlay (point) (+ 1 (point))))
         (str (elt key-leap--all-keys key-index))
         (colored-string (key-leap--color-substring str)))
    (overlay-put ol 'window win)
    (overlay-put ol 'before-string
                 (propertize " " 'display`((margin left-margin) ,colored-string)))
    (push ol key-leap--buffer-overlays)))

(defun key-leap--delete-overlays ()
  (dolist (ol key-leap--buffer-overlays)
    (delete-overlay ol))
  (setq key-leap--buffer-overlays nil))

(defun key-leap--update-margin-keys (win)
  (set-window-margins win (length key-leap--key-chars))
  (let ((start (line-number-at-pos (window-start win)))
        (limit (- key-leap--num-keys 1))
        (continue t))
    (save-excursion
      (goto-char (window-start win))
      (unless (bolp) (forward-visible-line 1))
      (let ((line (line-number-at-pos)))
        (while (and continue (<= (- line start) limit))
          (when (or (not (eobp))
                    (and (eobp) (= (point) (line-beginning-position))))
            (key-leap--place-overlay win (- line start)))
          (setq line (+ 1 line))
          (when (eobp) (setq continue nil))
          (forward-visible-line 1))))))

(defun key-leap--after-change (beg end len)
  (when (or (= beg end)
            (string-match "\n" (buffer-substring-no-properties beg end)))
    (key-leap--update-current-buffer)))

(defun key-leap--clean-current-buffer ()
  (dolist (win (get-buffer-window-list (current-buffer) nil t))
    (remove-overlays (point-min) (point-max) 'window win)
    (set-window-margins win 0)))

(defun key-leap--update-buffer (buffer)
  (with-current-buffer buffer
    (when key-leap-mode
      (key-leap--delete-overlays)
      (dolist (win (get-buffer-window-list buffer nil t))
        (key-leap--update-margin-keys win)))))

(defun key-leap--window-scrolled (win beg)
  (key-leap--update-buffer (window-buffer win)))

(defun key-leap--update-current-buffer ()
  (key-leap--update-buffer (current-buffer)))

(defun key-leap--reset-match-state ()
  (setq key-leap--current-key "*")
  (key-leap--update-current-buffer))

(defun key-leap--append-char (valid-chars char-source-function)
  (let ((input-char (funcall char-source-function)))
    (if (member input-char valid-chars)
        (setq key-leap--current-key (concat key-leap--current-key (char-to-string input-char)))
      (progn
        (key-leap--reset-match-state)
        (error "Input char not part of any key")))))

(defun key-leap--read-keys (char-source-function)
  (setq key-leap--current-key "")
  (dolist (position-chars key-leap--key-chars)
    (key-leap--update-current-buffer)
    (key-leap--append-char position-chars char-source-function)))

(defun key-leap-start-matching ()
  "When called, will wait for the user to type the characters of a key in the margin, and then jump to the corresponding line."
  (interactive)
  (let ((inhibit-quit t))
    (if key-leap-mode
        (progn
          (unless
              (with-local-quit
                (princ " ")
                (key-leap--read-keys 'read-char)
                (key-leap--leap-to-current-key))
            (key-leap--reset-match-state))
          (key-leap--reset-match-state))
      (error "Key-leap-mode not enabled in this buffer"))))

;;;###autoload
(define-minor-mode key-leap-mode
  "Leap between visible lines by typing short keywords."
  :lighter nil
  :keymap (let ((key-map (make-sparse-keymap)))
            (define-key key-map (kbd "C-c #") 'key-leap-start-matching)
            key-map)
  (if key-leap-mode
      (progn
        (key-leap--cache-keys)
        (add-hook 'after-change-functions 'key-leap--after-change nil t)
        (add-hook 'window-scroll-functions 'key-leap--window-scrolled nil t)
        (add-hook 'change-major-mode-hook 'key-leap--clean-current-buffer nil t)
        (add-hook 'window-configuration-change-hook 'key-leap--update-current-buffer nil t)
        (add-hook 'post-command-hook 'key-leap--update-current-buffer nil t)
        (key-leap--update-current-buffer))
    (progn
      (remove-hook 'after-change-functions 'key-leap--after-change t)
      (remove-hook 'window-scroll-functions 'key-leap--window-scrolled t)
      (remove-hook 'change-major-mode-hook 'key-leap--clean-current-buffer t)
      (remove-hook 'window-configuration-change-hook 'key-leap--update-current-buffer t)
      (remove-hook 'post-command-hook 'key-leap--update-current-buffer t)
      (key-leap--clean-current-buffer))))

(provide 'key-leap)

;;; key-leap.el ends here
