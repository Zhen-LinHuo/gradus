;;; Internet Gateway
;;;
;;; Copied from the openSUSE Tumbleweed pattern 'gateway_server'
;;; (patterns-base-20241218 / patterns-server-20250313);
;;; packages with no same-named Guix package were removed,
;;; none substituted (2 removed).
(specifications->manifest
 (list "ddclient" "fetchmail" "radvd" "squid" "whois" "wireshark"))
