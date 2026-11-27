;;; tests/package-groups.scm — reading the package-group manifests.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (gradus package-groups))

(define runner (test-runner-simple))
(test-runner-current runner)

  (test-equal "the categories are the manifest subdirectories, in order"
    '("containers" "devel" "documentation" "fonts" "network" "office"
      "server" "system" "virtual")
    (map car (package-group-tree)))

  (test-equal "every category carries its groups, in file-name order"
    '((ceph docker podman)
      (base-devel)
      (documentation)
      (fonts)
      (gateway_server network_admin)
      (libreoffice)
      (file_server printing)
      (base console enhanced_base hardware)
      (kvm xen))
    (map cdr (package-group-tree)))

  (test-equal "the flat identifier list spans every category"
    17
    (length (package-group-ids)))

  (test-equal "a group's description is its first comment line"
    "Internet Gateway"
    (package-group-description 'gateway_server))

  (test-equal "a group's packages come from its manifest"
    '("ddclient" "fetchmail" "radvd" "squid" "whois" "wireshark")
    (package-group-packages 'gateway_server))

  (test-equal "the libreoffice group names its suite, not the category"
    '("libreoffice")
    (package-group-packages 'libreoffice))

  (test-equal "a same-upstream rename lands the Guix package"
    '("docker")
    (package-group-packages 'docker))

  (test-equal "the development group carries the toolchain under Guix names"
    '("autoconf" "automake" "binutils" "bison" "db" "e2fsprogs" "fdupes"
      "gcc-toolchain" "gdbm" "gettext" "glibc" "gmp" "git" "gperf" "libaio"
      "libtool" "m4" "make" "ncurses" "openldap" "patch" "pkg-config"
      "sparse" "subversion" "texinfo" "zlib")
    (package-group-packages 'base-devel))

  (test-assert "every group carries at least one package"
    (every (lambda (id) (pair? (package-group-packages id)))
           (package-group-ids)))

  (test-assert "the base group's packages are all names, not paths"
    (every (lambda (name)
             (and (string? name)
                  (not (string-contains name "/"))))
           (package-group-packages 'base)))

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
