# Keyfreq fork

## About

This is a fork of `keyfreq` available [here](https://github.com/dacap/keyfreq).
I just added the `keyfreq-html-v2` function that prettifies
the HTML page and more interestingly adds a representation of
the frequencies on a keyboard map.

You can remove a specific key on the map to automatically change the colorscale
by using the text input at the top of the page with for instance `['C', 'a']` to
remove `Ctrl` and `a` key from the heat map count.

![Screenshot](./assets/keyfreq-html-v2.png
"Screenshot of the new rendered page")

You need Javascript to be enabled in your web browser.

## Drawbacks

1. I am not a web developer so sorry for the non-responsive web design.
   This was just an "empty-morning project".
1. Please note that `keyfreq` returns all the shortcuts associated to
   the commands you use. It means that the generated keyboard map does
   not represent the keys you actually typed but a rough approximation.
1. Some shortcuts are not registered by `keyfreq` and therefore misinterpreted.
   (in dired, the `refresh-buffer` command is `<menu-bar> <file> <revert-buffer>`
   whereas my actual shortcut is `g`)
1. For now only the keyboard layout I use is **hardcoded**.
   It is however possible to improve this by using JSON keyboard file format
   from [keyboard-layout-editor.com](http://www.keyboard-layout-editor.com/)
   for instance.

## Installation

### Manually

Download this repository to a folder and add this folder
to your `load-path`.

Then, include the following lines in your `.emacs` file:

``` elisp
    (require 'keyfreq)
    (keyfreq-mode 1)
    (keyfreq-autosave-mode 1)
```

An additional setting is required with this fork:
you need to specify the location of the keyfreq folder with:

``` elisp
	(setq keyfreq-folder "<keyfreq-installation-folder>")
```

### With use-package and quelpa

Here is the installation to use with `use-package` and `quelpa-use-package`:

``` elisp
(use-package keyfreq
  :quelpa ((keyfreq :fetcher github :repo "KirmTwinty/keyfreq") :upgrade t :ensure t)
  :config
  (setq keyfreq-folder "~/.emacs.d/quelpa/build/keyfreq/")
  (keyfreq-mode 1)
  (keyfreq-autosave-mode 1)
  (setq keyfreq-excluded-commands
	'(self-insert-command))
  ;; To exclude commands:
  ;; (setq keyfreq-excluded-commands
  ;;     '(self-insert-command
  ;;       forward-char
  ;;       backward-char
  ;;       previous-line
  ;;       next-line))
  )
```

## How to use

Use `keyfreq-show` to see how many times you used a command.
Use `keyfreq-html` to write a plain HTML table of the statistics.
Use `keyfreq-html-v2` to get the keyboard heat map.

`keyfreq-html-v2` writes a **single self-contained HTML file** -- the
stylesheet and the script are inlined, so the report can be moved, mailed or
committed without losing its behaviour.  It opens the file in your browser;
with a prefix argument (`C-u`) it asks where to save it instead of using a
temporary file.  Modes are listed most-used first, and the "Skip keys" box
re-colours every heat map from a JSON list such as `["C", "S"]`.

## Saving behaviour

`keyfreq` keeps its statistics in `keyfreq-file` (by default `~/.emacs.keyfreq`),
one `((major-mode . command) . count)` entry per line.

Saving used to regenerate the whole file from the in-memory hash table.  That made
version control useless: the writer emitted the entries in reverse order, so every
save rewrote every line -- a 5000-entry log changed by about 10000 lines per save,
regardless of how little you actually used Emacs.

A save now patches the file in place:

* an entry that already exists keeps its line and only its counter is rewritten;
* a command that is not in the file yet is appended as a new line, in sorted
  order, right before the closing parenthesis;
* every other byte is left untouched, so `git diff` shows only what really changed.

| Setting / command | Default | Meaning |
| --- | --- | --- |
| `keyfreq-incremental-save` | `t` | Bind to `nil` to regenerate the whole file (the old behaviour). |
| `keyfreq-coding-system` | `nil` | Coding system for the file.  `nil` detects it, so an existing file keeps its own encoding. |
| `M-x keyfreq-sort-file` | -- | One-off normalisation: sort the file by key for perfectly stable, line-aligned diffs. |

The writer is also safer than before: it writes through a temporary file and renames
it into place, it never drops the in-memory deltas unless the data reached the disk,
and a truncated or damaged file is copied to `keyfreq-file.corrupt-<timestamp>`
before the readable entries are salvaged, instead of silently wiping the history.

### Running the tests

``` sh
emacs --batch -l test/keyfreq-tests.el
```

## How to exclude commands

``` elisp
    (setq keyfreq-excluded-commands
          '(self-insert-command
            forward-char
            backward-char
            previous-line
            next-line))
```
