# Keyfreq fork

## About

This is a fork of `keyfreq` available [here](https://github.com/dacap/keyfreq).
I just added the `keyfreq-html-v2` function that prettifies
the HTML page and more interestingly adds a representation of
the frequencies on a keyboard map.

You can remove a specific key on the map to automatically change the colorscale
by using the text input at the top of the page with for instance `['C', 'a']` to
remove `Ctrl` and `a` key from the heat map count.

![Screenshot](https://github.com/KirmTwinty/keyfreq/raw/master/screenshot/keyfreq-html-v2.png
"Screenshot of the new rendered page")

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
Use `keyfreq-html` to get the original rendered HTML page.
Use `keyfreq-html-v2` to get the keyboard heat map.

## How to exclude commands

``` elisp
    (setq keyfreq-excluded-commands
          '(self-insert-command
            forward-char
            backward-char
            previous-line
            next-line))
```
