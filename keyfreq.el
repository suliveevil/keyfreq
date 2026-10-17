;;; keyfreq.el --- track command frequencies
;; -*- coding: utf-8 -*-
;;
;; Copyright 2009-2010, 2015 by David Capello
;; Copyright 2008 by Xah Lee
;; Copyright 2006 by Michal Nazarewicz
;; Copyright 2006 by Ryan Yeske
;;
;; Author: Ryan Yeske, Michal Nazarewicz (mina86/AT/mina86.com)
;; Maintainer: David Capello, Xah lee
;; Created: 2006
;;
;; Package-Requires: ((cl-lib "0.5"))
;;
;;
;; Keyfreq is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.
;;
;; Version 1.8 - 2026
;; * Save in place: an existing entry keeps its line and only its
;;   counter is rewritten; unknown commands are appended before the
;;   closing parenthesis.  The file is no longer regenerated on every
;;   save, so version control shows only the lines that really changed.
;; * Fall back to a full rewrite only when the file cannot be parsed.
;; * Write through a temporary file (atomic rename) and never corrupt
;;   the in-memory table when a write fails.
;; * Add `keyfreq-sort-file' for a one-off normalisation of the file.
;;
;; Version 1.7 - 2015-09 - David Capello
;; * Avoid accumulating key frequency if keyfreq-file-release-lock fails
;;
;; Version 1.6 - 2015-09 - David Capello
;; * Added keyfreq-reset thanks to @w-vi
;; * Fixed issue running multiple instances of Emacs 24.5
;;
;; Version 1.5 - 2014-11 - David Capello
;; * Support cl-lib or cl
;; * Minor doc fixes
;;
;; Version 1.4 - 2010-09 - David Capello
;; * Renamed from command-frequency to keyfreq
;; * Now keyfreq-table holds "deltas"
;; * Removed a lot of "facility" functions to keep the code simple.
;; * Rename keyfreq-summarize-all-modes -> keyfreq-groups-major-modes.
;; * Added keyfreq-filter-major-mode
;; * Added lock file to avoid overwrite the file by two processes at
;;   the same time.
;;
;; Version 1.3 - 2009-09 - David Capello
;; * Added keyfreq-summarize-all-modes
;;
;; Version 1.2 - 2009-09 - David Capello
;; * Now each hash hash-key is a (major-mode . command) cons. Now only
;;   symbols are recorded.
;;
;; Version 1.1 - 2008-09
;; - Replaced the use of this-command var by real-last-command, so
;;   that the commands backward-kill-word, kill-word, kill-line,
;;   kill-region, do not all get counted as kill-region. Changed
;;   post-command-hook to pre-command-hook
;;
;; Version 1.0 - 2007
;; - Made into a full featured minor mode.  Added full doc
;;   strings. Added feature to save and read to disk the frequency
;;   hash table. Added ability to set user preference using emacs's
;;   customization system. Code is ~400 lines. This version is made by
;;   Michal Nazarewicz in 2007.
;;
;; Version 0.1 - 2006
;; - First version by Ryan Yeske. A quick hack of about 40 lines.
;;

;;; Commentary:
;;
;; HOW TO USE IT?
;;
;; Include the following lines in your .emacs file:
;;
;;   (require 'keyfreq)
;;   (keyfreq-mode 1)
;;   (keyfreq-autosave-mode 1)
;;
;; And use `keyfreq-show' to see how many times you used a command.
;;
;;; Code:

(if (not (featurep 'cl-lib))
    (progn
      (require 'cl)
      ;; fix conflict name
      (defalias 'cl-reduce 'reduce))
  (require 'cl-lib))
;; (require 'json)?

(defgroup keyfreq nil
  "Customization group for Keyfreq mode.
This mode stores number of times each command was called and
provides it as a statistical data."
  :package-version '(keyfreq . "1.7")
  :group 'local
  :prefix "keyfreq")

;;;###autoload
(define-minor-mode keyfreq-mode
  "Keyfreq mode records number of times each command was
called making it possible to access usage statistics through
various keyfreq-* functions."
  :global t
  :init-value nil
  :lighter nil
  :keymap nil
  :group 'keyfreq

  (if keyfreq-mode
      (add-hook 'pre-command-hook 'keyfreq-pre-command-hook)
    (remove-hook 'pre-command-hook 'keyfreq-pre-command-hook)))


(defcustom keyfreq-buffer "*frequencies*"
  "Buffer where frequencies are displayed."
  :group 'keyfreq
  :type 'string)

(defcustom keyfreq-folder (file-name-directory (or load-file-name buffer-file-name))
  "Where keyfreq is installed to retrieve the script.js file."
  :group 'keyfreq
  :type 'string)

(defcustom keyfreq-file "~/.emacs.keyfreq"
  "File `keyfreq-table' is saved to/loaded from by
`keyfreq-table-save' and `keyfreq-table-load' functions
by default."
  :group 'keyfreq
  :type 'file)


(defcustom keyfreq-file-lock "~/.emacs.keyfreq.lock"
  "Lock file to update the `keyfreq-file'."
  :group 'keyfreq
  :type 'file)

(defcustom keyfreq-excluded-regexp '()
  "List of commands in REGEXP-FORM excluded by keyfreq."
  :group 'keyfreq
  :type 'file)

(defvar keyfreq-table (make-hash-table :test 'equal :size 128)
  "Hash table storing number of times each command was called in each major mode
since the last time the frequencies were saved in `keyfreq-file'.")

(defvar keyfreq-excluded-commands '()
  "List of commands excluded by keyfreq.")

(defun keyfreq-match-p (cmd)
  "Return t if CMD in `keyfreq-excluded-commands' or match `keyfreq-excluded-regexp'."
  ;; HACK Inspire by `consult--regexp-filter'
  (let ((filter (mapconcat (lambda (x) (concat "\\(?:" x "\\)"))
                           keyfreq-excluded-regexp "\\|")))
    (or (memq cmd keyfreq-excluded-commands)
        (when keyfreq-excluded-regexp
          (string-match-p filter (symbol-name cmd))))))


(defun keyfreq-pre-command-hook ()
  "Record command execution in `keyfreq-table' hash."
  (let ((command real-last-command) count)
    (when (and command (symbolp command))
      (setq count (gethash (cons major-mode command) keyfreq-table))
      (unless (keyfreq-match-p command)
        (puthash (cons major-mode command) (if count (1+ count) 1)
                 keyfreq-table)
        ))))

(defun keyfreq-groups-major-modes (table)
  "Group major modes in TABLE by command.
Return a hash table where each entry has COMMAND as key and
COUNTER as value."
  (let ((new-table (make-hash-table :test 'equal :size 128)))
    (maphash (lambda (k v)
	       (puthash (cdr k) (+ (gethash (cdr k) new-table 0) v) new-table))
	     table)
    new-table))


(defun keyfreq-filter-major-mode (table major-mode)
  "Leave the frequencies of the specified major mode.
Return a hash table where each entry has COMMAND as key and
COUNTER as value."

  (let ((new-table (make-hash-table :test 'equal :size 128)))
    (maphash (lambda (k v)
	       (when (eq (car k) major-mode)
		 (puthash (cdr k) (+ (gethash (cdr k) new-table 0) v) new-table)))
	     table)
    new-table))


(defun keyfreq-used-major-modes (table)
  "Return a list with the used major modes (major modes
contained in the TABLE)."
  (let ((list))
    (maphash (lambda (k v)
	       (add-to-list 'list (car k)))
	     table)
    list))


(defun keyfreq-list (table &optional reverse limit)
  "Return a cons which car is sum of times any command was used
and cdr is a list of (command . count) pairs.

If REVERSE is nil, sort it starting from the most used command;
if it is `no-sort' the list is not sorted; if it is non-nil and
not `no-sort', sort it from the least used commands.  If LIMIT is
a positive number, only commands which were used more then LIMIT
times will be added.  If it is a negative number, only commands
which were used less then -LIMIT times will be added."

  (let (l (sum 0))
    (maphash
     (cond
      ((or (not (numberp limit)) (= limit 0))
       (lambda (k v) (setq l (cons (cons k v) l) sum (+ sum v))))
      ((= limit -1) (lambda (k v) (setq sum (+ sum v))))
      ((< limit 0)
       (setq limit (- limit))
       (lambda (k v) (setq sum (+ sum v))
	 (if (< v limit) (setq l (cons (cons k v) l)))))
      (t
       (lambda (k v) (setq sum (+ sum v))
	 (if (> v limit) (setq l (cons (cons k v) l))))))
     table)
    (cons sum
	  (cond
	   ((equal reverse 'no-sort) l)
	   (reverse (sort l (lambda (a b) (< (cdr a) (cdr b)))))
	   (t       (sort l (lambda (a b) (> (cdr a) (cdr b)))))))))


(defun keyfreq-format-list (list &optional func)
  "Return formatted string with command usage statistics.

The LIST is the `keyfreq-table' converted to a list using the `keyfreq-list'.

If FUNC is nil each line contains number of times command was
called and the command; if it is t percentage usage is added in
the middle; if it is 'raw each line will contain number an
command separated by single line (with no formatting) otherwise
FUNC must be a function returning a string which will be called
for each entry with three arguments: number of times command was
called, percentage usage and the command."
  (let* ((sum (car list))
         (max-len
          (cl-reduce (lambda (a b) (max a (length (symbol-name (car b)))))
                  (cdr list)
                  :initial-value 0)))
    (mapconcat
     (cond
      ((not func) (lambda (e) (format "%7d  %s\n" (cdr e) (car e))))
      ((equal func t)
       (lambda (e) (format (concat "%7d  %6.2f%%  %- "
                              (format "%d" max-len)
                              "s %s\n")
			   (cdr e) (/ (* 1e2 (cdr e)) sum) (car e)
                           (ignore-errors (keyfreq-where-is (car e))))))
      ((equal func 'raw) (lambda (e) (format "%d %s\n" (cdr e) (car e))))
      (t (lambda (e) (funcall func (cdr e) (/ (* 1e2 (cdr e)) sum) (car e)))))
     (cdr list) "")))

(defun keyfreq-where-is (command &optional keymaps)
  "Return the keys COMMAND is bound to, as a comma separated string.

KEYMAPS defaults to the global keymap.  To also see a mode's own
bindings pass its keymap, e.g.

  (keyfreq-where-is 'org-return (keyfreq--mode-keymap 'org-mode))

Since Emacs 30 `where-is-internal' takes (DEFINITION KEYMAP FIRSTONLY
NOINDIRECT); a non-nil KEYMAP means `search this keymap and the global
keymap'."
  (mapconcat 'key-description
             (where-is-internal command (or keymaps (list global-map)))
             ", "))

(defun keyfreq--mode-keymap (major-mode)
  "Return MAJOR-MODE's own keymap when it follows the `<mode>-map' convention."
  (let ((symbol (intern (concat (symbol-name major-mode) "-map"))))
    (and (boundp symbol)
         (keymapp (symbol-value symbol))
         (symbol-value symbol))))

(defun keyfreq--mode-keymaps (major-mode)
  "Return the keymap to resolve MAJOR-MODE's bindings in.

Major modes bind most of their commands in their own keymap rather than
in `global-map'; resolving against `global-map' alone silently drops
them (for `org-mode' that was 42% of all key presses).  Falls back to
`global-map' when the mode has no `<mode>-map'."
  (or (keyfreq--mode-keymap major-mode) (list global-map)))

(defun keyfreq-show (&optional major-mode-symbol)
  "Show command usage statistics in `keyfreq-buffer'.

If MAJOR-MODE-SYMBOL is given, the function shows the statistics
for that particular major mode only.

With a universal argument, the major-mode of the current buffer
is used as MAJOR-MODE-SYMBOL argument."
  (interactive (list (cond (current-prefix-arg major-mode)
			   (t nil))))

  (let ((table (copy-hash-table keyfreq-table)))
    ;; Merge with the values in `keyfreq-file'
    (keyfreq-table-load table)

    (let* ((list (keyfreq-list
		  (cond
		   (major-mode-symbol (keyfreq-filter-major-mode table major-mode-symbol))
		   (t (keyfreq-groups-major-modes table)))))
	   (formatted-list (keyfreq-format-list list t)))

      ;; Display the table
      (display-message-or-buffer (concat (if major-mode-symbol
					     (concat "For " (symbol-name major-mode))
					   (concat "For all major modes"))
					 ":\n\n"
					 formatted-list)
				 keyfreq-buffer)
      )))


(defcustom keyfreq-html-history t
  "When non-nil, `keyfreq-html-v2' reads the git history of
`keyfreq-file' and lets the report pick a time period.

The log is a plain file in a git repository for most people, and the
commit dates are the only time information keyfreq has: the counters
are cumulative, so a snapshot taken from an old commit shows what the
heat map looked like back then."
  :group 'keyfreq
  :type 'boolean)

(defun keyfreq--git (repo &rest args)
  "Run git in REPO with ARGS and return its stdout, or nil on failure."
  (when (and repo (executable-find "git"))
    (with-temp-buffer
      (let ((status (apply #'call-process "git" nil (current-buffer) nil
                           (append (list "-C" repo) args))))
        (when (eq status 0)
          (buffer-string))))))

(defun keyfreq--git-repo (file)
  "Return (REPO . RELATIVE-PATH) for FILE when it lives in a git work tree."
  (let* ((target (expand-file-name file))
         (dir (file-name-directory target))
         (top (ignore-errors
                (string-trim
                 (or (keyfreq--git dir "rev-parse" "--show-toplevel") "")))))
    (when (and (not (string-empty-p top)) (file-directory-p top))
      (cons top (file-relative-name target top)))))

(defun keyfreq--read-log-entries (text)
  "Parse TEXT as a keyfreq log and return a hash of (MODE . COMMAND) -> count."
  (let ((table (make-hash-table :test 'equal)))
    (ignore-errors
      (with-temp-buffer
        (insert text)
        (goto-char (point-min))
        (let ((form (read (current-buffer))))
          (dolist (entry form)
            (when (and (consp entry) (consp (car entry)) (integerp (cdr entry)))
              (puthash (car entry) (+ (gethash (car entry) table 0) (cdr entry))
                       table))))))
    table))

(defun keyfreq--git-versions (file)
  "Return (DATE . TEXT) pairs for each commit of FILE, oldest first."
  (let* ((repo (keyfreq--git-repo file))
         (repo-dir (car-safe repo))
         (relative (cdr-safe repo)))
    (when repo-dir
      (let ((log (keyfreq--git repo-dir "log" "--format=%h%x09%ad"
                               "--date=short" "--follow" "--" relative))
            (versions nil))
        (when log
          (dolist (line (nreverse (split-string log "\n" t)))
            (let ((fields (split-string line "\t")))
              (when (and (car fields) (cadr fields))
                (let ((text (keyfreq--git repo-dir "show"
                                          (concat (car fields) ":" relative))))
                  (when text
                    (push (cons (cadr fields) text) versions)))))))
        (nreverse versions)))))

(defun keyfreq--read-file-entries (file)
  "Parse FILE as a keyfreq log."
  (when (file-exists-p file)
    (keyfreq--read-log-entries
     (with-temp-buffer
       (let ((coding-system-for-read
              (or keyfreq-coding-system 'undecided)))
         (insert-file-contents file))
       (buffer-string)))))

(defun keyfreq--history-snapshots (file)
  "Return (PERIOD . TABLE) pairs for FILE, one per month plus now.

The counters are cumulative, and the log was rewritten a few times over
the years (a machine or Emacs change resets some counters), so the
useful question is not what changed between two commits but what the
whole picture looked like at a given moment.  Snapshots are monotonic
by construction and cannot produce negative counts."
  (let ((versions (and keyfreq-html-history (keyfreq--git-versions file)))
        (latest (make-hash-table :test 'equal))
        (months nil))
    (dolist (version versions)
      (let ((month (substring (car version) 0 (min 7 (length (car version))))))
        (unless (gethash month latest)
          (push month months))
        (puthash month (cdr version) latest)))
    (let ((result nil))
      (dolist (month (nreverse months))
        (push (cons month (keyfreq--read-log-entries (gethash month latest)))
              result))
      (when (file-exists-p file)
        (push (cons "now" (keyfreq--read-file-entries file)) result))
      (nreverse result))))

(defun keyfreq--history-payload (snapshots)
  "Return (PERIODS NAMES ROWS) describing SNAPSHOTS.

ROWS is a list of (PERIOD-INDEX MODE-INDEX COMMAND-INDEX COUNT), where
the indexes point into NAMES."
  (let ((periods nil)
        (names nil)
        (index (make-hash-table :test 'equal))
        (rows nil)
        (period 0))
    (dolist (snapshot snapshots)
      (push (car snapshot) periods)
      (maphash
       (lambda (key count)
         (when (and (consp key) (symbolp (cdr key)) (> count 0))
           (let ((mode-name (symbol-name (car key)))
                 (command-name (symbol-name (cdr key))))
             (dolist (name (list mode-name command-name))
               (unless (gethash name index)
                 (setq names (append names (list name)))
                 (puthash name (1- (length names)) index)))
             (push (list period
                         (gethash mode-name index)
                         (gethash command-name index)
                         count)
                   rows))))
       (cdr snapshot))
      (setq period (1+ period)))
    (list (nreverse periods) names (nreverse rows))))

(defun keyfreq--json-history (periods names rows)
  "Return `keyfreq--json-history-1' with HTML-significant characters escaped."
  (let ((json (keyfreq--json-history-1 periods names rows)))
    (setq json (replace-regexp-in-string "<" "\\u003c" json t t))
    (setq json (replace-regexp-in-string ">" "\\u003e" json t t))
    (setq json (replace-regexp-in-string "&" "\\u0026" json t t))
    json))

(defun keyfreq--json-quoted (string)
  "Return STRING as a JSON string literal."
  (require (quote json))
  (json-encode-string string))

(defun keyfreq--json-history-1 (periods names rows)
  "Serialise the history as a JSON object.

Angle brackets and ampersands are escaped as \\u escapes so that the
payload can be embedded in a script element safely."
  (concat
   "{\"periods\":["
   (mapconcat #'keyfreq--json-quoted periods ",")
   "],\"names\":["
   (mapconcat #'keyfreq--json-quoted names ",")
   "],\"rows\":["
   (mapconcat (lambda (row)
                (concat "[" (mapconcat #'number-to-string row ",") "]"))
              rows ",")
   "]}"))

;;; ------------------------------------------------------------------
;;; Daily archives
;;; ------------------------------------------------------------------

(defcustom keyfreq-daily-archive t
  "When non-nil, keep one file per day under `keyfreq-daily-directory'.

`keyfreq-file' stays the cumulative rollup that the \"All time\"
view reads.  The daily archives are the authority for the Today /
7 days / 30 days views, and they make the rollup rebuildable with
`keyfreq-rebuild-rollup'."
  :group 'keyfreq
  :type 'boolean)

(defcustom keyfreq-daily-directory nil
  "Directory holding the per-day archives.
Nil means a `keyfreq-days' directory next to `keyfreq-file'."
  :group 'keyfreq
  :type '(choice (const :tag "Next to keyfreq-file" nil) directory))

(defvar keyfreq--rollup-dirty nil
  "Expanded name of a rollup file that must be rebuilt from the archives.

Storing the file rather than a flag keeps a failure from one rollup from
triggering a rebuild of a different one.")

(defun keyfreq--daily-dir ()
  "Return the directory holding the daily archives."
  (or keyfreq-daily-directory
      (expand-file-name
       "keyfreq-days"
       (file-name-directory (expand-file-name keyfreq-file)))))

(defun keyfreq--daily-baseline ()
  "Return the file holding the pre-archive totals."
  (expand-file-name ".baseline.log" (keyfreq--daily-dir)))

(defun keyfreq--daily-file (&optional days-ago)
  "Return the archive file for DAYS-AGO days before today."
  (let* ((now (decode-time))
         ;; noon keeps summer time from moving the date around
         (time (encode-time 0 0 12 (- (nth 3 now) (or days-ago 0))
                            (nth 4 now) (nth 5 now))))
    (expand-file-name (concat (format-time-string "%Y-%m-%d" time) ".log")
                      (keyfreq--daily-dir))))

(defun keyfreq--daily-ensure-baseline ()
  "Copy the rollup aside once, before the first daily archive is written."
  (let ((baseline (keyfreq--daily-baseline)))
    (unless (or (file-exists-p baseline)
                (not (file-exists-p keyfreq-file))
                (zerop (file-attribute-size (file-attributes keyfreq-file))))
      (make-directory (keyfreq--daily-dir) t)
      (copy-file keyfreq-file baseline t))))

(defun keyfreq--table-entries (table)
  "Return the entries of TABLE sorted by their printed key."
  (let ((entries nil))
    (maphash (lambda (key count) (push (cons key count) entries)) table)
    (sort entries
          (lambda (a b)
            (string< (prin1-to-string (car a)) (prin1-to-string (car b)))))))

(defun keyfreq--write-table (table file)
  "Write TABLE to FILE as a keyfreq log, replacing it."
  (make-directory (file-name-directory (expand-file-name file)) t)
  (let ((content
         (with-temp-buffer
           (insert "(")
           (dolist (entry (keyfreq--table-entries table))
             (insert (prin1-to-string entry) "\n"))
           (insert ")")
           (buffer-string))))
    (keyfreq--write-file content file
                         (keyfreq--writing-coding-system
                          (keyfreq--file-coding-system file)))))

(defun keyfreq--archive-day (pending)
  "Add the deltas in PENDING to today's archive."
  (make-directory (keyfreq--daily-dir) t)
  (keyfreq--daily-ensure-baseline)
  (let ((file (keyfreq--daily-file)))
    (if (and (file-exists-p file)
             (> (file-attribute-size (file-attributes file)) 0))
        (keyfreq--merge-in-place pending file)
      (keyfreq--write-table pending file))))

(defun keyfreq--range-table (days)
  "Return a table with the totals of the last DAYS daily archives."
  (let ((table (make-hash-table :test 'equal)))
    (dotimes (i days)
      (let ((file (keyfreq--daily-file i)))
        (when (file-exists-p file)
          (maphash (lambda (key count)
                     (puthash key (+ (gethash key table 0) count) table))
                   (keyfreq--read-file-entries file)))))
    table))

(defun keyfreq-rebuild-rollup ()
  "Rebuild `keyfreq-file' from the baseline plus every daily archive."
  (interactive)
  (let ((dir (keyfreq--daily-dir)))
    (unless (file-directory-p dir)
      (user-error "No daily archives in %s" dir))
    (let ((table (make-hash-table :test 'equal))
          (files (directory-files
                  dir t "\\`[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\\.log\\'")))
      (let ((baseline (keyfreq--daily-baseline)))
        (when (file-exists-p baseline)
          (maphash (lambda (key count)
                     (puthash key (+ (gethash key table 0) count) table))
                   (keyfreq--read-file-entries baseline))))
      (dolist (file files)
        (maphash (lambda (key count)
                   (puthash key (+ (gethash key table 0) count) table))
                 (keyfreq--read-file-entries file)))
      (keyfreq--write-table table keyfreq-file)
      (setq keyfreq--rollup-dirty nil)
      (message "keyfreq: rebuilt %s from %d daily files"
               (file-name-nondirectory keyfreq-file) (length files)))))

(defun keyfreq--report-snapshots (file)
  "Return (PERIOD . TABLE) pairs for the report, ranges first."
  (let ((ranges nil))
    (when (and keyfreq-daily-archive (file-directory-p (keyfreq--daily-dir)))
      (dolist (spec '(("today" . 1) ("7d" . 7) ("30d" . 30)))
        (let ((table (keyfreq--range-table (cdr spec))))
          (when (> (hash-table-count table) 0)
            (push (cons (car spec) table) ranges)))))
    (append (nreverse ranges) (keyfreq--history-snapshots file))))

(defun keyfreq--period-label (period)
  "Return the menu label for the report PERIOD."
  (cond ((equal period "now") "All time")
        ((equal period "today") "Today")
        ((equal period "7d") "Last 7 days")
        ((equal period "30d") "Last 30 days")
        (t period)))

;;; ------------------------------------------------------------------
;;; HTML report
;;; ------------------------------------------------------------------

(defvar keyfreq-html--last-temp-report nil
  "The temporary report written by the previous `keyfreq-html-v2' call.")

(defun keyfreq--html-escape (string)
  "Return STRING escaped for use as HTML text or in a quoted attribute."
  (let ((s (format "%s" string)))
    (setq s (replace-regexp-in-string "&" "&amp;" s t t))
    (setq s (replace-regexp-in-string "<" "&lt;" s t t))
    (setq s (replace-regexp-in-string ">" "&gt;" s t t))
    (setq s (replace-regexp-in-string "\"" "&quot;" s t t))
    s))

(defun keyfreq--html-number (number)
  "Return NUMBER as a string with thousands separators."
  (let ((s (number-to-string number)))
    (if (<= (length s) 3)
        s
      (let ((parts nil))
        (while (> (length s) 3)
          (push (substring s (- (length s) 3)) parts)
          (setq s (substring s 0 (- (length s) 3))))
        (push s parts)
        (mapconcat #'identity parts ",")))))

(defun keyfreq--html-id (string used)
  "Return a unique id for STRING that is safe in a URL fragment.
USED is a hash table of ids already handed out; it is updated."
  (let* ((base (replace-regexp-in-string "[^A-Za-z0-9_-]" "-" string))
         (base (if (string-match-p "\\`[A-Za-z_]" base)
                   base
                 (concat "x-" base)))
         (id base)
         (i 1))
    (while (gethash id used)
      (setq id (format "%s-%d" base (setq i (1+ i)))))
    (puthash id t used)
    id))

(defun keyfreq--html-asset-file (name)
  "Return the absolute path of the bundled asset NAME."
  (let ((file (expand-file-name name keyfreq-folder))
        (lib (locate-library "keyfreq")))
    (unless (file-exists-p file)
      (setq file (and lib (expand-file-name name (file-name-directory lib)))))
    (unless (and file (file-exists-p file))
      (error "keyfreq: cannot find %s; customize `keyfreq-folder'" name))
    file))

(defun keyfreq--html-insert-asset (name)
  "Insert the contents of the bundled asset NAME at point.
Inlining turns the report into a single self-contained file."
  (insert
   (with-temp-buffer
     (let ((coding-system-for-read 'utf-8))
       (insert-file-contents (keyfreq--html-asset-file name)))
     (buffer-string))))

(defun keyfreq--html-modes (table)
  "Return an alist of (MAJOR-MODE . TOTAL) for TABLE, most used first."
  (let ((cells nil))
    (maphash (lambda (key count)
               (when (consp key)
                 (let ((cell (assoc (car key) cells)))
                   (if cell
                       (setcdr cell (+ (cdr cell) count))
                     (push (cons (car key) count) cells)))))
             table)
    (sort cells
          (lambda (a b)
            (if (= (cdr a) (cdr b))
                (string< (symbol-name (car a)) (symbol-name (car b)))
              (> (cdr a) (cdr b)))))))

(defun keyfreq--pseudo-binding-p (sequence)
  "Return non-nil when SEQUENCE is a menu-bar/tool-bar style binding.
Those are not keystrokes, and they add noise to the Shortcut column."
  (string-match-p
   "\\`<\\(menu-bar\\|tool-bar\\|tab-bar\\|mode-line\\|vertical-line\\|right-divider\\|bottom-divider\\|vertical-scroll-bar\\|horizontal-scroll-bar\\)>"
   (key-description sequence)))

(defun keyfreq--html-printable (string)
  "Return STRING with every non-printing character replaced by ?.

`key-description' can emit raw bytes (for example for the pseudo key
ranges bound to `undefined'); those are not valid HTML text and cannot
be encoded as UTF-8."
  (replace-regexp-in-string "[^[:print:]]" "?" string))

(defun keyfreq--where-is-string (command keymaps)
  "Return COMMAND's keys resolved in KEYMAPS, HTML-escaped.

Pseudo bindings (menu-bar, tool-bar, ...) and unprintable key ranges
are left out; the result is always valid UTF-8 text."
  (if (eq command 'undefined)
      ""
    (keyfreq--html-escape
     (mapconcat (lambda (sequence)
                  (keyfreq--html-printable (key-description sequence)))
                (cl-remove-if
                 (lambda (sequence)
                   (or (keyfreq--pseudo-binding-p sequence)
                       ;; a "80..255"-style range is a character class,
                       ;; not something one presses
                       (string-match-p "\\.\\." (key-description sequence))))
                 (where-is-internal command (or keymaps (list global-map))))
                ", "))))

(defun keyfreq--html-shortcut-index (table modes)
  "Resolve every mode/command pair in TABLE to its keystrokes.

MODES is the value of `keyfreq--html-modes'.

Return (PER-MODE . UNION).  PER-MODE maps a major mode to a hash table
of COMMAND -> escaped keystroke string resolved in that mode's own
keymap.  UNION maps COMMAND -> every binding seen in any mode, which is
what the \"All major modes\" table shows."
  (let ((per-mode (make-hash-table :test 'eq))
        (all (make-hash-table :test 'eq))
        (global-cache (make-hash-table :test 'eq)))
    (dolist (cell modes)
      (let* ((mode (car cell))
             (map (keyfreq--mode-keymap mode))
             (index (make-hash-table :test 'eq))
             (commands nil))
        (maphash (lambda (key _count)
                   (when (eq (car-safe key) mode)
                     (push (cdr key) commands)))
                 table)
        (dolist (command commands)
          (let ((text (if map
                          (keyfreq--where-is-string command map)
                        (or (gethash command global-cache)
                            (puthash command
                                     (keyfreq--where-is-string command nil)
                                     global-cache)))))
            (puthash command text index)
            (when (not (string-empty-p text))
              (puthash command (append (gethash command all) (list text)) all))))
        (puthash mode index per-mode)))
    (maphash (lambda (command parts)
               (puthash command
                        (mapconcat #'identity
                                   (delete-dups
                                    (apply #'append
                                           (mapcar (lambda (s)
                                                     (split-string s ",\\s-*" t))
                                                   parts)))
                                   ", ")
                        all))
             all)
    (cons per-mode all)))

(defun keyfreq--html-insert-table (list shortcut)
  "Insert an HTML table for LIST, a value returned by `keyfreq-list'.
SHORTCUT is a function that maps a command to its already escaped
keystroke description."
  (insert "<table>\n")
  (insert "<colgroup><col style=\"width:10%\"><col style=\"width:9%\">"
          "<col><col style=\"width:42%\"></colgroup>\n")
  (insert "<thead><tr>"
          "<th scope=\"col\" aria-sort=\"descending\">"
          "<button type=\"button\" class=\"sort\" data-sort=\"count\">Times</button></th>"
          "<th scope=\"col\">"
          "<button type=\"button\" class=\"sort\" data-sort=\"percent\">%</button></th>"
          "<th scope=\"col\">"
          "<button type=\"button\" class=\"sort\" data-sort=\"command\">Command</button></th>"
          "<th scope=\"col\">"
          "<button type=\"button\" class=\"sort\" data-sort=\"shortcut\">Shortcut</button></th>"
          "</tr></thead>\n<tbody>\n")
  ;; Keep the rows terse: cells are styled by position, and the counter is
  ;; carried by `data-count' so the renderer does not have to parse the
  ;; first column.
  (keyfreq-format-list
   list
   (lambda (count perc command)
     (insert (format "<tr><td>%s</td><td>%.2f%%</td><td>%s</td>"
                     (keyfreq--html-number count) perc
                     (keyfreq--html-escape
                      ;; Emacs records the symbol `undefined' when an
                      ;; unbound key is pressed; say so instead of
                      ;; printing "undefined".
                      (if (eq command 'undefined)
                          "(unbound key)"
                        command)))
             (format "<td data-count=\"%d\">%s</td></tr>\n"
                     count (funcall shortcut command)))))
  (insert "</tbody>\n</table>\n"))

(defun keyfreq--html-insert-card (modes periods)
  "Insert the interactive heat map card.

MODES is the value of `keyfreq--html-modes'; PERIODS is the list of
history periods, or nil when there is no git history.  The card holds a
single canvas plus the controls that choose what it shows."
  (insert "<section class=\"card\" id=\"heatmap-card\">\n")
  (insert "<div class=\"card-head\">\n")
  (insert "<h2>Keyboard heat map</h2>\n")
  (insert "<div class=\"controls\">\n")
  (insert "<label>Mode <select id=\"mode-select\">")
  (insert "<option value=\"all\">All major modes</option>")
  (dolist (entry modes)
    (insert (format "<option value=\"%s\">%s (%s)</option>"
                    (keyfreq--html-escape (car entry))
                    (keyfreq--html-escape (car entry))
                    (keyfreq--html-number (cdr entry)))))
  (insert "</select></label>\n")
  (insert "<label>Scale <select id=\"scale-select\">"
          "<option value=\"sqrt\" selected>sqrt</option>"
          "<option value=\"linear\">linear</option>"
          "<option value=\"log\">log</option>"
          "</select></label>\n")
  (when (> (length periods) 1)
    (insert "<label>Period <select id=\"period-select\">")
    (dolist (period periods)
      (unless (equal period "now")
        (insert (format "<option value=\"%s\">%s</option>"
                        (keyfreq--html-escape period)
                        (keyfreq--html-escape (keyfreq--period-label period))))))
    (insert "<option value=\"now\" selected>All time</option>")
    (insert "</select></label>\n"))
  (insert "<span class=\"scope\" id=\"scope-summary\"></span>\n")
  (insert "</div>\n</div>\n")
  (insert "<div class=\"heatmap-wrap\">\n")
  (insert "<canvas id=\"heatmap\" width=\"900\" height=\"340\"></canvas>\n")
  (insert "<div class=\"key-tip\" id=\"key-tip\" hidden></div>\n")
  (insert "<p class=\"empty\" id=\"empty-note\" hidden>"
          "no keyboard shortcuts in this selection</p>\n")
  (insert "</div>\n")
  (insert "<p class=\"hint\">Hover a key for its press count.  Each command "
          "is counted once, on its first real binding, resolved in that "
          "mode's own keymap.</p>\n")
  (insert "</section>\n"))

(defun keyfreq-html (filename &optional confirm)
  "Save a plain HTML report of the statistics as FILENAME.

Kept for compatibility; the interactive keyboard report is
`keyfreq-html-v2', which this now shares its implementation with."
  (interactive
   (list (read-file-name "Write HTML file: " nil nil nil
                         (expand-file-name "keyfreq.html" default-directory))
         (not current-prefix-arg)))
  (and confirm
       (file-exists-p filename)
       (or (y-or-n-p (format "File `%s' exists; overwrite? " filename))
           (error "Canceled")))
  (keyfreq-html-v2 filename nil))

(defun keyfreq-html-v2 (&optional filename open)
  "Save a self-contained HTML report with a keyboard heat map.

The report embeds `style.css' and `script.js', so it can be moved,
mailed or committed as a single file.  A single canvas shows the heat
map for the major mode picked in the Mode menu.

FILENAME defaults to a fresh file in `temporary-file-directory' and
the previously generated temporary report is removed.  When OPEN is
non-nil the report is shown with `browse-url'.

Interactively, use a prefix argument to choose FILENAME."
  (interactive
   (list (when current-prefix-arg
           (read-file-name "Write HTML report: " nil nil nil
                           "keyfreq-report.html"))
         t))
  (let ((table (copy-hash-table keyfreq-table)))
    (keyfreq-table-load table)
    (let* ((modes (keyfreq--html-modes table))
           (used (make-hash-table :test 'equal))
           (ids (make-hash-table :test 'eq))
           (total (car (keyfreq-list table 'no-sort)))
           (index (keyfreq--html-shortcut-index table modes))
           (per-mode (car index))
           (all-keys (cdr index))
           (snapshots (keyfreq--report-snapshots keyfreq-file))
           (payload (keyfreq--history-payload snapshots))
           (file (or filename
                     (make-temp-file
                      (expand-file-name "keyfreq-" temporary-file-directory)
                      nil ".html")))
           (cell (lambda (list shortcut)
                   (with-temp-buffer
                     (keyfreq--html-insert-table list shortcut)
                     (buffer-string)))))
      (dolist (entry modes)
        (puthash (car entry)
                 (keyfreq--html-id (symbol-name (car entry)) used)
                 ids))
      ;; bind the coding system around the whole writer: `with-temp-file'
      ;; writes after its body, so a `let' inside would be too late.
      (let ((coding-system-for-write 'utf-8-unix))
        (with-temp-file file
          (insert "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n")
          (insert "<meta charset=\"utf-8\">\n")
          (insert "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n")
          (insert (format "<title>Keyfreq Report - %s commands in %d modes</title>\n"
                          (keyfreq--html-number (hash-table-count table))
                          (length modes)))
          (insert "<style>\n")
          (keyfreq--html-insert-asset "style.css")
          (insert "\n</style>\n</head>\n<body>\n")
          (insert "<nav class=\"header\" id=\"header\">\n")
          (insert "<div class=\"nav-sort\"><label>Sort <select id=\"mode-order\">"
                  "<option value=\"count\" selected>by presses</option>"
                  "<option value=\"name\">by name</option>"
                  "</select></label><span class=\"modes-total\">"
                  (format "%d modes" (length modes))
                  "</span></div>\n")
          (insert "<ul>\n")
          (insert (format "<li><a href=\"#anchor-all\"><span class=\"name\">All major modes</span><span class=\"count\">%s</span></a></li>\n"
                          (keyfreq--html-number total)))
          (dolist (entry modes)
            (insert (format "<li><a href=\"#%s\"><span class=\"name\">%s</span><span class=\"count\">%s</span></a></li>\n"
                            (gethash (car entry) ids)
                            (keyfreq--html-escape (car entry))
                            (keyfreq--html-number (cdr entry)))))
          (insert "</ul>\n</nav>\n<main class=\"content\">\n")
          (insert "<h1>Keyfreq Report</h1>\n")
          (insert (format "<p class=\"summary\">%s mode/command pairs &middot; %d modes &middot; %s invocations &middot; generated %s</p>\n"
                          (keyfreq--html-number (hash-table-count table))
                          (length modes)
                          (keyfreq--html-number total)
                          (format-time-string "%Y-%m-%d %H:%M")))
          (keyfreq--html-insert-card modes (car payload))
          (insert "<section data-mode=\"all\">\n")
          (insert "<h2 id=\"anchor-all\">All major modes</h2>\n")
          (insert (funcall cell
                           (keyfreq-list (keyfreq-groups-major-modes table))
                           (lambda (command) (or (gethash command all-keys) ""))))
          (insert "</section>\n")
          (dolist (entry modes)
            (let* ((mode (car entry))
                   (keys (gethash mode per-mode)))
              (insert (format "<section data-mode=\"%s\">\n"
                              (keyfreq--html-escape (symbol-name mode))))
              (insert (format "<h2 id=\"%s\">%s</h2>\n"
                              (gethash mode ids)
                              (keyfreq--html-escape mode)))
              (insert (funcall cell
                               (keyfreq-list (keyfreq-filter-major-mode table mode))
                               (lambda (command)
                                 (or (gethash command keys) ""))))
              (insert "</section>\n")))
          (insert "</main>\n")
          (when (> (length (car payload)) 1)
            ;; escape < > & so the payload can never close the script tag
            (insert "<script type=\"application/json\" id=\"keyfreq-data\">")
            (insert (keyfreq--json-history (car payload) (nth 1 payload) (nth 2 payload)))
            (insert "</script>\n"))
          (insert "</body>\n</html>\n")
          (insert "<script>\n")
          (keyfreq--html-insert-asset "script.js")
          (insert "\n</script>\n")))
      ;; drop the previous temporary report so the temp dir does not fill up
      (when (and (null filename)
                 keyfreq-html--last-temp-report
                 (not (equal keyfreq-html--last-temp-report file))
                 (file-exists-p keyfreq-html--last-temp-report))
        (ignore-errors (delete-file keyfreq-html--last-temp-report)))
      (setq keyfreq-html--last-temp-report (unless filename file))
      (message "keyfreq: wrote %s" file)
      (when open (browse-url file))
      file)))

(defun keyfreq-json-encode (table)
  "Return a JSON representation of the table of frequencies."
  (require 'json)
  (let ((commands-indexes (make-hash-table :test 'equal :size 128))
	commands-list frequencies-matrix i)

    ;; Build the "commands" property of the JSON object.
    (setq i 0)
    (maphash
     (lambda (command-symbol counter)
       (add-to-list 'commands-list command-symbol t)
       (puthash command-symbol i commands-indexes)
       (setq i (+ i 1))
       )
     (keyfreq-groups-major-modes table))

    ;; Build the "frequencies" property.
    (mapc
     (lambda (major-mode-symbol)
       (let ((cmd-count-pairs '()))
	 (keyfreq-format-list (keyfreq-list (keyfreq-filter-major-mode table major-mode-symbol))
			      (lambda (count perc command)
				(add-to-list 'cmd-count-pairs (gethash command commands-indexes) t)
				(add-to-list 'cmd-count-pairs count t)))
	 (add-to-list 'frequencies-matrix major-mode-symbol t)
	 (add-to-list 'frequencies-matrix (append cmd-count-pairs nil) t)))
     (keyfreq-used-major-modes table))

    (json-encode `((:format . 1)
		   (:commands . ,commands-list)
		   (:frequencies . ,frequencies-matrix)))))


(defun keyfreq-json (filename &optional confirm)
  "Save a file (as FILENAME) with a JSON structure of the data."

  (interactive
   (list (if buffer-file-name
	     (read-file-name "Write JSON file: "
			     nil nil nil nil)
	   (read-file-name "Write JSON file: " default-directory
			   (expand-file-name
			    (file-name-nondirectory (buffer-name))
			    default-directory)
			   nil nil))
	 (not current-prefix-arg)))

  (and confirm
       (file-exists-p filename)
       (or (y-or-n-p (format "File `%s' exists; overwrite? " filename))
	   (error "Canceled")))

  (let ((table (copy-hash-table keyfreq-table)))

    ;; Merge with the values in `keyfreq-file'
    (keyfreq-table-load table)

    (with-temp-file filename
      (insert (keyfreq-json-encode table)))))


(defun keyfreq-reset ()
  "Reset all statistics including those in the file."
  (interactive)
  (when (yes-or-no-p (concat "Delete keyfreq file? You will lose all your stats. "))
    ;; clear the hash table
    (clrhash keyfreq-table)
    ;; Deal with the file
    (when (keyfreq-file-is-unlocked)
      ;; Lock the file
      (keyfreq-file-claim-lock)
      ;; Check that we have the lock
      (if (eq (keyfreq-file-owner) (emacs-pid))
	  (unwind-protect
	      ;; if the file exists just delete it
	      (if (file-exists-p keyfreq-file)
		  (delete-file keyfreq-file))
	    ;; Release the lock.
	    (keyfreq-file-release-lock))))))


(defun keyfreq-file-owner ()
  "Return the PID of the Emacs process that owns the table file lock file."
  (let (owner)
    (and (file-exists-p keyfreq-file-lock)
	 (ignore-errors
	   (with-temp-buffer
	     (insert-file-contents-literally keyfreq-file-lock)
	     (goto-char (point-min))
	     (setq owner (read (current-buffer)))
	     (integerp owner)))
	 owner)))


(defun keyfreq-file-claim-lock ()
  (ignore-errors
    (write-region (number-to-string (emacs-pid)) nil
		  keyfreq-file-lock nil 'nomessage nil 'excl)))


(defun keyfreq-file-release-lock ()
  (when (file-exists-p keyfreq-file-lock)
    (delete-file keyfreq-file-lock)))


(defun keyfreq-file-is-unlocked ()
  ;; If the lock file exists....
  (if (file-exists-p keyfreq-file-lock)
      ;; If the process which has the lock does not exist
      (if (not (memql (keyfreq-file-owner) (list-system-processes)))
	  ;; Delete the lock
	  (delete-file keyfreq-file-lock)))
  ;; Check again the lock existence (just in case...)
  (not (file-exists-p keyfreq-file-lock)))


;;; ------------------------------------------------------------------
;;; Persistence
;;; ------------------------------------------------------------------

(defcustom keyfreq-incremental-save t
  "If non-nil, merge `keyfreq-table' into `keyfreq-file' in place.

A key that is already in the file keeps its line and only the
counter after the dot is rewritten.  A key that is not in the
file yet is appended as a new line, right before the closing
parenthesis of the list.  Every other byte of the file is left
untouched, so version control shows only the lines whose counter
really changed.

If nil, or if the file cannot be read as a keyfreq list, the
whole file is regenerated from scratch (the pre-1.8 behaviour)."
  :group 'keyfreq
  :type 'boolean)

(defcustom keyfreq-coding-system nil
  "Coding system used to read and write `keyfreq-file'.
Nil means detect it from the file, which is the safe default: an
existing file keeps its original encoding instead of being
re-encoded behind the user's back."
  :group 'keyfreq
  :type '(choice (const :tag "Detect from the file" nil)
                 coding-system))

(defvar keyfreq--corrupt-backup nil
  "Backup file created by the last `keyfreq-table-load' call, if any.")

(defun keyfreq--entry-key-p (key)
  "Return non-nil when KEY looks like a `(major-mode . command)' pair."
  (and (consp key) (symbolp (car key)) (symbolp (cdr key))))

(defun keyfreq--writable-table (table)
  "Return a copy of TABLE keeping only the entries keyfreq wants to keep."
  (let ((copy (make-hash-table :test 'equal
                               :size (max 16 (hash-table-count table)))))
    (maphash (lambda (key count)
               (when (keyfreq--entry-key-p key)
                 (unless (keyfreq-match-p (cdr key))
                   (puthash key count copy))))
             table)
    copy))

(defun keyfreq--reading-coding-system ()
  "Coding system to read `keyfreq-file' with."
  (or keyfreq-coding-system 'undecided))

(defun keyfreq--writing-coding-system (&optional detected)
  "Coding system to write `keyfreq-file' with.
DETECTED is what Emacs found while reading the file; a concrete
coding system wins so that the file keeps its original encoding."
  (if (and detected (not (eq (coding-system-base detected) 'undecided)))
      detected
    (or keyfreq-coding-system 'utf-8-unix)))

(defun keyfreq--file-coding-system (&optional file)
  "Detect the coding system of an existing FILE, default `keyfreq-file'."
  (let ((target (or file keyfreq-file)))
    (when (file-exists-p target)
      (with-temp-buffer
        (condition-case nil
            (progn
              (insert-file-contents target nil 0 65536)
              buffer-file-coding-system)
          (error nil))))))

(defun keyfreq--counter-span (start end)
  "Return the (BEG . END) of the counter token at the tail of START..END.

Return nil when the entry is not laid out the way `prin1' writes
it, so that the caller can fall back to a full rewrite."
  (save-excursion
    (goto-char end)
    (skip-chars-backward " \t\n\r" start)
    (when (and (> (point) start) (eq (char-before) ?\)))
      (goto-char (1- (point)))
      (skip-chars-backward " \t\n\r" start)
      (let ((num-end (point)))
        (skip-chars-backward "0-9" start)
        (when (and (< (point) num-end)
                   (> (point) start)
                   (memq (char-before) '(?\s ?\t ?\n ?\r)))
          (cons (point) num-end))))))

(defun keyfreq--scan-entries ()
  "Index the entries of the current buffer.

Return a cons (INDEX . SEEN).  INDEX maps an entry key to the
buffer span of its counter; SEEN holds every key found in the
file, including the ones whose counter could not be located.

Signal an error when the buffer is not a complete keyfreq list.
Writing an in-place patch into a damaged file would corrupt it
further, so the caller falls back to a full rewrite instead."
  (let ((index (make-hash-table :test 'equal :size 512))
        (seen (make-hash-table :test 'equal :size 512))
        (form nil))
    (goto-char (point-min))
    (skip-chars-forward " \t\n\r")
    (unless (eq (char-after) ?\()
      (error "Keyfreq file does not start with a list"))
    (forward-char 1)                    ; step into the outer list
    (while (progn
             (skip-chars-forward " \t\n\r")
             (not (or (eobp) (eq (char-after) ?\)))))
      (let ((start (point)))
        (setq form (read (current-buffer)))     ; signals on damage
        (when (and (consp form) (consp (car form)) (integerp (cdr form)))
          (puthash (car form) t seen)
          (when (not (gethash (car form) index))
            (let ((span (keyfreq--counter-span start (point))))
              (when span
                (puthash (car form) span index)))))))
    (skip-chars-forward " \t\n\r")
    (unless (eq (char-after) ?\))
      (error "Keyfreq file is not terminated by a closing parenthesis"))
    (cons index seen)))

(defun keyfreq--closing-paren-pos ()
  "Return the position of the `)' that closes the entry list."
  (save-excursion
    (goto-char (point-max))
    (skip-chars-backward " \t\n\r")
    (when (eq (char-before) ?\))
      (1- (point)))))

(defun keyfreq--write-file (contents file &optional coding)
  "Write CONTENTS to FILE atomically, preserving FILE's file modes."
  (let* ((target (expand-file-name file))
         (dir (file-name-directory target))
         (modes (or (ignore-errors (file-modes target))
                    (logand #o666 (default-file-modes))))
         (coding (or coding keyfreq-coding-system 'utf-8-unix))
         (tmp (make-temp-file (expand-file-name ".keyfreq-" dir) nil ".tmp")))
    (unwind-protect
        (progn
          (let ((coding-system-for-write coding))
            (write-region contents nil tmp nil 'nomessage))
          (when modes (ignore-errors (set-file-modes tmp modes)))
          (condition-case nil
              (rename-file tmp target t)
            ;; Windows refuses to rename onto an existing file.
            (error
             (let ((coding-system-for-write coding))
               (write-region contents nil target nil 'nomessage))
             (ignore-errors (delete-file tmp)))))
      (when (file-exists-p tmp)
        (ignore-errors (delete-file tmp))))))

(defun keyfreq--merge-in-place (pending &optional file)
  "Merge the deltas of PENDING into FILE without regenerating it.

Existing counters are rewritten in place and unknown keys are
appended as new lines.  Signals an error if the file cannot be
patched safely; the caller then falls back to a full rewrite."
  (let* ((target (or file keyfreq-file))
         (updates nil)
        (additions nil)
        (buffer (generate-new-buffer " *keyfreq-merge*" t)))
    (unwind-protect
        (with-current-buffer buffer
          (let ((coding-system-for-read (keyfreq--reading-coding-system)))
            (insert-file-contents target))
          (when (zerop (buffer-size))
            (error "Keyfreq file is empty"))
          (let ((coding (keyfreq--writing-coding-system buffer-file-coding-system)))
            (let* ((scan (keyfreq--scan-entries))
                   (index (car scan))
                   (seen (cdr scan)))
              (maphash
               (lambda (key count)
                 (let ((span (gethash key index)))
                   (cond
                    ((null span)
                     (if (gethash key seen)
                         ;; The entry is in the file but its counter could
                         ;; not be located: fall back to a full rewrite.
                         (error "Cannot locate the counter of %S" key)
                       (push (cons key count) additions)))
                    (t
                     (let* ((old (string-to-number
                                  (buffer-substring-no-properties
                                   (car span) (cdr span))))
                            (new (+ old count)))
                       (unless (= old new)
                         (push (list (car span) (cdr span) (number-to-string new))
                               updates)))))))
               pending)
              ;; Nothing to change means do not touch the file at all, so
              ;; the mtime (and any file watcher) stays quiet.
              (when (or updates additions)
                ;; Rewrite counters from the end of the buffer backwards so
                ;; that the spans taken from the index stay valid.
                (dolist (update (sort updates (lambda (a b) (> (car a) (car b)))))
                  (goto-char (nth 0 update))
                  (delete-region (nth 0 update) (nth 1 update))
                  (insert (nth 2 update)))
                ;; Append keys that are not in the file yet, in a stable
                ;; order, just before the closing parenthesis.
                (when additions
                  (setq additions
                        (sort additions
                              (lambda (a b)
                                (string< (prin1-to-string (car a))
                                         (prin1-to-string (car b))))))
                  (goto-char (or (keyfreq--closing-paren-pos)
                                 (error "Keyfreq file has no closing parenthesis")))
                  (unless (or (bobp) (bolp)) (insert "\n"))
                  (dolist (entry additions)
                    (prin1 (cons (car entry) (cdr entry)) (current-buffer))
                    (insert "\n")))
                (keyfreq--write-file (buffer-string) target coding)))))
      (kill-buffer buffer))))

(defun keyfreq--save-full (table)
  "Regenerate `keyfreq-file' from TABLE merged with the file on disk.

TABLE itself is never modified, so a failed write can safely be
retried without counting the file contents twice."
  (let ((merged (copy-hash-table table)))
    (keyfreq-table-load merged)
    (let ((content
           (with-temp-buffer
             ;; `keyfreq-list' accumulates by prepending, so its `no-sort'
             ;; output lists the entries in reverse order.  Writing that
             ;; directly means the next save reverses the file again and
             ;; version control sees a full rewrite on every save, so put
             ;; the natural order back.
             (let ((l (reverse (cdr (keyfreq-list merged 'no-sort)))))
               (insert "(")
               (dolist (item l)
                 (prin1 item (current-buffer))
                 ;; One command per line keeps the file readable.
                 (insert "\n"))
               (insert ")"))
             (buffer-string))))
      (keyfreq--write-file content keyfreq-file
                           (keyfreq--writing-coding-system
                            (keyfreq--file-coding-system))))))

(defun keyfreq--write-rollup (pending)
  "Write PENDING to `keyfreq-file', regenerating it if it cannot be patched."
  (condition-case err
      (progn
        (if (and keyfreq-incremental-save
                 (file-exists-p keyfreq-file)
                 (> (file-attribute-size (file-attributes keyfreq-file)) 0))
            (keyfreq--merge-in-place pending)
          (keyfreq--save-full pending))
        t)
    (error
     (message "keyfreq: in-place save failed (%s); regenerating file"
              (error-message-string err))
     (condition-case err
         (progn (keyfreq--save-full pending) t)
       (error
        (message "keyfreq: cannot save %s: %s"
                 keyfreq-file (error-message-string err))
        nil)))))

(defun keyfreq--save-locked (table)
  "Write TABLE to disk, assuming this process holds the lock.

The daily archive is written first and is authoritative; the rollup in
`keyfreq-file' is a materialised view that can be rebuilt from it.
Return non-nil when the data reached the disk.  TABLE is cleared only
after the data is safely archived, so a failed write can be retried
without losing or duplicating counters."
  (when (and keyfreq--rollup-dirty
             keyfreq-daily-archive
             (equal keyfreq--rollup-dirty (expand-file-name keyfreq-file)))
    (condition-case err
        (keyfreq-rebuild-rollup)
      (error (message "keyfreq: rollup rebuild failed: %s"
                      (error-message-string err)))))
  (let ((pending (keyfreq--writable-table table)))
    (if (zerop (hash-table-count pending))
        ;; Everything in TABLE is filtered out, nothing to write.
        (progn (clrhash table) t)
      (let ((archived
             (if keyfreq-daily-archive
                 (condition-case err
                     (progn (keyfreq--archive-day pending) t)
                   (error
                    (message "keyfreq: cannot write the daily archive (%s); keeping the counters for the next save"
                             (error-message-string err))
                    nil))
               t)))
        (cond
         ((not archived) nil)           ; nothing written, keep the deltas
         (t
          (let ((ok (keyfreq--write-rollup pending)))
            ;; the deltas are safe in the archive either way
            (clrhash table)
            (unless ok
              (setq keyfreq--rollup-dirty (expand-file-name keyfreq-file)))
            ok)))))))

(defun keyfreq-table-save (table &optional mustsave)
  "Append all values from the specified TABLE into the
`keyfreq-file' as a sexp of an alist.  Then resets the TABLE
if it was successfully merged.

The file is updated in place: an entry that already exists keeps
its line and only its counter is rewritten, while unknown
entries are appended right before the closing parenthesis.  Bind
`keyfreq-incremental-save' to nil to regenerate the whole file
instead.

If MUSTSAVE is t, this function tries to save the table until it
gets the lock and successfully saves it.  If MUSTSAVE is nil, it
does nothing if the table cannot be saved."

  ;; Avoid adding nothing to the file
  (unless (zerop (hash-table-count table))
    (let ((done nil))
      ;; Check that the lock file doesn't exist
      (while (not done)
        (if (not (keyfreq-file-is-unlocked))
            ;; Somebody else is writing; retry only if we must.
            (setq done (not mustsave))
          ;; Lock the file
          (keyfreq-file-claim-lock)
          ;; Check that we have the lock
          (if (not (eq (keyfreq-file-owner) (emacs-pid)))
              (setq done (not mustsave))
            (unwind-protect
                (progn
                  (keyfreq--save-locked table)
                  (setq done t))
              (keyfreq-file-release-lock))))
        (when (and (not done) mustsave)
          ;; We must save right now, so keep trying to get the lock.
          (sleep-for 0.1))))))

(defun keyfreq-sort-file (&optional filename)
  "Rewrite FILENAME (default `keyfreq-file') with entries sorted by key.

This is a one-off normalisation.  Sorting the file makes later
in-place updates produce minimal, line-aligned diffs."
  (interactive)
  (let* ((file (expand-file-name (or filename keyfreq-file)))
         (entries nil))
    (unless (file-exists-p file)
      (user-error "No such file: %s" file))
    (with-temp-buffer
      (let ((coding-system-for-read (or keyfreq-coding-system 'undecided)))
        (insert-file-contents file))
      (goto-char (point-min))
      (skip-chars-forward " \t\n\r")
      (when (eq (char-after) ?\() (forward-char 1))
      (condition-case nil
          (while (progn
                   (skip-chars-forward " \t\n\r")
                   (not (or (eobp) (eq (char-after) ?\)))))
            (push (read (current-buffer)) entries))
        (error nil)))
    (unless entries
      (user-error "No entries found in %s" file))
    (let ((content
           (with-temp-buffer
             (insert "(")
             (dolist (entry (sort entries
                                  (lambda (a b)
                                    (string< (prin1-to-string a)
                                             (prin1-to-string b)))))
               (prin1 entry (current-buffer))
               (insert "\n"))
             (insert ")")
             (buffer-string))))
      (if (not (keyfreq-file-is-unlocked))
          (user-error "Keyfreq file is locked by another Emacs")
        (keyfreq-file-claim-lock)
        (unwind-protect
            (progn
              (keyfreq--write-file content file
                                   (keyfreq--writing-coding-system
                                    (keyfreq--file-coding-system)))
              (message "keyfreq: sorted %d entries in %s"
                       (length entries) file))
          (keyfreq-file-release-lock))))))


(defun keyfreq--backup-file ()
  "Copy `keyfreq-file' aside and return the backup name."
  (let* ((base (concat keyfreq-file ".corrupt-"
                       (format-time-string "%Y%m%d-%H%M%S")))
         (name base)
         (i 1))
    (while (file-exists-p name)
      (setq name (format "%s-%d" base (setq i (1+ i)))))
    (copy-file keyfreq-file name t)
    name))

(defun keyfreq-table-load (table)
  "Load all values from the `keyfreq-file' and add them in the TABLE.
The table is not reset, so the values are appended to the table.
An empty file simply contributes nothing.

A damaged or truncated file is never allowed to destroy the
statistics: the original is copied to
`keyfreq-file.corrupt-<timestamp>' first, and every entry that can
still be read is salvaged.  `keyfreq--corrupt-backup' names the
backup that was created, if any."
  (setq keyfreq--corrupt-backup nil)
  (when (file-exists-p keyfreq-file)
    (let ((entries nil) (damaged nil))
      (with-temp-buffer
        (let ((coding-system-for-read (keyfreq--reading-coding-system)))
          (insert-file-contents keyfreq-file))
        (goto-char (point-min))
        (skip-chars-forward " \t\n\r")
        (cond
         ((eobp))                       ; empty file: nothing to load
         ((eq (char-after) ?\()         ; the expected shape
          (forward-char 1)
          (condition-case nil
              (while (progn
                       (skip-chars-forward " \t\n\r")
                       (not (or (eobp) (eq (char-after) ?\)))))
                (push (read (current-buffer)) entries))
            (end-of-file nil)           ; truncated tail: keep the prefix
            (error (setq damaged t)))
          ;; A complete keyfreq list always ends with a parenthesis.
          (save-excursion
            (goto-char (point-max))
            (skip-chars-backward " \t\n\r")
            (unless (eq (char-before) ?\)) (setq damaged t))))
         (t                             ; not a list at all
          (setq damaged t)
          (condition-case nil
              (let ((form (read (current-buffer))))
                (setq entries (if (listp form) form (list form))))
            (error nil)))))
      (setq entries (nreverse entries))   ; keep the file's original order
      (when (and damaged (> (length entries) 0))
        (setq keyfreq--corrupt-backup
              (ignore-errors (keyfreq--backup-file)))
        (message "keyfreq: %s looks damaged; kept a copy in %s and salvaged %d entries"
                 keyfreq-file (or keyfreq--corrupt-backup "?") (length entries)))
      (dolist (entry entries)
        (when (and (listp entry) (consp (car entry)) (integerp (cdr entry)))
          (unless (keyfreq-match-p (cdr (car entry)))
            (puthash (car entry)
                     (+ (gethash (car entry) table 0) (cdr entry))
                     table)))))))


;;;###autoload
(define-minor-mode keyfreq-autosave-mode
  "Keyfreq Autosave mode automatically saves
`keyfreq-table' every `keyfreq-autosave-timeout' seconds
and when emacs is killed."
  :global t
  :init-value nil
  :lighter nil
  :keymap nil
  :group 'keyfreq

  (when keyfreq-autosave--timer
    (cancel-timer keyfreq-autosave--timer)
    (setq keyfreq-autosave--timer nil))

  (if keyfreq-autosave-mode
      (progn
	(setq keyfreq-autosave--timer
	      (run-at-time t keyfreq-autosave-timeout
			   'keyfreq-autosave--do))
	(add-hook 'kill-emacs-hook 'keyfreq-mustsave--do))
    (keyfreq-mustsave--do)
    (remove-hook 'kill-emacs-hook 'keyfreq-mustsave--do)))


(defcustom keyfreq-autosave-timeout 600
  "How often in seconds `keyfreq-table' should be saved
when `keyfreq-autosave-mode' is enabled.  Setting this
value will take effect only after (re)enabling
`keyfreq-autosave-mode'."
  :group 'keyfreq
  :type 'number)


(defvar keyfreq-autosave--timer nil)


(defun keyfreq-autosave--do ()
  "Function executed periodically to save the `keyfreq-table' in `keyfreq-file'."
  (keyfreq-table-save keyfreq-table))


(defun keyfreq-mustsave--do ()
  "Function executed when we close Emacs."
  (keyfreq-table-save keyfreq-table t))


;;;###autoload
(defun keyfreq-save-now ()
  "Save keyfreq data now."
  (interactive)
  (keyfreq-mustsave--do)
  (message "keyfreq data saved into %s" keyfreq-file))

(provide 'keyfreq)

;;; keyfreq.el ends here
