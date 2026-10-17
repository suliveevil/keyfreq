;;; keyfreq-tests.el --- tests for in-place keyfreq saves  -*- lexical-binding: t -*-
;;
;; Self-contained test suite for the incremental (in-place) persistence
;; change in keyfreq.el.
;;
;;   emacs --batch -l test/keyfreq-tests.el
;;
;; It creates its own fixture log in a temporary directory, so it never
;; touches your real `keyfreq-file'.

(require 'cl-lib)

(defvar kf-pass 0)
(defvar kf-fail 0)
(defvar kf-failures nil)
(defvar kf-here (file-name-directory (or load-file-name buffer-file-name)))
(defvar kf-el (expand-file-name "../keyfreq.el"
                              (file-name-directory
                               (expand-file-name (or load-file-name buffer-file-name)))))
(defvar kf-tmp (make-temp-file "keyfreq-tests-" t))

(defun kf-ok (label form)
  (if form
      (progn (cl-incf kf-pass) (princ (format "  PASS %s\n" label)))
    (cl-incf kf-fail)
    (push label kf-failures)
    (princ (format "  FAIL %s\n" label))))

(defmacro kf-test (name &rest body)
  `(progn
     (princ (format "\n== %s ==\n" ,name))
     (condition-case err
         (progn ,@body)
       (error (cl-incf kf-fail)
              (push ,name kf-failures)
              (princ (format "  ERROR %s: %s\n" ,name (error-message-string err)))))))

(defun kf-make-table (entries)
  "Build a keyfreq table from ENTRIES, a list of (MODE CMD COUNT)."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (e entries h)
      (puthash (cons (nth 0 e) (nth 1 e)) (nth 2 e) h))))

(defun kf-fixture (&optional entry-count)
  "Write a synthetic keyfreq log and return its path."
  (let* ((path (make-temp-file (expand-file-name "log-" kf-tmp)))
         (n (or entry-count 300))
         (text
          (with-temp-buffer
            (insert "(")
            (dotimes (i n)
              (prin1 (cons (cons (if (zerop (mod i 3)) 'org-mode 'fundamental-mode)
                                 (intern (format "cmd-%d" i)))
                           (1+ i))
                     (current-buffer))
              (insert "\n"))
            (insert ")")
            (buffer-string))))
    (with-temp-file path (insert text))
    path))

(defun kf-read-entries (file)
  "Independent parser: return the raw entry list of FILE."
  (when (file-exists-p file)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8-unix))
        (insert-file-contents file))
      (condition-case nil
          (let ((form (read (current-buffer))))
            (cl-remove-if-not
             (lambda (e) (and (consp e) (consp (car e)) (integerp (cdr e))))
             form))
        (error nil)))))

(defun kf-totals (file)
  (let ((h (make-hash-table :test 'equal)))
    (dolist (e (kf-read-entries file))
      (puthash (car e) (+ (gethash (car e) h 0) (cdr e)) h))
    h))

(defun kf-get (file key) (gethash key (kf-totals file)))

(defun kf-lines (file)
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix)) (insert-file-contents file))
    (split-string (buffer-string) "\n")))

(defun kf-git-diff-size (a b)
  "Real git diff size between A and B, as (insertions . deletions)."
  (with-temp-buffer
    (call-process "git" nil t nil "diff" "--no-index" "--numstat" "--" a b)
    (goto-char (point-min))
    (let ((line (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position))))
      (if (string-match "^\\([0-9]+\\)\t\\([0-9]+\\)" line)
          (cons (string-to-number (match-string 1 line))
                (string-to-number (match-string 2 line)))
        (cons 0 0)))))

(defun kf-save (file table &optional mustsave)
  (let ((keyfreq-file file)
        (keyfreq-file-lock (concat file ".lock")))
    (keyfreq-table-save table mustsave)))

(load kf-el nil t)
(unless (fboundp 'keyfreq--merge-in-place)
  (error "keyfreq.el did not load from %s" kf-el))

(kf-test "existing counters are rewritten in place"
         (let* ((file (kf-fixture))
                (orig (kf-fixture))
                (before (kf-totals file))
                (nlines (length (kf-lines file))))
           (copy-file file orig t)
           (kf-save file (kf-make-table '((org-mode cmd-0 5)
                                          (org-mode cmd-3 12)
                                          (fundamental-mode cmd-1 1))) t)
           (kf-ok "org-mode cmd-0 +5"
                  (= (+ 5 (gethash '(org-mode . cmd-0) before))
                     (kf-get file '(org-mode . cmd-0))))
           (kf-ok "org-mode cmd-3 +12"
                  (= (+ 12 (gethash '(org-mode . cmd-3) before))
                     (kf-get file '(org-mode . cmd-3))))
           (kf-ok "fundamental-mode cmd-1 +1"
                  (= (+ 1 (gethash '(fundamental-mode . cmd-1) before))
                     (kf-get file '(fundamental-mode . cmd-1))))
           (kf-ok "git diff is 3 insertions + 3 deletions"
                  (equal (cons 3 3) (kf-git-diff-size orig file)))
           (kf-ok "line count unchanged" (= nlines (length (kf-lines file))))
           (kf-ok "order preserved"
                  (equal (mapcar #'car (kf-read-entries orig))
                         (mapcar #'car (kf-read-entries file))))
           (delete-file file) (delete-file orig)))

(kf-test "unknown keys are appended, nothing else moves"
         (let* ((file (kf-fixture))
                (orig (kf-fixture)))
           (copy-file file orig t)
           (kf-save file (kf-make-table '((org-mode brand-new-a 3)
                                          (prog-mode brand-new-b 1))) t)
           (kf-ok "brand-new-a = 3" (= 3 (kf-get file '(org-mode . brand-new-a))))
           (kf-ok "brand-new-b = 1" (= 1 (kf-get file '(prog-mode . brand-new-b))))
           (kf-ok "git diff is a pure addition of 2 lines"
                  (equal (cons 2 0) (kf-git-diff-size orig file)))
           (let ((new (kf-lines file)) (old (kf-lines orig)))
             (kf-ok "every original entry line survives verbatim"
                    (cl-every (lambda (l) (or (not (string-prefix-p "((" l))
                                              (member l new)))
                              old))
             (kf-ok "the closing paren is still alone on the last line"
                    (string= ")" (car (last (kf-lines file)))))
             (kf-ok "no duplicate keys"
                    (= (length (kf-read-entries file))
                       (hash-table-count (kf-totals file)))))
           (delete-file file) (delete-file orig)))

(kf-test "no drift over many incremental saves"
         (let* ((file (kf-fixture))
                (expected (kf-totals file))
                (keys (let (ks) (maphash (lambda (k _v) (push k ks)) expected) ks)))
           (dotimes (i 30)
             (let* ((key (nth (mod (* i 37) (length keys)) keys))
                    (delta (1+ i)))
               (puthash key (+ (gethash key expected 0) delta) expected)
               (kf-save file (kf-make-table (list (list (car key) (cdr key) delta))) t)))
           (let ((actual (kf-totals file)) (bad nil))
             (maphash (lambda (k v)
                        (unless (equal v (gethash k actual :missing))
                          (setq bad (cons k bad))))
                      expected)
             (kf-ok "no drift after 30 saves" (null bad))
             (kf-ok "no extra keys" (= (hash-table-count expected)
                                       (hash-table-count actual))))
           (delete-file file)))

(kf-test "unicode symbols survive byte for byte"
         (let* ((file (make-temp-file (expand-file-name "uni-" kf-tmp)))
                (orig (make-temp-file (expand-file-name "uni0-" kf-tmp)))
                (weird (intern "hippie-expand\u200b")))
           (with-temp-file file
             (insert "(")
             (prin1 (cons (cons 'fundamental-mode weird) 7) (current-buffer))
             (insert "\n")
             (prin1 (cons (cons 'org-mode 'org-return) 11) (current-buffer))
             (insert "\n)"))
           (copy-file file orig t)
           (kf-save file (kf-make-table (list (list 'fundamental-mode weird 1))) t)
           (kf-ok "counter updated" (= 8 (kf-get file (cons 'fundamental-mode weird))))
           (kf-ok "git diff is 1 insertion + 1 deletion"
                  (equal (cons 1 1) (kf-git-diff-size orig file)))
           (kf-ok "zero-width space preserved in the raw bytes"
                  (with-temp-buffer
                    (let ((coding-system-for-read 'utf-8-unix)) (insert-file-contents file))
                    (string-match-p "\u200b" (buffer-string))))
           (delete-file file) (delete-file orig)))

(kf-test "a failed write keeps the deltas and does not duplicate them"
         (let* ((file (kf-fixture))
                (orig (kf-fixture))
                (table (kf-make-table '((org-mode cmd-0 5)))))
           (copy-file file orig t)
           (cl-letf (((symbol-function 'keyfreq--write-file)
                      (lambda (&rest _) (error "simulated disk full"))))
             (kf-save file table t))
           (kf-ok "file untouched" (equal 0 (car (kf-git-diff-size orig file))))
           (kf-ok "delta kept in memory" (= 5 (gethash '(org-mode . cmd-0) table)))
           (kf-save file table t)
           (kf-ok "retry applies the delta exactly once"
                  (= (+ 5 (kf-get orig '(org-mode . cmd-0)))
                     (kf-get file '(org-mode . cmd-0))))
           (delete-file file) (delete-file orig)))

(kf-test "a live lock blocks a non-mandatory save"
         (let ((file (kf-fixture))
               (table (kf-make-table '((org-mode cmd-0 5)))))
           (let ((keyfreq-file file)
                 (keyfreq-file-lock (concat file ".lock")))
             (write-region "1" nil keyfreq-file-lock nil 'nomessage)
             (keyfreq-table-save table nil)
             (kf-ok "table not cleared" (= 5 (gethash '(org-mode . cmd-0) table)))
             (kf-ok "file not changed" (= 1 (kf-get file '(org-mode . cmd-0))))
             (ignore-errors (delete-file keyfreq-file-lock)))
           (delete-file file)))

(kf-test "an empty or unparsable file is regenerated"
         (let ((file (make-temp-file (expand-file-name "empty-" kf-tmp))))
           (kf-save file (kf-make-table '((org-mode cmd-0 4))) t)
           (kf-ok "empty file becomes a valid log"
                  (= 4 (kf-get file '(org-mode . cmd-0))))
           (with-temp-file file (insert "garbage\n"))
           (kf-save file (kf-make-table '((org-mode cmd-0 2))) t)
           (kf-ok "garbage file is replaced by a valid log"
                  (= 2 (kf-get file '(org-mode . cmd-0))))
           (delete-file file)))

(kf-test "full rewrite (incremental disabled) is a fixed point too"
         (let* ((file (kf-fixture))
                (orig (kf-fixture))
                (prev (make-temp-file (expand-file-name "prev-" kf-tmp)))
                (keyfreq-incremental-save nil))
           (copy-file file orig t)
           (kf-save file (kf-make-table '((org-mode cmd-0 5))) t)
           (kf-ok "counter updated"
                  (= 6 (kf-get file '(org-mode . cmd-0))))
           (kf-ok "no longer a full reversal of the file"
                  (< (let ((d (kf-git-diff-size orig file))) (+ (car d) (cdr d))) 20))
           (copy-file file prev t)
           (kf-save file (kf-make-table '((org-mode cmd-3 7))) t)
           (kf-ok "the next full rewrite is a small diff as well"
                  (< (let ((d (kf-git-diff-size prev file))) (+ (car d) (cdr d))) 20))
           (delete-file file) (delete-file orig) (delete-file prev)))

(kf-test "keyfreq-sort-file keeps every entry"
         (let ((file (kf-fixture)))
           (let ((keyfreq-file file)) (keyfreq-sort-file))
           (kf-ok "entry count preserved"
                  (= 300 (length (kf-read-entries file))))
           (kf-ok "file is sorted by key"
                  (let ((s (mapcar (lambda (e) (prin1-to-string (car e)))
                                   (kf-read-entries file))))
                    (equal s (sort (copy-sequence s) #'string<))))
           (delete-file file)))

(kf-test "excluded commands are not written"
         (let* ((file (kf-fixture))
                (keyfreq-excluded-commands '(cmd-0)))
           (kf-save file (kf-make-table '((org-mode cmd-0 9))) t)
           (kf-ok "excluded command untouched" (= 1 (kf-get file '(org-mode . cmd-0))))
           (delete-file file)))

(kf-test "a truncated file is salvaged, not wiped"
         (let* ((file (make-temp-file (expand-file-name "trunc-" kf-tmp)))
                (size nil))
           (with-temp-file file
             (insert "(")
             (dotimes (i 500)
               (prin1 (cons (cons 'org-mode (intern (format "c%d" i))) (1+ i))
                      (current-buffer))
               (insert "\n"))
             (insert "(("))                 ; truncated mid-entry, no closing paren
           (setq size (file-attribute-size (file-attributes file)))
           (kf-save file (kf-make-table '((org-mode c0 5))) t)
           (kf-ok "the list is readable again" (consp (kf-read-entries file)))
           (kf-ok "the 500 salvaged entries survive"
                  (= 500 (length (kf-read-entries file))))
           (kf-ok "the delta still applied" (= 6 (kf-get file '(org-mode . c0))))
           (kf-ok "the file did not shrink to a stub"
                  (> (file-attribute-size (file-attributes file)) (* size 0.8)))
           (kf-ok "a .corrupt backup was kept"
                  (consp (directory-files
                          (file-name-directory file) t
                          (concat (regexp-quote (file-name-nondirectory file))
                                  "\\.corrupt"))))
           (dolist (b (directory-files (file-name-directory file) t
                                       (concat (regexp-quote (file-name-nondirectory file))
                                               "\\.corrupt")))
             (delete-file b))
           (delete-file file)))

(kf-test "a file without a closing paren is repaired, nothing is written outside the list"
         (let ((file (make-temp-file (expand-file-name "noclose-" kf-tmp))))
           (with-temp-file file
             (insert "(\n((org-mode . org-return) . 10)\n;; trailing comment\n"))
           (kf-save file (kf-make-table '((org-mode brand-new 3)
                                          (org-mode org-return 1))) t)
           (kf-ok "file is a well-formed list" (consp (kf-read-entries file)))
           (kf-ok "the new command was recorded" (= 3 (kf-get file '(org-mode . brand-new))))
           (kf-ok "the existing counter was incremented" (= 11 (kf-get file '(org-mode . org-return))))
           (dolist (b (directory-files (file-name-directory file) t
                                       (concat (regexp-quote (file-name-nondirectory file))
                                               "\\.corrupt")))
             (delete-file b))
           (delete-file file)))

(kf-test "file modes: new files get 0644, existing modes are preserved"
         (let ((new (expand-file-name (format "mode-new-%d.log" (random 100000)) kf-tmp))
               (old (expand-file-name (format "mode-old-%d.log" (random 100000)) kf-tmp)))
           (ignore-errors (delete-file new))
           (kf-save new (kf-make-table '((org-mode cmd-0 1))) t)
           (kf-ok "new file is 0644"
                  (= #o644 (logand #o777 (file-modes new))))
           (with-temp-file old (insert "(\n((org-mode . org-return) . 1)\n)"))
           (set-file-modes old #o600)
           (kf-save old (kf-make-table '((org-mode org-return 1))) t)
           (kf-ok "existing 0600 is preserved"
                  (= #o600 (logand #o777 (file-modes old))))
           (delete-file new) (delete-file old)))

(princ (format "\n----------------------------------------\n%d passed, %d failed\n"
               kf-pass kf-fail))
(delete-directory kf-tmp t)
(if (null kf-failures)
    (princ "ALL TESTS PASSED\n")
  (progn
    (princ (format "FAILURES: %S\n" (nreverse kf-failures)))
    (kill-emacs 1)))
