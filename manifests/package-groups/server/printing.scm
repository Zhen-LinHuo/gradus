;;; Print Server
;;;
;;; From the openSUSE Tumbleweed pattern 'printing' (patterns-server).
;;; Packages with no same-named Guix package were removed.
;;; Removed (no Guix package):
;;;   OpenPrintingPPDs-ghostscript
;;;   OpenPrintingPPDs-hpijs
;;;   OpenPrintingPPDs-postscript
;;;   cups-backends
;;;   cups-filters-cups-browsed
;;;   gutenprint
;;;   hplip-driver-hpcups
;;;   manufacturer-PPDs
(specifications->manifest
 (list "cups" "cups-filters" "epson-inkjet-printer-escpr" "samba" "splix"))
