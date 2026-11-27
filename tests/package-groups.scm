;;; tests/package-groups.scm — reading the package-package-group manifests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (gradus package-groups))

(define runner (test-runner-simple))
(test-runner-current runner)

  (test-equal "the bundled groups are listed in file-name order"
    '(base console enhanced_base file_server gateway_server hardware)
    (package-group-ids))

  (test-equal "a group's description is its first comment line"
    "Internet Gateway"
    (package-group-description 'gateway_server))

  (test-equal "a group's packages come from its manifest"
    '("ddclient" "fetchmail" "radvd" "squid" "whois" "wireshark")
    (package-group-packages 'gateway_server))

  (test-assert "every group carries at least one package"
    (every (lambda (id) (pair? (package-group-packages id))) (package-group-ids)))

  (test-assert "the base group's packages are all names, not paths"
    (every (lambda (name)
             (and (string? name)
                  (not (string-contains name "/"))))
           (package-group-packages 'base)))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
