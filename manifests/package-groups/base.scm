;;; Base System
;;;
;;; Copied from the openSUSE Tumbleweed pattern 'base'
;;; (patterns-base-20241218 / patterns-server-20250313);
;;; packages with no same-named Guix package were removed,
;;; none substituted (12 removed).
(specifications->manifest
 (list "bash" "coreutils" "glibc" "procps" "rpm" "shadow" "util-linux"))
