;;; Office Software
;;;
;;; From the openSUSE Tumbleweed pattern 'office' (patterns-office);
;;; the identifier here is 'libreoffice', renamed from 'office'
;;; because the group names what it installs.
;;; Packages with no same-named Guix package were removed.
;;; Same-upstream renames (SUSE name -> Guix name):
;;;   libreoffice-calc -> libreoffice
;;;   libreoffice-draw -> libreoffice
;;;   libreoffice-impress -> libreoffice
;;;   libreoffice-math -> libreoffice
;;;   libreoffice-writer -> libreoffice
(specifications->manifest
 (list "libreoffice"))
