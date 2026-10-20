# Keyfreq fork

## About

This is a fork of [`keyfreq`](https://github.com/dacap/keyfreq), which counts how
often you run each Emacs command.  The fork keeps the statistics file small and
diffable, and rebuilds the HTML report around an interactive keyboard heat map.

Compared with upstream:

| | upstream | this fork |
| --- | --- | --- |
| saving | regenerates the whole file on every save | patches counters in place |
| statistics file | churns on every save | only changed lines change |
| report | one table per mode, stacked | one table at a time, chosen from a menu |
| heat map | one static canvas per mode | a single interactive canvas |
| shortcuts | resolved in the global keymap | resolved in each mode's own keymap |
| time | cumulative only | today / 7 days / 30 days / git snapshots |

![The report](./assets/keyfreq-html-v2.png)

## The report

`M-x keyfreq-html-v2` writes a **single self-contained HTML file** -- the
stylesheet and the script are inlined, so the report can be moved, mailed or
committed and still works.  It opens the file in your browser; with a prefix
argument (`C-u`) it asks where to save instead of using a temporary file.

### Keyboard heat map

One canvas, four controls and no page-level clutter:

* **Mode** -- `All major modes` or any single mode.  It drives the heat map
  *and* the table below it, so choosing `org-mode` shows org-mode's keys and
  org-mode's commands together.
* **Scale** -- `sqrt` (default), `linear` or `log`.  Command usage spans four
  orders of magnitude; a linear scale leaves almost every key blank.
* **Period** -- `Today`, `Last 7 days`, `Last 30 days`, one entry per month
  found in the git history of `keyfreq-file`, and `All time` (the default).
* **Hover** -- shows the key, the number of presses and its share.
* **Key caps** -- drawn the way a MacBook Air prints them: the shifted symbol
  above the base one (`:` over `;`, `!` over `1`), and `⌃` `⌥` `⌘` for
  Control, Option and Command.  Both legends of a cap are the same physical
  key, so their presses are added together and either one can be hovered or
  clicked.
* **Click** -- focuses a key: it is outlined, the keys it is used with (a
  modifier with the keys it modifies, and the keys of a multi-key sequence)
  keep their heat, every other key fades to a flat grey so the map keeps its
  shape, and the table keeps only the commands that use it.  Click the chip,
  press `Escape' or click the key again to clear it.
* **Modifiers** -- `C-`, `M-`, `S-`, `s-` and `A-` light the Control, Option,
  Shift and Command keys; `s-` is Super (Command), not the letter `s`, and
  names like `<return>` or `<space>` are matched to their key caps.

Heat is a single accent ramp over a neutral key cap rather than a rainbow: a
rainbow invents banding that is not in the data.  The canvas follows
`prefers-color-scheme` and scales with `devicePixelRatio`.

### The table

Below the map there is exactly one table -- the selected mode -- with
`Times`, `%`, `Command` and `Shortcut` columns.  Every column header sorts, and
clicking it again reverses the order.  Commands with no key binding sort last.

Only the selected table is rendered: the other modes stay in the document (so
the report still reads without JavaScript) but are hidden, and they are rebuilt
lazily when you pick them.

### Shortcuts are resolved per mode

Upstream resolved every shortcut against the currently active keymaps, in
practice `global-map`, so any command bound only in a major mode's keymap showed
no key at all.

The report now resolves each mode/command pair in that mode's own
`<mode>-map`, and:

* drops `menu-bar` / `tool-bar` / `tab-bar` / `mode-line` / mouse pseudo
  bindings -- they are not keystrokes;
* credits only the **first** real binding of a command.  `keyfreq` counts
  commands, so counting a press once per binding would multiply it;
* skips unprintable key ranges, so the file is always valid UTF-8.

Resolving is still a guess, though: a command with two bindings gets one of
them, and every typed character is the single command
`self-insert-command`, so the character area cannot be split at all.

### Recorded keys

With `keyfreq-record-keys` (the default) keyfreq also stores the key
sequence that actually invoked each command, taken from
`this-command-keys` at the moment it runs, in a side file
(`<keyfreq-file>.keys`):

``` elisp
(((org-mode . self-insert-command) . 100)     ; the counter, as always
((org-mode self-insert-command "a") . 60)     ; the side file
((org-mode self-insert-command "b") . 40)
((org-mode next-line "C-n") . 10)
((org-mode next-line "<down>") . 5)
```

The report draws the recorded keys when it has them and falls back to
resolving the command for older counts, so both are visible at once and
nothing has to be migrated.  Two things that were impossible become plain
facts: typed characters get their own keys, and a command bound twice
contributes to each binding by its real share.  The side file is patched in
place and grows one line per (mode, command, key) used.

A period view has no per-period key split, so it applies the recorded
proportions to that period's counts.

### Keys that never run a command

A command loop only sees commands, so some keys were invisible: the
answers to `y-or-n-p', the per-hit keys of `query-replace', and anything
else read with `read-event' / `read-char' / `read-key' while a command is
running.  `keyfreq-record-prompts' (the default) advises those three
functions and counts what they return:

* they are counted under the pseudo command `keyfreq-prompt', because no
  real command runs for them -- add that name to
  `keyfreq-excluded-commands' to hide the row again;
* they enter the same key file, so the heat map shows `y`, `n` and `q`
  for a replacement session.

What still cannot be recorded, at this level:

* `ESC` on its own.  Emacs maps it to `meta-prefix-char`, so it is a
  prefix, not a command: nothing runs and nothing is counted.  `ESC` followed
  by a key arrives as `M-<key>` (the heat map lights the Option key), and the
  ESC cap itself never lights up.
* other bare prefixes (`C-x`, `C-c`, `C-h`, ...), and any key that aborts
  instead of running a command;
* keys that go to a subprocess, as in `vterm` or `ansi-term`;
* keys pressed in other applications.

> The figures below are the author's own usage, not a property of the patch.
> On that log -- 5,028 mode/command pairs over 140 modes -- `org-mode` resolved
> **57.7%** of its presses to a key with the upstream code and **88.1%** with
> the fork.  `org-return` alone carried 57,708 presses there and displayed no
> key, although it is `RET`.  Your own split will differ; only the mechanism
> is general.

## Saving behaviour

`keyfreq` keeps its statistics in `keyfreq-file` (by default `~/.emacs.keyfreq`),
one `((major-mode . command) . count)` entry per line.

Saving used to regenerate the whole file from the in-memory hash table, and the
writer emitted entries in reverse order, so every save rewrote every line: a log
of N entries produced a diff of roughly N lines touched, whatever you did in
between.

A save now patches the file in place:

* an entry that already exists keeps its line and only its counter is rewritten;
* a command that is not in the file yet is appended as a new line, right before
  the closing parenthesis;
* every other byte is untouched, so `git diff` shows only what really changed.

The writer is also safer: it writes through a temporary file and renames it into
place, it never drops the in-memory deltas unless the data reached the disk, and
a truncated or damaged file is copied to `keyfreq-file.corrupt-<timestamp>`
before the readable entries are salvaged, instead of wiping the history.

### One file per day

Cumulative counters can only answer "since the beginning", so the fork also
writes one small file per day:

```
~/.emacs.d/assets/keyfreq-log                  cumulative rollup
~/.emacs.d/assets/keyfreq-days/.baseline.log   the rollup before the split
~/.emacs.d/assets/keyfreq-days/2026-10-18.log  today's deltas
~/.emacs.d/assets/keyfreq-days/2026-10-17.log  yesterday, frozen
```

The daily archives are authoritative; `keyfreq-file` is a materialised view that
`M-x keyfreq-rebuild-rollup` can regenerate from the baseline plus every daily
file.  A failed archive write keeps the counters for the next save; a failed
rollup write still clears them (they are safely archived) and rebuilds the
rollup on the next save.

Cost of reading a window, measured on a log with about 5,000 entries (it grows
with the number of entries, not with this particular history):

| window | files | parse |
| --- | --- | --- |
| today | 1 | 0.6 ms |
| last 7 days | 7 | 13 ms |
| last 30 days | 30 | 16 ms |
| all time | 1 (`keyfreq-file`) | 14 ms |

Each save touches only `keyfreq-log` and today's file, so the archives stay
friendly to version control.

## Drawbacks

1. The keyboard layout is **hardcoded** (Apple).  Feeding it a JSON layout from
   [keyboard-layout-editor.com](http://www.keyboard-layout-editor.com/) would
   generalise it.
2. Without `keyfreq-record-keys` the map is a map of **hotkeys**, not of typing:
   `keyfreq` records the command you ran, and the key is resolved afterwards.  On the author's log roughly
   49% of the recorded presses are mouse events, 22% are typing collapsed into
   the single `self-insert-command` counter, 10% resolve to no binding at all,
   and only about 29% land on a physical key -- those proportions depend
   entirely on how you use Emacs, so treat them as an illustration, not as a
   normalisation.  The character area can never be split per letter without
   recording `this-command-keys`.
3. With recorded keys a second binding counts by its own share; without them a
   command with several bindings is drawn on its first one only.  Counters
   collected before `keyfreq-record-keys` was enabled keep the old behaviour.
4. Auto-generated key descriptions can be surprising: in `dired`,
   `revert-buffer` is `<menu-bar> <file> <revert-buffer>` when you actually press
   `g`.  Pseudo bindings are now filtered out, so the row simply shows no key.
5. The git-history periods depend on the log being committed: months with no
   commits, or counters that were reset by hand, are visible as such.
6. `keyfreq-html` is now the same report as `keyfreq-html-v2` (kept for
   compatibility); there is no longer a separate plain-table page.
7. JavaScript is required for the heat map and for the single-table view.  With
   it disabled the report still lists every table, just as one long page.

## Installation

### Manually

Download this repository to a folder and add this folder to your `load-path`.

``` elisp
(require 'keyfreq)
(keyfreq-mode 1)
(keyfreq-autosave-mode 1)
```

An additional setting is required with this fork: the location of the keyfreq
folder, which holds the inlined `style.css` and `script.js`:

``` elisp
(setq keyfreq-folder "<keyfreq-installation-folder>")
```

### With use-package and quelpa

``` elisp
(use-package keyfreq
  :quelpa ((keyfreq :fetcher github :repo "KirmTwinty/keyfreq") :upgrade t :ensure t)
  :bind (("C-c k" . keyfreq-html-v2))
  :config
  (setq keyfreq-folder "~/.emacs.d/quelpa/build/keyfreq/")
  (keyfreq-mode 1)
  (keyfreq-autosave-mode 1)
  (setq keyfreq-excluded-commands
        '(self-insert-command
          mwheel-scroll))
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

| Command | What it does |
| --- | --- |
| `keyfreq-show` | How many times each command ran, in a buffer. |
| `keyfreq-html-v2` | The interactive report.  `C-u` asks where to save it. |
| `keyfreq-html` | Same report, kept for compatibility. |
| `keyfreq-json` | The raw statistics as JSON. |
| `keyfreq-sort-file` | One-off normalisation: sort the statistics file by key. |
| `keyfreq-rebuild-rollup` | Regenerate `keyfreq-file` from the baseline and the daily archives. |
| `keyfreq-save-now` | Save the counters immediately. |
| `keyfreq-where-is` | Keys a command is bound to; pass a keymap to see a mode's own bindings. |

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| `keyfreq-file` | `~/.emacs.keyfreq` | The cumulative statistics file. |
| `keyfreq-file-lock` | `<file>.lock` | Lock file, so two Emacsen do not clobber each other. |
| `keyfreq-incremental-save` | `t` | `nil` regenerates the whole file (the old behaviour). |
| `keyfreq-daily-archive` | `t` | Keep one file per day; `nil` writes no directory at all. |
| `keyfreq-daily-directory` | next to `keyfreq-file` | Where the daily archives live. |
| `keyfreq-html-history` | `t` | Read the git history for the period menu.  `nil` skips it, which saves a few seconds on a repository with a long history of the file. |
| `keyfreq-coding-system` | `nil` | Coding system of the file; `nil` detects it, so an existing file keeps its encoding. |
| `keyfreq-record-keys` | `t` | Record the key sequence that invoked each command, in `<keyfreq-file>.keys`. |
| `keyfreq-record-prompts` | `t` | Also count keys read outside the command loop (`y-or-n-p`, `query-replace`), under `keyfreq-prompt`. |
| `keyfreq-key-file` | `nil` | Where the recorded keys live; `nil` derives it from `keyfreq-file`. |
| `keyfreq-excluded-commands` | `nil` | Commands that are never counted (noise such as `mouse-*`). |
| `keyfreq-excluded-regexp` | `nil` | Regexps of commands that are never counted. |
| `keyfreq-autosave-timeout` | `600` | Seconds between automatic saves. |

## Running the tests

``` sh
emacs --batch -l test/keyfreq-tests.el        # persistence, 51 assertions
emacs --batch -l test/keyfreq-html-tests.el   # the report, 59 assertions
```

Both suites build their own fixtures in a temporary directory and never touch
your real `keyfreq-file`.
