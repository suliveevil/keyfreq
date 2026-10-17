;;; keyfreq-html-tests.el --- tests for the HTML report  -*- lexical-binding: t -*-
;;
;;   emacs --batch -l test/keyfreq-html-tests.el

(require 'cl-lib)

(defvar kfh-pass 0)
(defvar kfh-fail 0)
(defvar kfh-failures nil)
(defvar kfh-here (file-name-directory
                  (expand-file-name (or load-file-name buffer-file-name))))
(defvar kfh-el (expand-file-name "../keyfreq.el" kfh-here))
(defvar kfh-tmp (make-temp-file "keyfreq-html-tests-" t))

(defun kfh-ok (label form)
  (if form
      (progn (cl-incf kfh-pass) (princ (format "  PASS %s\n" label)))
    (cl-incf kfh-fail)
    (push label kfh-failures)
    (princ (format "  FAIL %s\n" label))))

(defmacro kfh-test (name &rest body)
  `(progn
     (princ (format "\n== %s ==\n" ,name))
     (condition-case err
         (progn ,@body)
       (error (cl-incf kfh-fail)
              (push ,name kfh-failures)
              (princ (format "  ERROR %s: %s\n" ,name (error-message-string err)))))))

(defun kfh-slurp (file)
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix)) (insert-file-contents file))
    (buffer-string)))

(defun kfh-fixture (entries)
  "Write ENTRIES (a list of ((mode . cmd) . count)) as `keyfreq-file'."
  (let ((file (make-temp-file (expand-file-name "log-" kfh-tmp))))
    (with-temp-file file
      (insert "(")
      (dolist (e entries) (prin1 e (current-buffer)) (insert "\n"))
      (insert ")"))
    file))

(defun kfh-ids (html)
  (let ((ids nil) (p 0))
    (while (string-match " id=\"\\([^\"]*\\)\"" html p)
      (push (match-string 1 html) ids) (setq p (match-end 0)))
    ids))

(defun kfh-hrefs (html)
  (let ((hrefs nil) (p 0))
    (while (string-match " href=\"#\\([^\"]*\\)\"" html p)
      (push (match-string 1 html) hrefs) (setq p (match-end 0)))
    hrefs))

(load kfh-el nil t)
(unless (fboundp 'keyfreq--html-escape)
  (error "keyfreq.el did not load from %s" kfh-el))

(setq keyfreq-folder (directory-file-name kfh-here))
(setq keyfreq-folder (file-name-directory (directory-file-name kfh-here)))
(setq keyfreq-folder (expand-file-name ".." kfh-here))

(kfh-test "escaping helpers"
         (kfh-ok "&<>\" are escaped"
                 (equal "a&amp;b&lt;c&gt;d&quot;e"
                        (keyfreq--html-escape "a&b<c>d\"e")))
         (kfh-ok "plain text is untouched"
                 (equal "org-return" (keyfreq--html-escape 'org-return)))
         (kfh-ok "thousands separators"
                 (equal "57,708" (keyfreq--html-number 57708)))
         (kfh-ok "small numbers have no separator"
                 (equal "999" (keyfreq--html-number 999)))
         (kfh-ok "id sanitising"
                 (equal "benchmark-init-tree-mode"
                        (let ((used (make-hash-table :test 'equal)))
                          (keyfreq--html-id "benchmark-init/tree-mode" used))))
         (kfh-ok "ids do not collide"
                 (let ((used (make-hash-table :test 'equal)))
                   (not (equal (keyfreq--html-id "a/b-mode" used)
                               (keyfreq--html-id "a-b-mode" used))))))

(kfh-test "shortcuts are resolved in the mode's own keymap"
         (require 'dired)
         (kfh-ok "a mode map is found by the <mode>-map convention"
                 (keymapp (keyfreq--mode-keymap 'dired-mode)))
         (kfh-ok "a mode without a map falls back to global-map"
                 (equal (list global-map)
                        (keyfreq--mode-keymaps 'no-such-mode)))
         (kfh-ok "dired-toggle-marks is invisible globally"
                 (equal "" (keyfreq--where-is-string 'dired-toggle-marks nil)))
         (kfh-ok "but visible in dired-mode"
                 (string-match-p
                  "\\`t"
                  (keyfreq--where-is-string
                   'dired-toggle-marks (keyfreq--mode-keymap 'dired-mode))))
         (kfh-ok "org-return is RET in org-mode"
                 (progn (require 'org)
                        (string-match-p
                         "\\`RET"
                         (keyfreq--where-is-string
                          'org-return (keyfreq--mode-keymap 'org-mode))))))

(kfh-test "pseudo bindings and unprintable keys never reach the report"
         (kfh-ok "menu-bar paths are stripped"
                 (not (string-match-p "menu-bar" (keyfreq--where-is-string 'save-buffer nil))))
         (kfh-ok "an unbound key is reported in the Shortcut column"
                 (equal "(unbound key)" (keyfreq--where-is-string 'undefined nil)))
         (let* ((log (kfh-fixture '(((dired-mode . dired-toggle-marks) . 9))))
                (keyfreq-file log)
               (out (expand-file-name "pseudo.html" kfh-tmp)))
           (require 'dired)
           (keyfreq-html-v2 out nil)
           (let ((html (kfh-slurp out)))
             (kfh-ok "the report is plain UTF-8 text"
                     (equal html (decode-coding-string (encode-coding-string html 'utf-8) 'utf-8)))
             (kfh-ok "no menu-bar noise in shortcut cells"
                     (not (string-match-p "data-count=\"9\">[^<]*menu-bar" html)))
             (kfh-ok "the mode-local binding made it in"
                     (string-match-p "data-count=\"9\">t" html)))
           (delete-file log) (delete-file out)))

(kfh-test "report is a well formed, self-contained document"
         (let* ((log (kfh-fixture '(((fundamental-mode . next-line) . 57708)
                                    ((fundamental-mode . save-buffer) . 3200)
                                    ((org-mode . org-return) . 12))))
                (keyfreq-file log)
                (out (expand-file-name "report.html" kfh-tmp))
                (html nil))
           (keyfreq-html-v2 out nil)
           (setq html (kfh-slurp out))
           (kfh-ok "starts with a real doctype"
                   (string-prefix-p "<!DOCTYPE html>\n<html lang=\"en\">\n<head>"
                                    html))
           (kfh-ok "declares the encoding"
                   (string-match-p "<meta charset=\"utf-8\">" html))
           (kfh-ok "has a title" (string-match-p "<title>Keyfreq Report" html))
           (kfh-ok "head comes before body"
                   (< (string-match-p "<head>" html) (string-match-p "<body>" html)))
           (kfh-ok "inlines the stylesheet" (string-match-p "<style>" html))
           (kfh-ok "inlines the script" (string-match-p "<script>" html))
           (kfh-ok "an empty canvas is hidden, not left as a gap"
                   (string-match-p "canvas\\[hidden\\]" html))
           (kfh-ok "no external css/js reference"
                   (not (string-match-p "\\(src\\|href\\)=\"[^\"]*\\.\\(js\\|css\\)\"" html)))
           (kfh-ok "no <xmp> element" (not (string-match-p "<xmp" html)))
           (kfh-ok "numbers are grouped" (string-match-p ">57,708<" html))
           (kfh-ok "counter travels in data-count"
                   (string-match-p "<td data-count=\"57708\">" html))
           (delete-file log) (delete-file out)))

(kfh-test "there is exactly one heat map, driven by a mode menu"
         (let* ((log (kfh-fixture '(((org-mode . next-line) . 40)
                                    ((dired-mode . dired-toggle-marks) . 7))))
                (keyfreq-file log)
                (out (expand-file-name "card.html" kfh-tmp)))
           (require 'dired)
           (keyfreq-html-v2 out nil)
           (let ((html (kfh-slurp out)))
             (kfh-ok "exactly one canvas element"
                     (= 1 (let ((n 0) (p 0))
                            (while (string-match "<canvas id=\"heatmap\"" html p)
                              (setq n (1+ n) p (match-end 0)))
                            n)))
             (kfh-ok "there is a mode select"
                     (string-match-p "id=\"mode-select\"" html))
             (kfh-ok "it lists every mode plus All"
                     (and (string-match-p "<option value=\"all\">" html)
                          (string-match-p "<option value=\"org-mode\">" html)
                          (string-match-p "<option value=\"dired-mode\">" html)))
             (kfh-ok "there is a scale select"
                     (string-match-p "id=\"scale-select\"" html))
             (kfh-ok "no leftover per-section canvases"
                     (not (string-match-p "<canvas></canvas>" html))))
           (delete-file log) (delete-file out)))

(kfh-test "tables are sortable by command, shortcut and count"
         (let* ((log (kfh-fixture '(((org-mode . next-line) . 7)
                                    ((org-mode . save-buffer) . 2))))
                (keyfreq-file log)
                (out (expand-file-name "sortable.html" kfh-tmp)))
           (keyfreq-html-v2 out nil)
           (let ((html (kfh-slurp out)))
             (dolist (key '("count" "percent" "command" "shortcut"))
               (kfh-ok (format "the %s column has a sort button" key)
                       (string-match-p
                        (format "class=\"sort\" data-sort=\"%s\"" key)
                        html)))
             (kfh-ok "the default order is marked as descending"
                     (string-match-p "aria-sort=\"descending\"" html))
             (kfh-ok "the Mode menu is the only mode picker"
                     (and (string-match-p "id=\"mode-select\"" html)
                          (not (string-match-p "id=\"mode-order\"" html))))
             (kfh-ok "the all view and the mode view both exist"
                     (and (string-match-p "data-mode=\"all\"" html)
                          (string-match-p "data-mode=\"org-mode\"" html))))
           (delete-file log) (delete-file out)))

(kfh-test "no git history means no period menu and no data blob"
         (let* ((log (kfh-fixture '(((org-mode . next-line) . 3))))
                (keyfreq-file log)
                (out (expand-file-name "nohist.html" kfh-tmp)))
           (let ((keyfreq-html-history nil))
             (keyfreq-html-v2 out nil))
           (let ((html (kfh-slurp out)))
             (kfh-ok "no history script is embedded"
                     (not (string-match-p "id=\"keyfreq-data\"" html)))
             (kfh-ok "no period menu"
                     (not (string-match-p "id=\"period-select\"" html)))
             (kfh-ok "the mode menu is still there"
                     (string-match-p "id=\"mode-select\"" html)))
           (delete-file log) (delete-file out)))

(kfh-test "mode names are escaped everywhere they appear"
         (let* ((weird (intern (concat "weird<mode>&" "\"" "name")))
                (log (kfh-fixture (list (cons (cons weird 'next-line) 11))))
                (keyfreq-file log)
                (out (expand-file-name "weird.html" kfh-tmp)))
           (keyfreq-html-v2 out nil)
           (let ((html (kfh-slurp out)))
             (kfh-ok "attribute is escaped"
                     (string-match-p "data-mode=\"weird&lt;mode&gt;&amp;&quot;name\"" html))
             (kfh-ok "heading is escaped"
                     (string-match-p ">weird&lt;mode&gt;&amp;&quot;name</h2>" html))
             (kfh-ok "no raw markup leaks through"
                     (not (string-match-p "weird<mode>" html))))
           (delete-file log) (delete-file out)))

(kfh-test "anchors resolve and ids are unique"
         (let* ((log (kfh-fixture '(((org-mode . org-return) . 5)
                                    ((text-mode . next-line) . 3)
                                    ((fundamental-mode . save-buffer) . 1))))
                (keyfreq-file log)
                (out (expand-file-name "anchors.html" kfh-tmp)))
           (keyfreq-html-v2 out nil)
           (let* ((html (kfh-slurp out))
                  (ids (kfh-ids html))
                  (hrefs (kfh-hrefs html)))
             (kfh-ok "the document is a single column, no mode sidebar"
                     (not (string-match-p "<nav class=\"header\"" html)))
             (kfh-ok "every href has a matching id"
                     (cl-every (lambda (h) (member h ids)) hrefs))
             (kfh-ok "ids are unique"
                     (= (length ids) (length (delete-dups (copy-sequence ids))))))
           (delete-file log) (delete-file out)))

(kfh-test "a mode name containing / does not break anything"
         (let* ((log (kfh-fixture '(((benchmark-init/tree-mode . save-buffer) . 7)
                                    ((benchmark-init/tree-mode . keyboard-quit) . 2))))
                (keyfreq-file log)
                (out (expand-file-name "slash.html" kfh-tmp)))
           (keyfreq-html-v2 out nil)
           (let ((html (kfh-slurp out)))
             (kfh-ok "the section keeps the real name in data-mode"
                     (string-match-p "data-mode=\"benchmark-init/tree-mode\"" html))
             (kfh-ok "no heading carries an unsafe id"
                     (not (string-match-p "id=\"benchmark-init/tree-mode\"" html)))
             (kfh-ok "no raw id with a slash"
                     (not (string-match-p "id=\"benchmark-init/tree-mode\"" html))))
           (delete-file log) (delete-file out)))

(kfh-test "keyfreq-html (v1) also declares its encoding"
         (let* ((log (kfh-fixture '(((org-mode . org-return) . 3))))
                (keyfreq-file log)
                (out (expand-file-name "v1.html" kfh-tmp)))
           (keyfreq-html out t)
           (let ((html (kfh-slurp out)))
             (kfh-ok "has a doctype" (string-prefix-p "<!DOCTYPE html>" html))
             (kfh-ok "has a charset" (string-match-p "<meta charset=\"utf-8\">" html))
             (kfh-ok "has a title" (string-match-p "<title>" html))
             (kfh-ok "has no obsolete <a name>" (not (string-match-p "<a name=" html))))
           (delete-file log) (delete-file out)))

(kfh-test "the previous temporary report is cleaned up"
         (let* ((log (kfh-fixture '(((org-mode . org-return) . 1))))
                (keyfreq-file log)
                (first nil) (second nil))
           (setq first (keyfreq-html-v2 nil nil))
           (kfh-ok "a temp report was written" (file-exists-p first))
           (setq second (keyfreq-html-v2 nil nil))
           (kfh-ok "the new report exists" (file-exists-p second))
           (kfh-ok "the previous temp report was removed"
                   (not (file-exists-p first)))
           (kfh-ok "an explicit filename is not treated as a temp report"
                   (let ((named (expand-file-name "named.html" kfh-tmp)))
                     (keyfreq-html-v2 named nil)
                     (and (file-exists-p named)
                          (not (equal keyfreq-html--last-temp-report named)))))
           (delete-file log)))

(princ (format "\n----------------------------------------\n%d passed, %d failed\n"
               kfh-pass kfh-fail))
(delete-directory kfh-tmp t)
(if (null kfh-failures)
    (princ "ALL TESTS PASSED\n")
  (progn (princ (format "FAILURES: %S\n" (nreverse kfh-failures)))
         (kill-emacs 1)))
