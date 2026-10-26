;;; keyfreq.el --- track command frequencies -*- coding: utf-8; lexical-binding: t; -*-
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

(require 'cl-lib)
(require 'json)

(defgroup keyfreq nil
  "Customization group for Keyfreq mode.
This mode stores number of times each command was called and
provides it as a statistical data."
  :package-version '(keyfreq . "1.7")
  :group 'local
  :prefix "keyfreq")

(defcustom keyfreq-record-prompts t
  "When non-nil, also record the keys that prompts read directly.

Commands such as `query-replace' read their per-hit keys outside the
command loop, so `pre-command-hook' never sees them.  Advising
`read-event', `read-char' and `read-key' recovers them.  Because no real
command runs for those keys they are counted under the pseudo command
`keyfreq-prompt', which `keyfreq-excluded-commands' can exclude in turn."
  :group 'keyfreq
  :type 'boolean)

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
      (progn
        (add-hook 'pre-command-hook 'keyfreq-pre-command-hook)
        (when keyfreq-record-prompts (keyfreq--enable-prompt-advice)))
    (remove-hook 'pre-command-hook 'keyfreq-pre-command-hook)
    (keyfreq--disable-prompt-advice)))


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
  :type '(repeat string))

(defcustom keyfreq-coding-system nil
  "Coding system used to read and write `keyfreq-file'.
Nil means detect it from the file, which is the safe default: an
existing file keeps its original encoding instead of being
re-encoded behind the user's back."
  :group 'keyfreq
  :type '(choice (const :tag "Detect from the file" nil)
                 coding-system))

(defvar keyfreq-table (make-hash-table :test 'equal :size 128)
  "Hash table storing number of times each command was called in each major mode
since the last time the frequencies were saved in `keyfreq-file'.")

(defvar keyfreq-excluded-commands '()
  "List of commands excluded by keyfreq.")

(defvar keyfreq--excluded-filter nil
  "Cached regexp built from `keyfreq-excluded-regexp'.")
(defvar keyfreq--excluded-filter-for 'keyfreq--unset
  "The value of `keyfreq-excluded-regexp' the filter was built from.")

(defun keyfreq-match-p (cmd)
  "Return t if CMD is in `keyfreq-excluded-commands'
or matches `keyfreq-excluded-regexp'."
  ;; HACK Inspire by `consult--regexp-filter'
  (or (memq cmd keyfreq-excluded-commands)
      (when keyfreq-excluded-regexp
        ;; this runs on every keystroke, so the filter is cached
        (unless (eq keyfreq--excluded-filter-for keyfreq-excluded-regexp)
          (setq keyfreq--excluded-filter
                (mapconcat (lambda (x) (concat "\\(?:" x "\\)"))
                           keyfreq-excluded-regexp "\\|")
                keyfreq--excluded-filter-for keyfreq-excluded-regexp))
        (string-match-p keyfreq--excluded-filter (symbol-name cmd)))))


(defconst keyfreq-prompt-command 'keyfreq-prompt
  "Pseudo command standing for keys read outside the command loop.")

(defvar keyfreq--prompt-advised nil
  "Non-nil once the read functions carry `keyfreq--record-prompt'.")

(defun keyfreq--count-command (mode command)
  "Add one invocation of COMMAND in MODE to `keyfreq-table'."
  (let* ((key (cons mode command))
         (count (gethash key keyfreq-table)))
    (puthash key (if count (1+ count) 1) keyfreq-table)))

(defcustom keyfreq-record-keys t
  "When non-nil, record the key sequence that invoked each command.

`keyfreq' counts commands and resolves their keys later with
`where-is-internal', which cannot tell which of two bindings was
actually used and cannot tell which character was typed (every typed
character is the single command `self-insert-command').  Recording
`this-command-keys' at invocation time gives the exact key; it is kept
in a side file so the existing counters keep working unchanged."
  :group 'keyfreq
  :type 'boolean)

(defcustom keyfreq-key-file nil
  "File recording the keys that invoked each command.
Nil means `keyfreq-file' with `.keys' appended."
  :group 'keyfreq
  :type '(choice (const :tag "Derive from keyfreq-file" nil) file))

(defcustom keyfreq-daily-archive t
  "When non-nil, keep one file per day under `keyfreq-daily-directory'.

`keyfreq-file' stays the cumulative rollup that the \"All time\" view
reads, and `keyfreq-key-file' the all-time key total.  The daily
archives are the authority for the Today / 7 days / 30 days and month
views -- one counter file and one key file per day -- and they make the
rollup rebuildable with `keyfreq-rebuild-rollup'."
  :group 'keyfreq
  :type 'boolean)

(defcustom keyfreq-daily-directory nil
  "Directory holding the per-day archives.
Nil means a `keyfreq-days' directory next to `keyfreq-file'."
  :group 'keyfreq
  :type '(choice (const :tag "Next to keyfreq-file" nil) directory))

(defcustom keyfreq-daily-retention nil
  "Number of days of daily archives to keep, nil to keep them all.

When set, `keyfreq-compact-archives' folds every daily archive older
than this into a monthly archive: 2026-07.log then holds the sum of
the days of July 2026, and the day files it was built from are gone.
The leftovers are compacted once a day, while saving.

A month archive carries exactly the counts of the days it replaces, so
no period loses data: only the resolution of the older end of the
history changes, from one day to one month.  The value must be at
least 30, because the Last 30 days view reads day archives."
  :group 'keyfreq
  :type '(choice (const :tag "Keep every day" nil)
                 (integer :tag "Days")))

(defcustom keyfreq-monthly-retention nil
  "Number of months of monthly archives to keep, nil to keep them all.

The second step down: once `keyfreq-daily-retention' has folded the
days into months, this folds the months older than it into one file per
year -- 2023.log then holds what the months of 2023 held.  The archive
directory ends up layered, fine at the recent end and coarse at the old
one:

    last 30 days           one file per day
    older, up to a year    one file per month
    older still            one file per year

All time is the sum of the three layers, and no count is either lost or
counted twice: what changes is the resolution of the old end."
  :group 'keyfreq
  :type '(choice (const :tag "Keep every month" nil)
                 (integer :tag "Months")))

(defvar keyfreq-key-table (make-hash-table :test 'equal)
  "Pending key counts, keyed by (MAJOR-MODE COMMAND KEY-DESCRIPTION).")

(defvar keyfreq--last-keys nil
  "Key description of the invocation that is about to be recorded.")

(defun keyfreq--add-key (mode command keys)
  "Add one (MODE COMMAND KEYS) event to `keyfreq-key-table'."
  (when keyfreq-record-keys
    (let* ((key (list mode command keys))
           (count (gethash key keyfreq-key-table)))
      (puthash key (if count (1+ count) 1) keyfreq-key-table))))

(defun keyfreq--record-prompt (value)
  "Count VALUE, an event read outside the command loop, then return it.

Used as `:filter-return' advice on the functions that read single events,
so that the keys of `y-or-n-p' and `query-replace' are not lost."
  (when (and keyfreq-record-keys
             keyfreq-record-prompts
             (or (integerp value)
                 (and (vectorp value) (> (length value) 0))
                 (and (consp value) (integerp (car value)))))
    (let ((keys (ignore-errors
                  (key-description (if (vectorp value) value (vector value))))))
      (when (and (stringp keys) (not (string-empty-p keys)))
        (keyfreq--count-command major-mode keyfreq-prompt-command)
        (keyfreq--add-key major-mode keyfreq-prompt-command keys))))
  value)

(defun keyfreq--enable-prompt-advice ()
  "Start recording the keys that prompts read directly."
  (unless keyfreq--prompt-advised
    (dolist (function '(read-event read-char read-key))
      (advice-add function :filter-return #'keyfreq--record-prompt))
    (setq keyfreq--prompt-advised t)))

(defun keyfreq--disable-prompt-advice ()
  "Stop recording the keys that prompts read directly."
  (when keyfreq--prompt-advised
    (dolist (function '(read-event read-char read-key))
      (ignore-errors (advice-remove function #'keyfreq--record-prompt)))
    (setq keyfreq--prompt-advised nil)))

(defun keyfreq-pre-command-hook ()
  "Record command execution in `keyfreq-table' hash.

Also counts the key sequence that invoked the command when
`keyfreq-record-keys' is non-nil."
  (keyfreq--record-keys)
  (when keyfreq-record-keys
    (setq keyfreq--last-keys
          (ignore-errors (key-description (this-command-keys)))))
  (let ((command real-last-command) count)
    (when (and command (symbolp command))
      (setq count (gethash (cons major-mode command) keyfreq-table))
      (unless (keyfreq-match-p command)
        (puthash (cons major-mode command) (if count (1+ count) 1)
                 keyfreq-table)
        ))))

;;; ------------------------------------------------------------------
;;; Recorded keys
;;; ------------------------------------------------------------------

(defun keyfreq--key-file ()
  "Return the file holding the recorded keys."
  (or keyfreq-key-file (concat keyfreq-file ".keys")))

(defun keyfreq--key-entry-p (key)
  "Return non-nil when KEY looks like a recorded (MODE COMMAND KEYS) entry."
  (and (consp key)
       (null (nthcdr 3 key))
       (symbolp (nth 0 key))
       (symbolp (nth 1 key))
       (stringp (nth 2 key))))

(defun keyfreq--table-copy (table)
  "Return a copy of TABLE."
  (let ((copy (make-hash-table :test 'equal :size (hash-table-count table))))
    (maphash (lambda (key count) (puthash key count copy)) table)
    copy))

(defun keyfreq--record-keys ()
  "Count the key sequence of the command recorded by this invocation.

`real-last-command' is the command that just ran, and
`keyfreq--last-keys' holds the keys that invoked it, so the two stay
aligned exactly like the command counter they accompany."
  (when (and keyfreq-record-keys
             keyfreq--last-keys
             (symbolp real-last-command)
             (not (string-empty-p keyfreq--last-keys)))
    (keyfreq--add-key major-mode real-last-command keyfreq--last-keys)))

(defun keyfreq--save-keys ()
  "Write the pending `keyfreq-key-table' deltas to disk.

Today's archive under `keyfreq-daily-directory' is written first and is
authoritative for the period views; `<keyfreq-file>.keys' is patched with
the same deltas afterwards so it keeps holding the all-time total.  The
two are written in that order for the same reason the counter archive
comes before the rollup: a snapshot that is behind by one save can be
repaired, a day that never reached the disk cannot.

Return non-nil when the data reached the disk, so the caller can keep the
deltas in memory when it did not."
  (when keyfreq-record-keys
    (let ((pending (make-hash-table :test 'equal)))
      (maphash (lambda (key count)
                 (when (and (keyfreq--key-entry-p key)
                            (> count 0)
                            ;; the same exclusions the counters obey, so the
                            ;; two files never disagree about a command
                            (not (keyfreq-match-p (nth 1 key))))
                   (puthash key count pending)))
               keyfreq-key-table)
      (if (zerop (hash-table-count pending))
          (progn (clrhash keyfreq-key-table) t)
        (let ((archived
               (if keyfreq-daily-archive
                   (condition-case err
                       (progn (keyfreq--archive-day-keys pending) t)
                     (error
                      (message "keyfreq: cannot write the daily key archive (%s); keeping the counters for the next save"
                               (error-message-string err))
                      nil))
                 t)))
          (when archived
            (keyfreq--merge-key-file pending)
            (clrhash keyfreq-key-table))
          archived)))))

(defun keyfreq--merge-key-file (pending)
  "Merge PENDING into `<keyfreq-file>.keys', the all-time key total.
A file that cannot be patched in place is backed up and rewritten, or
every later save would fail on it."
  (let ((file (keyfreq--key-file)))
    (if (and (file-exists-p file)
             (> (file-attribute-size (file-attributes file)) 0))
        (condition-case err
            (keyfreq--merge-in-place pending file)
          (error
           (message "keyfreq: cannot merge into %s (%s); rewriting it"
                    file (error-message-string err))
           (ignore-errors (keyfreq--backup-file file))
           (let ((merged (keyfreq--table-copy pending)))
             (maphash (lambda (key count)
                        (puthash key (+ count (gethash key merged 0)) merged))
                      (keyfreq--read-file-entries file))
             (keyfreq--write-table merged file))))
      (keyfreq--write-table pending file))))

(defun keyfreq--recorded-keys ()
  "Return a table mapping (MODE COMMAND) to an alist of (KEYS . COUNT)."
  (let ((table (make-hash-table :test 'equal))
        (entries (keyfreq--read-file-entries (keyfreq--key-file))))
    (when entries
      (maphash (lambda (key count)
                 (when (keyfreq--key-entry-p key)
                   (let* ((pair (list (nth 0 key) (nth 1 key)))
                          (cell (gethash pair table)))
                     (puthash pair (cons (cons (nth 2 key) count) cell) table))))
               entries))
    table))

(defun keyfreq--key-table-entries ()
  "Return a table mapping (MODE COMMAND KEYS) to a number of presses.

Same shape as a key archive, so the all-time view and a period view can
be read by the same code."
  (let ((table (make-hash-table :test 'equal))
        (entries (keyfreq--read-file-entries (keyfreq--key-file))))
    (when entries
      (maphash (lambda (key count)
                 (when (keyfreq--key-entry-p key)
                   (puthash key (+ (gethash key table 0) count) table)))
               entries))
    table))

(defun keyfreq-groups-major-modes (table)
  "Group major modes in TABLE by command.
Return a hash table where each entry has COMMAND as key and
COUNTER as value."
  (let ((new-table (make-hash-table :test 'equal :size 128)))
    (maphash (lambda (k v)
	       (puthash (cdr k) (+ (gethash (cdr k) new-table 0) v) new-table))
	     table)
    new-table))


(defun keyfreq-filter-major-mode (table mode)
  "Leave the frequencies of the specified major MODE.
Return a hash table where each entry has COMMAND as key and
COUNTER as value."

  (let ((new-table (make-hash-table :test 'equal :size 128)))
    (maphash (lambda (k v)
	       (when (eq (car k) mode)
		 (puthash (cdr k) (+ (gethash (cdr k) new-table 0) v) new-table)))
	     table)
    new-table))


(defun keyfreq-used-major-modes (table)
  "Return a list with the used major modes (major modes
contained in the TABLE)."
  (let ((seen (make-hash-table :test 'eq))
        (modes nil))
    (maphash (lambda (k _v)
               (unless (gethash (car k) seen)
                 (puthash (car k) t seen)
                 (push (car k) modes)))
             table)
    modes))


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
      ((= limit -1) (lambda (_k v) (setq sum (+ sum v))))
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
the middle; if it is \='raw each line will contain number an
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

  (keyfreq-where-is \\='org-return (keyfreq--mode-keymap \\='org-mode))

Since Emacs 30 `where-is-internal' takes (DEFINITION KEYMAP FIRSTONLY
NOINDIRECT); a non-nil KEYMAP means `search this keymap and the global
keymap'."
  (mapconcat 'key-description
             (where-is-internal command (or keymaps (list global-map)))
             ", "))

(defun keyfreq--mode-keymap (mode)
  "Return MODE's own keymap when it follows the `<mode>-map' convention."
  (let ((symbol (intern (concat (symbol-name mode) "-map"))))
    (and (boundp symbol)
         (keymapp (symbol-value symbol))
         (symbol-value symbol))))

(defun keyfreq--mode-keymaps (mode)
  "Return the keymap to resolve MODE's bindings in.

Major modes bind most of their commands in their own keymap rather than
in `global-map'; resolving against `global-map' alone silently drops
them (for `org-mode' that was 42% of all key presses).  Falls back to
`global-map' when the mode has no `<mode>-map'."
  (or (keyfreq--mode-keymap mode) (list global-map)))

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
  "When non-nil, `keyfreq-html-v2' also offers one period per year and month.

They come from the archives under `keyfreq-daily-directory', not from
version control: each period is what that year or that month added, not
the whole picture as it stood at its end.  The periods are disjoint and
add up to All time.  A year appears once its months have been folded
into a year archive, and those months stop being offered.

Nothing outside the keyfreq data files is consulted.  Set this to nil to
keep only the Today / 7 days / 30 days / All time periods."
  :group 'keyfreq
  :type 'boolean)

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

(defun keyfreq--read-file-entries (file)
  "Parse FILE as a keyfreq log."
  (when (file-exists-p file)
    (keyfreq--read-log-entries
     (with-temp-buffer
       (let ((coding-system-for-read
              (or keyfreq-coding-system 'undecided)))
         (insert-file-contents file))
       (buffer-string)))))

(defun keyfreq--snapshot (period count keys)
  "Return a report snapshot for PERIOD.

COUNT maps (MODE . COMMAND) to a number of invocations and KEYS maps
(MODE COMMAND KEYS) to a number of presses.  Both belong to the same
period, so the heat map never has to borrow the key split of another
one.  Either table may be nil; the accessors then return an empty one."
  (cons period (list :count (or count (make-hash-table :test 'equal))
                     :keys (or keys (make-hash-table :test 'equal)))))

(defun keyfreq--snapshot-count (snapshot)
  "Return the (MODE . COMMAND) table of SNAPSHOT, never nil."
  (plist-get (cdr snapshot) :count))

(defun keyfreq--snapshot-keys (snapshot)
  "Return the (MODE COMMAND KEYS) table of SNAPSHOT, never nil."
  (plist-get (cdr snapshot) :keys))

(defun keyfreq--history-payload (snapshots)
  "Return (PERIODS NAMES ROWS KEY-NAMES KEY-ROWS) describing SNAPSHOTS.

ROWS is a list of (PERIOD-INDEX MODE-INDEX COMMAND-INDEX COUNT), where
the indexes point into NAMES.  KEY-ROWS is the same for the recorded
keys: (PERIOD-INDEX MODE-INDEX COMMAND-INDEX KEY-INDEX COUNT), with the
key index pointing into KEY-NAMES.  A period without recorded keys
contributes no KEY-ROWS and the renderer falls back to the all-time
split."
  (let ((periods nil)
        (names nil)
        (index (make-hash-table :test 'equal))
        (rows nil)
        (key-names nil)
        (key-index (make-hash-table :test 'equal))
        (key-rows nil)
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
                 (push name names)
                 (puthash name (1- (length names)) index)))
             (push (list period
                         (gethash mode-name index)
                         (gethash command-name index)
                         count)
                   rows))))
       (keyfreq--snapshot-count snapshot))
      (maphash
       (lambda (key count)
         (when (and (keyfreq--key-entry-p key) (> count 0))
           (let ((mode-name (symbol-name (nth 0 key)))
                 (command-name (symbol-name (nth 1 key)))
                 (key-name (nth 2 key)))
             (dolist (name (list mode-name command-name))
               (unless (gethash name index)
                 (push name names)
                 (puthash name (1- (length names)) index)))
             (unless (gethash key-name key-index)
               (push key-name key-names)
               (puthash key-name (1- (length key-names)) key-index))
             (push (list period
                         (gethash mode-name index)
                         (gethash command-name index)
                         (gethash key-name key-index)
                         count)
                   key-rows))))
       (keyfreq--snapshot-keys snapshot))
      (setq period (1+ period)))
    (list (nreverse periods) (nreverse names) (nreverse rows)
          (nreverse key-names) (nreverse key-rows))))

(defun keyfreq--json-history (periods names rows key-names key-rows)
  "Return `keyfreq--json-history-1' with HTML-significant characters escaped."
  (let ((json (keyfreq--json-history-1 periods names rows key-names key-rows)))
    (setq json (replace-regexp-in-string "<" "\\u003c" json t t))
    (setq json (replace-regexp-in-string ">" "\\u003e" json t t))
    (setq json (replace-regexp-in-string "&" "\\u0026" json t t))
    json))

(defun keyfreq--json-quoted (string)
  "Return STRING as a JSON string literal."
  (json-encode-string string))

(defun keyfreq--json-history-1 (periods names rows key-names key-rows)
  "Serialise the history as a JSON object.

Angle brackets and ampersands are escaped as \\u escapes so that the
payload can be embedded in a script element safely.  KEY-ROWS is the
per-period record of the keys that were actually pressed; it is emitted
alongside ROWS so a period view can draw its own key split."
  (concat
   "{\"periods\":["
   (mapconcat #'keyfreq--json-quoted periods ",")
   "],\"names\":["
   (mapconcat #'keyfreq--json-quoted names ",")
   "],\"rows\":["
   (mapconcat (lambda (row)
                (concat "[" (mapconcat #'number-to-string row ",") "]"))
              rows ",")
   "],\"keyNames\":["
   (mapconcat #'keyfreq--json-quoted key-names ",")
   "],\"keyRows\":["
   (mapconcat (lambda (row)
                (concat "[" (mapconcat #'number-to-string row ",") "]"))
              key-rows ",")
   "]}"))

;;; ------------------------------------------------------------------
;;; Daily archives
;;; ------------------------------------------------------------------

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

(defun keyfreq--daily-date (&optional days-ago)
  "Return the archive date for DAYS-AGO days before today, as YYYY-MM-DD.
The time is pinned to noon, so summer time cannot move the date."
  (let* ((now (decode-time))
         (time (encode-time 0 0 12 (- (nth 3 now) (or days-ago 0))
                            (nth 4 now) (nth 5 now))))
    (format-time-string "%Y-%m-%d" time)))

(defun keyfreq--daily-file (&optional days-ago)
  "Return the archive file for DAYS-AGO days before today."
  (expand-file-name (concat (keyfreq--daily-date days-ago) ".log")
                    (keyfreq--daily-dir)))

(defun keyfreq--month-date (&optional months-ago)
  "Return the archive month for MONTHS-AGO months before this one, as YYYY-MM.
The day is pinned to the 15th, so no month can be skipped or repeated."
  (let* ((now (decode-time))
         (time (encode-time 0 0 12 15 (- (nth 4 now) (or months-ago 0))
                            (nth 5 now))))
    (format-time-string "%Y-%m" time)))

(defun keyfreq--key-daily-file (&optional days-ago)
  "Return the recorded-keys archive for DAYS-AGO days before today.

It sits next to the counter archive of the same day, so a period reads
both halves of the same day from one directory, and the key split it
draws is the one that really belongs to that period."
  (expand-file-name (concat (keyfreq--daily-date days-ago) ".keys")
                    (keyfreq--daily-dir)))

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

(defun keyfreq--archive-day-keys (pending)
  "Add the recorded-key deltas in PENDING to today's key archive.

There is no baseline to copy aside: `<keyfreq-file>.keys' already holds
the all-time total, and this file only adds the missing time axis."
  (make-directory (keyfreq--daily-dir) t)
  (let ((file (keyfreq--key-daily-file)))
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

(defun keyfreq--range-key-table (days)
  "Return a table with the recorded keys of the last DAYS daily archives."
  (let ((table (make-hash-table :test 'equal)))
    (dotimes (i days)
      (let ((file (keyfreq--key-daily-file i)))
        (when (file-exists-p file)
          (maphash (lambda (key count)
                     (when (keyfreq--key-entry-p key)
                       (puthash key (+ (gethash key table 0) count) table)))
                   (keyfreq--read-file-entries file)))))
    table))

(defconst keyfreq--day-regexp "\\`[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\\."
  "Start of a file name holding one day of archives.")

(defconst keyfreq--month-regexp "\\`[0-9][0-9][0-9][0-9]-[0-9][0-9]\\."
  "Start of a file name holding one month of archives.")

(defconst keyfreq--archive-regexp
  "\\`[0-9][0-9][0-9][0-9]\\(-[0-9][0-9]\\(-[0-9][0-9]\\)?\\)?\\."
  "Start of a file name holding a year, a month or a day of archives.")

(defun keyfreq--dir-files (dir regexp)
  "Return the files of DIR matching REGEXP, oldest first."
  (when (file-directory-p dir)
    (sort (directory-files dir t regexp) #'string<)))

(defun keyfreq--daily-files ()
  "Return the daily counter archives, oldest first."
  (keyfreq--dir-files (keyfreq--daily-dir)
                      (concat keyfreq--day-regexp "log\\'")))

(defun keyfreq--daily-key-files ()
  "Return the daily recorded-key archives, oldest first."
  (keyfreq--dir-files (keyfreq--daily-dir)
                      (concat keyfreq--day-regexp "keys\\'")))

(defun keyfreq--archive-files ()
  "Return every counter archive, oldest first: years, months and days.

Sorting puts a fine archive before the coarse one that covers it --
2026-10-18.log, then 2026-10.log, then 2026.log -- so a period is only
complete once the last file of that period has been read."
  (keyfreq--dir-files (keyfreq--daily-dir)
                      (concat keyfreq--archive-regexp "log\\'")))

(defun keyfreq--archive-key-files ()
  "Return every recorded-key archive, oldest first: years, months and days."
  (keyfreq--dir-files (keyfreq--daily-dir)
                      (concat keyfreq--archive-regexp "keys\\'")))

(defun keyfreq--month-file (month)
  "Return the counter archive of MONTH, a YYYY-MM string."
  (expand-file-name (concat month ".log") (keyfreq--daily-dir)))

(defun keyfreq--month-key-file (month)
  "Return the recorded-key archive of MONTH, a YYYY-MM string."
  (expand-file-name (concat month ".keys") (keyfreq--daily-dir)))

(defun keyfreq--year-file (year)
  "Return the counter archive of YEAR, a YYYY string."
  (expand-file-name (concat year ".log") (keyfreq--daily-dir)))

(defun keyfreq--year-key-file (year)
  "Return the recorded-key archive of YEAR, a YYYY string."
  (expand-file-name (concat year ".keys") (keyfreq--daily-dir)))

(defun keyfreq--file-year (name)
  "Return the YYYY of NAME, or nil when it is not an archive.

Every archive falls in a year: a day and a month in the one they belong
to, and a year archive in its own."
  (when (string-match "\\`[0-9][0-9][0-9][0-9][-.]" name)
    (substring name 0 4)))


;;; ------------------------------------------------------------------
;;; Compaction
;;; ------------------------------------------------------------------

(defvar keyfreq--compact-attempt nil
  "Date of the last automatic compaction, as YYYY-MM-DD.

Compacting only ever has something to do once a day, so the date is
enough to keep a save from looking through the archive directory every
time.")

(defun keyfreq--compact-dir (&optional tier)
  "Return the staging directory of TIER.

TIER is `year' for the months that are becoming a year, and anything
else (nil included) for the days that are becoming a month.  The two
tiers stage their files apart, because a month waiting to become a year
and a day waiting to become a month are both named after a month.

Compacting happens in two steps: the archives are moved here first, and
only then folded into the coarser one.  An interrupted run therefore
leaves every count in one place, never in both -- which would have to be
counted twice -- and never in neither."
  (expand-file-name (if (eq tier 'year) "year" "day")
                    (expand-file-name ".compact" (keyfreq--daily-dir))))

(defun keyfreq--compact-commit (extension target &optional tier keep)
  "Fold the staged EXTENSION archives into the next coarser archive.

TIER is `year' to fold months into their year, anything else to fold
days into their month.  TARGET is called with the period -- a YYYY year
or a YYYY-MM month -- and returns the archive to write.  KEEP, when
given, filters the entries carried over.

The archive is written from the staging area alone -- the archive it
replaces has been moved there too -- so writing it again writes the same
counts again instead of adding them up a second time.  That is what makes
an interrupted run safe to finish: repeating this converges on the same
numbers.  Return the number of archives written."
  (let* ((year (eq tier 'year))
         (stage (keyfreq--compact-dir tier))
         (regexp (concat (if year keyfreq--month-regexp keyfreq--day-regexp)
                         extension "\\'"))
         (width (if year 4 7))
         (groups nil)
         (written 0))
    (dolist (file (keyfreq--dir-files stage regexp))
      (let* ((period (substring (file-name-nondirectory file) 0 width))
             (cell (assoc period groups)))
        (if cell
            (push file (cdr cell))
          (push (cons period (list file)) groups))))
    (dolist (group groups)
      (let* ((period (car group))
             (old (expand-file-name (concat period ".old." extension) stage))
             (table (make-hash-table :test 'equal)))
        (when (file-exists-p old)
          (maphash (lambda (key count)
                     (puthash key (+ count (gethash key table 0)) table))
                   (keyfreq--read-file-entries old)))
        (dolist (file (cdr group))
          (maphash (lambda (key count)
                     (when (or (null keep) (funcall keep key))
                       (puthash key (+ count (gethash key table 0)) table)))
                   (keyfreq--read-file-entries file)))
        (when (> (hash-table-count table) 0)
          (keyfreq--write-table table (funcall target period))
          (setq written (1+ written)))
        ;; the coarser archive holds them now, so the fine ones can go
        (dolist (file (cdr group))
          (delete-file file))
        (when (file-exists-p old)
          (delete-file old))))
    written))

(defun keyfreq--compact-finish ()
  "Fold whatever an interrupted run left staged into the coarser archives.

Return (MONTHS KEY-MONTHS YEARS KEY-YEARS): how many counter and key
month archives, then year archives, were written.  All zero when nothing
was pending.  Harmless to call at any time, and safe to repeat."
  (let ((months 0)
        (keys 0)
        (years 0)
        (year-keys 0))
    (dolist (tier '(nil year))
      (let ((stage (keyfreq--compact-dir tier)))
        (when (file-directory-p stage)
          (if tier
              (setq years (keyfreq--compact-commit "log" #'keyfreq--year-file tier)
                    year-keys (keyfreq--compact-commit
                               "keys" #'keyfreq--year-key-file
                               tier #'keyfreq--key-entry-p))
            (setq months (keyfreq--compact-commit "log" #'keyfreq--month-file)
                  keys (keyfreq--compact-commit
                        "keys" #'keyfreq--month-key-file nil
                        #'keyfreq--key-entry-p)))
          ;; it is empty now; if it is not, the next run looks again
          (ignore-errors (delete-directory stage)))))
    ;; the parent goes too, once both tiers are done
    (ignore-errors (delete-directory (expand-file-name ".compact"
                                                       (keyfreq--daily-dir))))
    (list months keys years year-keys)))

(defun keyfreq--compact-move (extension cutoff &optional tier)
  "Move the EXTENSION archives older than CUTOFF into the staging area.

TIER is `year' to move month archives that are becoming a year, anything
else to move day archives that are becoming a month.  CUTOFF is the
oldest date that stays at this resolution: a YYYY-MM month for the year
tier, a YYYY-MM-DD date otherwise.  Return the number moved."
  (let* ((year (eq tier 'year))
         (stage (keyfreq--compact-dir tier))
         (regexp (concat (if year keyfreq--month-regexp keyfreq--day-regexp)
                         extension "\\'"))
         (width (if year 4 7))
         (periods nil)
         (moved 0))
    (dolist (file (keyfreq--dir-files (keyfreq--daily-dir) regexp))
      (let ((name (file-name-base file)))
        (when (string< name (substring cutoff 0 (length name)))
          (let ((period (substring name 0 width)))
            (make-directory stage t)
            (rename-file file
                         (expand-file-name (file-name-nondirectory file) stage)
                         t)
            (unless (member period periods)
              (push period periods))
            (setq moved (1+ moved))))))
    ;; The coarser archive these belong to travels with them, so the
    ;; commit can write both halves back as one.
    (dolist (period periods)
      (let ((current (funcall (if (equal extension "keys")
                                  (if year #'keyfreq--year-key-file
                                    #'keyfreq--month-key-file)
                                (if year #'keyfreq--year-file
                                  #'keyfreq--month-file))
                              period)))
        (when (file-exists-p current)
          (make-directory stage t)
          (rename-file current
                       (expand-file-name (concat period ".old." extension) stage)
                       t))))
    moved))

(defun keyfreq--compact-locked (days months)
  "Fold days older than DAYS days into months, months older than MONTHS into years.

Either threshold may be nil, which skips that step.  The caller holds
the lock.  Return (DAYS-MOVED MONTHS-WRITTEN YEARS-WRITTEN), each
counting what an interrupted run had left behind."
  (if (not (file-directory-p (keyfreq--daily-dir)))
      (list 0 0 0)
    (let ((moved 0)
          (written 0)
          (folded 0))
      (dolist (done (list (keyfreq--compact-finish)))
        (setq written (+ written (nth 0 done)))
        (setq folded (+ folded (nth 2 done))))
      ;; Days become months first: the year step can only fold the month
      ;; archives once they exist.
      (when days
        (setq moved (keyfreq--compact-move
                     "log" (keyfreq--daily-date (1- days))))
        (keyfreq--compact-move "keys" (keyfreq--daily-date (1- days)))
        (dolist (done (list (keyfreq--compact-finish)))
          (setq written (+ written (nth 0 done)))
          (setq folded (+ folded (nth 2 done)))))
      (when months
        (keyfreq--compact-move "log" (keyfreq--month-date (1- months)) 'year)
        (keyfreq--compact-move "keys" (keyfreq--month-date (1- months)) 'year)
        (dolist (done (list (keyfreq--compact-finish)))
          (setq written (+ written (nth 0 done)))
          (setq folded (+ folded (nth 2 done)))))
      (list moved written folded))))

(defun keyfreq--compact-days (days)
  "Return DAYS as a retention `keyfreq-compact-archives' can use."
  (let ((number (and days (max 0 (truncate days)))))
    (cond
     ((null number)
      (user-error "Set `keyfreq-daily-retention', or pass a number of days"))
     ((< number 30)
      (user-error "Refusing to keep only %d days: the Last 30 days view reads day archives"
                  number))
     (t number))))

(defun keyfreq-compact-archives (&optional days months)
  "Fold old archives into coarser ones: days into months, months into years.

DAYS defaults to `keyfreq-daily-retention' and MONTHS to
`keyfreq-monthly-retention'; either may be nil, which skips that step.
Interactively a prefix argument overrides DAYS, and when the option is
nil the number is asked for.  DAYS has to be at least 30, because the
Last 30 days view reads day archives and a smaller value would take away
the files it needs.

Nothing is counted twice and nothing is lost: a coarser archive holds
exactly what the finer ones it replaced held, and `keyfreq-html-v2' and
`keyfreq-rebuild-rollup' read all three kinds alike.  What changes is the
resolution of the older end of the history, and the number of files.

Setting `keyfreq-daily-retention' or `keyfreq-monthly-retention' runs
this once a day on its own, while keyfreq saves."
  (interactive
   (list (or (and current-prefix-arg (prefix-numeric-value current-prefix-arg))
             keyfreq-daily-retention
             (read-number "Keep how many days of daily archives? " 90))
         keyfreq-monthly-retention))
  (let ((days (and days (keyfreq--compact-days days))))
    (keyfreq--with-file-lock
     (lambda ()
       (let* ((result (keyfreq--compact-locked days months))
              (moved (nth 0 result))
              (written (nth 1 result))
              (folded (nth 2 result)))
         (cond
          ((and (zerop moved) (zerop written) (zerop folded))
           (message "keyfreq: nothing to compact"))
          ((zerop moved)
           (message "keyfreq: recovered %d month and %d year archives"
                    written folded))
          (t
           (message "keyfreq: folded %d day archives into %d month and %d year archives"
                    moved written folded))))))))

(defun keyfreq--period-files (files key)
  "Return (PERIOD . FILES) for FILES, grouped by KEY, oldest first.

KEY is called with a file name and returns the period the file belongs
to, or nil for one that belongs to none.  A year archive belongs to its
year, a month archive to its month and its year, and a day archive to
its day, its month and its year."
  (let ((groups nil))
    (dolist (file files)
      (let ((period (funcall key (file-name-nondirectory file))))
        (when period
          (let ((cell (assoc period groups)))
            (if cell
                (push file (cdr cell))
              (push (cons period (list file)) groups))))))
    (nreverse (mapcar (lambda (group)
                        (cons (car group) (nreverse (cdr group))))
                      groups))))

(defun keyfreq--period-table (files &optional extra)
  "Return the sum of the archives in FILES, plus EXTRA."
  (let ((table (make-hash-table :test 'equal)))
    (when extra
      (maphash (lambda (key count)
                 (puthash key (+ count (gethash key table 0)) table))
               extra))
    (dolist (file files)
      (maphash (lambda (key count)
                 (puthash key (+ count (gethash key table 0)) table))
               (keyfreq--read-file-entries file)))
    table))

(defun keyfreq-rebuild-rollup ()
  "Rebuild `keyfreq-file' from the baseline plus every daily archive."
  (interactive)
  (keyfreq--with-file-lock #'keyfreq--rebuild-rollup-locked))

(defun keyfreq--rebuild-rollup-locked ()
  "Rebuild `keyfreq-file' while its lock is held."
  (let ((dir (keyfreq--daily-dir)))
    (unless (file-directory-p dir)
      (user-error "No daily archives in %s" dir))
    ;; A compaction that was interrupted has left day archives in its
    ;; staging area; finishing it first keeps them in the rebuild.
    (keyfreq--compact-finish)
    (let ((table (make-hash-table :test 'equal))
          (files (keyfreq--archive-files)))
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
      (message "keyfreq: rebuilt %s from %d archives"
               (file-name-nondirectory keyfreq-file) (length files)))))

(defun keyfreq--archive-snapshots (file)
  "Return report snapshots for FILE: now first, then one per year, newest first.

Every snapshot holds the counts of its own period -- what that year
added -- so the periods are disjoint and add up to All time.  Months are
never offered on their own: a month is part of the year it falls in."
  (let ((years nil))
    (when (and keyfreq-html-history
               keyfreq-daily-archive
               (file-directory-p (keyfreq--daily-dir)))
      (let* ((baseline (and (file-exists-p (keyfreq--daily-baseline))
                            (keyfreq--read-file-entries
                             (keyfreq--daily-baseline))))
             (groups (keyfreq--period-files (keyfreq--archive-files)
                                            #'keyfreq--file-year))
             (key-groups (keyfreq--period-files (keyfreq--archive-key-files)
                                                #'keyfreq--file-year)))
        ;; Oldest first in, newest first out, so the menu walks back from
        ;; this year into the older ones.  A month is never offered on its
        ;; own: it is part of the year it falls in.
        (dolist (group groups)
          (let ((period (car group)))
            (push (keyfreq--snapshot
                   period
                   ;; the baseline predates every archive, so it belongs
                   ;; to the earliest year there is
                   (keyfreq--period-table (cdr group)
                                          (and (eq group (car groups))
                                               baseline))
                   (keyfreq--period-table (cdr (assoc period key-groups))))
                  years)))))
    (if (file-exists-p file)
        (cons (keyfreq--snapshot "now"
                                 (keyfreq--read-file-entries file)
                                 (keyfreq--key-table-entries))
              years)
      years)))

(defun keyfreq--report-snapshots (file)
  "Return report snapshots in menu order: all time, the ranges, then the years.

The menu walks forward from the widest window to the narrowest and then
back into history: `All time`, `Today`, `Last 7 days`, `Last 30 days`,
this year, and the older ones newest first.

Every snapshot carries both halves of its period: the command counts and
the keys that were actually pressed during it."
  (let ((ranges nil))
    (when (and keyfreq-daily-archive (file-directory-p (keyfreq--daily-dir)))
      (dolist (spec '(("today" . 1) ("7d" . 7) ("30d" . 30)))
        (let ((table (keyfreq--range-table (cdr spec))))
          (when (> (hash-table-count table) 0)
            (push (keyfreq--snapshot (car spec) table
                                     (keyfreq--range-key-table (cdr spec)))
                  ranges)))))
    ;; `keyfreq--archive-snapshots' already leads with All time
    (let* ((rest (keyfreq--archive-snapshots file))
           (all (and rest (equal (car (car rest)) "now") (car rest))))
      (append (and all (list all))
              (nreverse ranges)
              (if all (cdr rest) rest)))))

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

(defun keyfreq--html-merge-recorded (recorded)
  "Merge RECORDED, keyed by (MODE COMMAND), into COMMAND -> alist."
  (let ((all (make-hash-table :test 'equal)))
    (maphash
     (lambda (pair alist)
       (let* ((command (nth 1 pair))
              (cell (gethash command all)))
         (dolist (entry alist)
           (let ((hit (assoc (car entry) cell)))
             (if hit
                 (setcdr hit (+ (cdr hit) (cdr entry)))
               (push (cons (car entry) (cdr entry)) cell))))
         (puthash command cell all)))
     recorded)
    all))

(defun keyfreq--html-keys-text (alist)
  "Return ALIST's key descriptions as text, most used first."
  (when alist
    (keyfreq--html-escape
     (mapconcat (lambda (pair) (car pair))
                (sort (copy-sequence alist)
                      (lambda (a b) (if (= (cdr a) (cdr b))
                                        (string< (car a) (car b))
                                      (> (cdr a) (cdr b)))))
                ", "))))

(defun keyfreq--html-keys-attr (alist)
  "Return a `data-keys' attribute describing ALIST, or nil."
  (when alist
    (format " data-keys=\"%s\""
            (keyfreq--html-escape
             (concat "["
                     (mapconcat
                      (lambda (pair)
                        (format "[%s,%d]"
                                (json-encode-string (car pair))
                                (cdr pair)))
                      alist ",")
                     "]")))))

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
      ;; The key was unbound; that is a property of the keystroke, so it
      ;; belongs in the Shortcut column, not in place of the command name.
      "(unbound key)"
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

(defun keyfreq--html-shortcut-index (table modes recorded)
  "Resolve every mode/command pair in TABLE to its keystrokes.

MODES is the value of `keyfreq--html-modes'.  RECORDED maps
(MODE COMMAND) to the keys actually pressed, which wins over resolving
the command in the keymap.

Return (PER-MODE . UNION)."
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
          (let ((text (or (keyfreq--html-keys-text
                           (gethash (list mode command) recorded))
                          (if map
                              (keyfreq--where-is-string command map)
                            (or (gethash command global-cache)
                                (puthash command
                                         (keyfreq--where-is-string command nil)
                                         global-cache))))))
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

(defun keyfreq--html-insert-table (list shortcut key-attr)
  "Insert an HTML table for LIST, a value returned by `keyfreq-list'.
SHORTCUT is a function that maps a command to its already escaped
keystroke description.  KEYS maps a command to a `data-keys' attribute
carrying the exact per-key counts, or nil when they were not recorded.
(The argument is not called KEYS, to avoid confusion with the recorded
keys.)"
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
                     ;; Emacs records the symbol `undefined' when an
                     ;; unbound key is pressed; the Command column keeps
                     ;; that symbol and the Shortcut column says why.
                     (keyfreq--html-escape command))
             (format "<td data-count=\"%d\"%s>%s</td></tr>\n"
                     count (or (funcall key-attr command) "")
                     (funcall shortcut command)))))
  (insert "</tbody>\n</table>\n"))

(defun keyfreq--html-insert-card (modes periods)
  "Insert the interactive heat map card.

MODES is the value of `keyfreq--html-modes'; PERIODS is the list of
history periods, or nil when there are no daily archives to build them
from.  The card holds a single canvas plus the controls that choose what
it shows."
  (insert "<section class=\"card\" id=\"heatmap-card\">\n")
  (insert "<h2 class=\"card-title\">Keyboard heat map</h2>\n")
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
  (insert "<span class=\"modes-total\" id=\"modes-meta\"></span>\n")
  (insert "</div>\n")
  ;; The status line owns its own row and a fixed height: focusing a key
  ;; makes the text longer, and a shared row would reflow the controls.
  (insert "<div class=\"status\">\n")
  (insert "<span class=\"scope\" id=\"scope-summary\"></span>\n")
  (insert "</div>\n")
  (insert "<div class=\"heatmap-wrap\">\n")
  (insert "<canvas id=\"heatmap\" width=\"900\" height=\"340\"></canvas>\n")
  (insert "<div class=\"key-tip\" id=\"key-tip\" hidden></div>\n")
  (insert "<p class=\"empty\" id=\"empty-note\" hidden>"
          "no keyboard shortcuts in this selection</p>\n")
  (insert "</div>\n")
  (insert "<p class=\"hint\">Hover a key for its press count, click it to "
          "keep only that key and the commands that use it.  Each command is "
          "counted once, on its first real binding, resolved in that mode's "
          "own keymap.</p>\n")
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
           (recorded (keyfreq--recorded-keys))
           (all-recorded (keyfreq--html-merge-recorded recorded))
           (index (keyfreq--html-shortcut-index table modes recorded))
           (per-mode (car index))
           (all-keys (cdr index))
           (snapshots (keyfreq--report-snapshots keyfreq-file))
           (payload (keyfreq--history-payload snapshots))
           (file (or filename
                     (make-temp-file
                      (expand-file-name "keyfreq-" temporary-file-directory)
                      nil ".html")))
           (cell (lambda (list shortcut key-attr)
                   (with-temp-buffer
                     (keyfreq--html-insert-table list shortcut key-attr)
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
          (insert "<main class=\"content\">\n")
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
                           (lambda (command) (or (gethash command all-keys) ""))
                           (lambda (command)
                             (keyfreq--html-keys-attr
                              (gethash command all-recorded)))))
          (insert "</section>\n")
          (dolist (entry modes)
            (let* ((mode (car entry))
                   (keys (gethash mode per-mode)))
              (insert (format "<section data-mode=\"%s\">\n"
                              (keyfreq--html-escape (symbol-name mode))))
              (insert (format "<h2>%s</h2>\n" (keyfreq--html-escape mode)))
              (insert (funcall cell
                               (keyfreq-list (keyfreq-filter-major-mode table mode))
                               (lambda (command)
                                 (or (gethash command keys) ""))
                               (lambda (command)
                                 (keyfreq--html-keys-attr
                                  (gethash (list mode command) recorded)))))
              (insert "</section>\n")))
          (insert "</main>\n")
          (when (> (length (car payload)) 1)
            ;; escape < > & so the payload can never close the script tag
            (insert "<script type=\"application/json\" id=\"keyfreq-data\">")
            (insert (keyfreq--json-history (car payload) (nth 1 payload)
                                           (nth 2 payload) (nth 3 payload)
                                           (nth 4 payload)))
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
  (let ((commands-indexes (make-hash-table :test 'equal :size 128))
	commands-list frequencies-matrix i)

    ;; Build the "commands" property of the JSON object.
    (setq i 0)
    (maphash
     (lambda (command-symbol _counter)
       (setq commands-list (append commands-list (list command-symbol)))
       (puthash command-symbol i commands-indexes)
       (setq i (+ i 1)))
     (keyfreq-groups-major-modes table))

    ;; Build the "frequencies" property.
    (mapc
     (lambda (major-mode-symbol)
       (let ((cmd-count-pairs '()))
	 (keyfreq-format-list (keyfreq-list (keyfreq-filter-major-mode table major-mode-symbol))
			      (lambda (count _perc command)
				(let ((index (gethash command commands-indexes)))
				  (unless (member index cmd-count-pairs)
				    (setq cmd-count-pairs
					  (append cmd-count-pairs (list index))))
				  (unless (member count cmd-count-pairs)
				    (setq cmd-count-pairs
					  (append cmd-count-pairs (list count)))))))
	 (setq frequencies-matrix (append frequencies-matrix (list major-mode-symbol)))
	 (setq frequencies-matrix
	       (append frequencies-matrix (list (append cmd-count-pairs nil))))))
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
  "Reset all statistics, including the files on disk.

Deletes `keyfreq-file', the recorded keys, and the daily archives with
their baseline, and clears both in-memory tables.  The .corrupt-*
backups, if any, are left alone."
  (interactive)
  (when (yes-or-no-p
         (concat
          "Delete all keyfreq statistics?  This removes the data file, "
          "the recorded keys and the daily archives. "))
    (if (not (keyfreq-file-is-unlocked))
        (message "keyfreq: %s is locked by another Emacs; nothing was deleted"
                 keyfreq-file)
      (keyfreq-file-claim-lock)
      (if (not (eq (keyfreq-file-owner) (emacs-pid)))
          (message "keyfreq: could not lock %s; nothing was deleted"
                   keyfreq-file)
        (unwind-protect
            (progn
              (clrhash keyfreq-table)
              (clrhash keyfreq-key-table)
              (when (file-exists-p keyfreq-file)
                (delete-file keyfreq-file))
              (let ((keys (keyfreq--key-file)))
                (when (file-exists-p keys)
                  (delete-file keys)))
              (let ((dir (keyfreq--daily-dir)))
                (when (file-directory-p dir)
                  (delete-directory dir t)))
              (setq keyfreq--rollup-dirty nil))
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
  (when (eq (keyfreq-file-owner) (emacs-pid))
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

(defun keyfreq--with-file-lock (function)
  "Call FUNCTION while holding `keyfreq-file-lock'."
  (unless (keyfreq-file-is-unlocked)
    (user-error "Keyfreq file is locked by another Emacs"))
  (keyfreq-file-claim-lock)
  (unless (eq (keyfreq-file-owner) (emacs-pid))
    (user-error "Could not lock %s" keyfreq-file))
  (unwind-protect
      (funcall function)
    (keyfreq-file-release-lock)))


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
whole file is regenerated from scratch."
  :group 'keyfreq
  :type 'boolean)

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
        (keyfreq--rebuild-rollup-locked)
      (error (message "keyfreq: rollup rebuild failed: %s"
                      (error-message-string err)))))
  ;; Compacting is daily work at most, and it never touches today's
  ;; archive, so it cannot race with what this save is writing.  It is
  ;; tried once a day even when it fails, or a broken archive directory
  ;; would be retried on every save.
  (when (and keyfreq-daily-archive
             (or keyfreq-daily-retention keyfreq-monthly-retention)
             (not (equal keyfreq--compact-attempt (keyfreq--daily-date))))
    (setq keyfreq--compact-attempt (keyfreq--daily-date))
    (condition-case err
        (keyfreq--compact-locked keyfreq-daily-retention
                                 keyfreq-monthly-retention)
      (error (message "keyfreq: compaction failed: %s"
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
          (condition-case err
              (keyfreq--save-keys)
            (error (message "keyfreq: cannot write %s: %s"
                            (keyfreq--key-file) (error-message-string err))))
          (let ((ok (keyfreq--write-rollup pending)))
            ;; Daily archives are authoritative; without them, retain
            ;; deltas until the rollup write succeeds.
            (when (or keyfreq-daily-archive ok)
              (clrhash table))
            (unless ok
              (when keyfreq-daily-archive
                (setq keyfreq--rollup-dirty (expand-file-name keyfreq-file))))
            ok)))))))

(defcustom keyfreq-lock-retries 50
  "How many 0.1 second waits a mandatory save does on a locked file.

A mandatory save (when Emacs quits, or `keyfreq-save-now') waits for
the other Emacs to release the lock; after this many waits it gives
up and leaves the new counts in memory, to be saved by the next
autosave.  Bounding the wait keeps Emacs from hanging on quit when
another instance never lets go."
  :group 'keyfreq
  :type 'integer)

(defun keyfreq-table-save (table &optional mustsave)
  "Append all values from the specified TABLE into the
`keyfreq-file' as a sexp of an alist.  Then resets the TABLE
if it was successfully merged.

The file is updated in place: an entry that already exists keeps
its line and only its counter is rewritten, while unknown
entries are appended right before the closing parenthesis.  Bind
`keyfreq-incremental-save' to nil to regenerate the whole file
instead.

If MUSTSAVE is t, this function waits for the lock for up to
`keyfreq-lock-retries' tenths of a second and saves once it gets
it.  If the lock does not free up in time, TABLE is left untouched
and the next save retries.  If MUSTSAVE is nil, it does nothing if
the table cannot be saved."

  ;; Avoid adding nothing to the file
  (unless (zerop (hash-table-count table))
    (let ((done nil)
          (attempts 0))
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
          ;; We must save right now, so keep trying to get the lock --
          ;; but never for ever: quitting Emacs must not hang here.
          (setq attempts (1+ attempts))
          (if (< attempts keyfreq-lock-retries)
              (sleep-for 0.1)
            (message "keyfreq: %s stayed locked; the new counts stay in memory"
                     keyfreq-file)
            (setq done t)))))))

(defun keyfreq-sort-file (&optional filename)
  "Rewrite FILENAME (default `keyfreq-file') with entries sorted by key.

This is a one-off normalisation.  Sorting the file makes later
in-place updates produce minimal, line-aligned diffs."
  (interactive)
  (keyfreq--with-file-lock
   (lambda ()
     (keyfreq--sort-file-locked filename))))

(defun keyfreq--sort-file-locked (&optional filename)
  "Sort FILENAME while holding `keyfreq-file-lock'."
  (let* ((file (expand-file-name (or filename keyfreq-file)))
         (entries nil))
    (unless (file-exists-p file)
      (user-error "No such file: %s" file))
    (with-temp-buffer
      (let ((coding-system-for-read (or keyfreq-coding-system 'undecided)))
        (insert-file-contents file))
      (goto-char (point-min))
      (let ((form (read (current-buffer))))
        (unless (listp form)
          (user-error "Invalid keyfreq list in %s" file))
        (condition-case nil
            (progn
              (read (current-buffer))
              (user-error "Unexpected trailing data in %s" file))
          (end-of-file nil))
        (setq entries form)))
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
      (keyfreq--write-file content file
                           (keyfreq--writing-coding-system
                            (keyfreq--file-coding-system file)))
      (message "keyfreq: sorted %d entries in %s"
               (length entries) file))))


(defun keyfreq--backup-file (&optional file)
  "Copy FILE (default `keyfreq-file') aside and return the backup name."
  (let* ((source (or file keyfreq-file))
         (base (concat source ".corrupt-"
                       (format-time-string "%Y%m%d-%H%M%S")))
         (name base)
         (i 1))
    (while (file-exists-p name)
      (setq name (format "%s-%d" base (setq i (1+ i)))))
    (copy-file source name t)
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


(defcustom keyfreq-autosave-timeout 600
  "How often in seconds `keyfreq-table' should be saved
when `keyfreq-autosave-mode' is enabled.  Setting this
value will take effect only after (re)enabling
`keyfreq-autosave-mode'."
  :group 'keyfreq
  :type 'number)

(defvar keyfreq-autosave--timer nil)

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
