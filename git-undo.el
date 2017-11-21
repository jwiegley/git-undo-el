;;; git-undo.el Foundation, Inc.

;; Author: John Wiegley <johnw@newartisans.com>
;; Created: 20 Nov 2017
;; Version: 0.1

;; Keywords: git diff history log undo
;; X-URL: https://github.com/jwiegley/git-undo

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Select a region and then use M-x git-undo to revert changes in that region
;; to the most recent Git historical version. Use C-x z to repeatdly walk back
;; through the history. M-x git-undo-browse will let you see the history of
;; changes in a separate buffer.

;;; Code:

(require 'cl)

(defgroup git-undo nil
  "Successively undo a buffer region using Git history"
  :group 'emacs)

(defvar git-undo--region-start)
(defvar git-undo--region-end)
(defvar git-undo--history)

(defun git-undo--apply-diff (hunk)
  (with-temp-buffer
    (insert hunk)
    (goto-char (point-min))
    (while (not (eobp))
      (pcase (char-after)
        (?\  (delete-char 1) (forward-line))
        (?\+ (delete-char 1) (forward-line))
        (?\- (delete-region (point) (and (forward-line) (point))))
        (t (delete-region (point) (point-max)))))
    (buffer-string)))

(defun git-undo--replace-region ()
  (goto-char git-undo--region-start)
  (delete-region git-undo--region-start git-undo--region-end)
  (if (null git-undo--history)
      (error "There is no more Git history to undo")
    (insert (git-undo--apply-diff (car git-undo--history)))
    (setq git-undo--history (cdr git-undo--history)))
  (goto-char git-undo--region-end))

(defun git-undo--compute-offsets (start end)
  "Taking uncommitted changes into account, find the location in
Git history for a given line."
  (let ((file-name (buffer-file-name))
        (buffer-lines (line-number-at-pos (point-max))))
    (with-temp-buffer
      (shell-command
       (format "git --no-pager diff -U%d HEAD -- %s"
               buffer-lines (file-name-nondirectory file-name))
       (current-buffer))
      (goto-char (point-min))
      (re-search-forward "^@@")
      (forward-line)
      (let ((adjustment 0)
            (line 1)
            adjusted-start
            adjusted-end)
        (while (not (eobp))
          (pcase (char-after)
            (?\+ (setq adjustment (1- adjustment)))
            (?\- (setq adjustment (1+ adjustment)))
            (t (setq line (1+ line))))
          (when (= (- start adjustment) line)
            (setq adjusted-start (+ start adjustment)))
          (when (= (- end adjustment) line)
            (setq adjusted-end (+ end adjustment))
            (goto-char (point-max)))
          (forward-line))
        (cons (1+ adjusted-start) adjusted-end)))))

(defun git-undo--build-history (start end)
  (let ((file-name (buffer-file-name)))
    (destructuring-bind (start-line . end-line)
        (git-undo--compute-offsets (line-number-at-pos start)
                                   (1- (line-number-at-pos end)))
      (with-temp-buffer
        (message "Retrieving Git history for lines %d to %d..."
                 start-line end-line)
        (shell-command
         (format "git --no-pager log --no-expand-tabs -p -L%d,%d:%s"
                 start-line end-line
                 (file-name-nondirectory file-name))
         (current-buffer))
        (message "")
        (goto-char (point-min))
        (let ((commit t) history)
          (while (and commit
                      (re-search-forward "^@@" nil t)
                      (forward-line))
            (delete-region (point-min) (point))
            (setq commit (and (re-search-forward "^commit " nil t)
                              (match-beginning 0)))
            (setq history (cons (buffer-substring-no-properties
                                 (point-min) (or commit (point-max)))
                                history)))
          (nreverse history))))))

;;;###autoload
(defun git-undo (&optional start end)
  "Undo Git-historical changes in the region from START to END."
  (interactive "r")
  (if (eq last-command 'git-undo)
      (git-undo--replace-region)
    (set (make-local-variable 'git-undo--region-start)
         (copy-marker start nil))
    (set (make-local-variable 'git-undo--region-end)
         (copy-marker end t))
    (set (make-local-variable 'git-undo--history)
         (git-undo--build-history start end))
    (git-undo--replace-region)))

;;;###autoload
(defun git-undo-browse (&optional start end)
  "Undo Git-historical changes in the region from START to END."
  (interactive "r")
  (let ((history (git-undo--build-history start end)))
    (display-buffer
     (with-current-buffer
         (get-buffer-create "*Git Region History*")
       (delete-region (point-min) (point-max))
       (dolist (entry history)
         (insert (git-undo--apply-diff entry)
                 #("-----\n" 0 5 (face bold))))
       (delete-region (- (point) 6) (point))
       (goto-char (point-min))
       (current-buffer)))))

;;; git-undo.el ends here
