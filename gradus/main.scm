;;; gradus/main.scm — executable entry point.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (gradus script))

(exit (main (command-line)))
