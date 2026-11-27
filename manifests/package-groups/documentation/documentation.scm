;;; Help and Support Documentation
;;;
;;; From the openSUSE Tumbleweed pattern 'documentation' (patterns-base).
;;; Packages with no same-named Guix package were removed.
;;; Same-upstream renames (SUSE name -> Guix name):
;;;   man -> man-db
;;; Removed (no Guix package):
;;;   pam-manpages
;;; ;;; texinfo is an addition, not from the pattern: the info reader, since
;;; Guix packages ship info files.
(specifications->manifest
 (list "man-db" "man-pages" "texinfo"))
