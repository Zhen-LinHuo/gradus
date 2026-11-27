;;; Hardware Support
;;;
;;; Copied from the openSUSE Tumbleweed pattern 'hardware'
;;; (patterns-base-20241218 / patterns-server-20250313);
;;; packages with no same-named Guix package were removed,
;;; none substituted (4 removed).
(specifications->manifest
 (list "ethtool" "hwinfo" "irqbalance"))
