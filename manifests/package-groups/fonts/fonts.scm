;;; Fonts
;;;
;;; From the openSUSE Tumbleweed pattern 'fonts' (patterns-base).
;;; Packages with no same-named Guix package were removed.
;;; Same-upstream renames (SUSE name -> Guix name):
;;;   dejavu-fonts -> font-dejavu
;;;   liberation-fonts -> font-liberation
;;; Removed (no Guix package):
;;;   google-roboto-fonts
;;;   intlfonts-euro-bitmap-fonts
;;;   xorg-x11-fonts-core
;;;   xorg-x11-fonts
;;;   adobe-sourcecodepro-fonts
;;;   adobe-sourcesanspro-fonts
;;;   adobe-sourceserifpro-fonts
;;;   efont-unicode-bitmap-fonts
;;;   google-noto-sans-symbols-fonts
;;;   google-noto-sans-symbols2-fonts
;;;   noto-sans-fonts
;;;   stix-fonts
;;; ;;; The TW companion pattern fonts_opt had no surviving package and was not
;;; carried over.
(specifications->manifest
 (list "font-dejavu" "font-liberation"))
