;;; Base Development
;;;
;;; From the openSUSE Tumbleweed pattern 'base-devel_basis' (patterns-devel);
;;; the identifier here is 'base-devel', renamed from 'base-devel_basis' because
;;; the
;;; group names what it installs.
;;; Packages with no same-named Guix package were removed.
;;; Same-upstream renames (SUSE name -> Guix name):
;;;   cpp -> gcc-toolchain
;;;   gcc -> gcc-toolchain
;;;   gcc-c++ -> gcc-toolchain
;;;   gcc-info -> gcc-toolchain
;;;   libstdc++-devel -> gcc-toolchain
;;;   gdbm-devel -> gdbm
;;;   gettext-tools -> gettext
;;;   glibc-devel -> glibc
;;;   glibc-info -> glibc
;;;   makeinfo -> texinfo
;;;   ncurses-devel -> ncurses
;;;   zlib-devel -> zlib
;;;   binutils-devel -> binutils
;;;   db-devel -> db
;;;   e2fsprogs-devel -> e2fsprogs
;;;   gmp-devel -> gmp
;;;   libaio-devel -> libaio
;;;   openldap2-devel -> openldap
;;; Removed (no Guix package):
;;;   awk
;;;   bin86
;;;   libgcj-devel
;;;   libosip2-devel
;;;   pam-devel
(specifications->manifest
 (list "autoconf" "automake" "binutils" "bison" "db" "e2fsprogs" "fdupes" "gcc-toolchain" "gdbm" "gettext" "glibc" "gmp" "git" "gperf" "libaio" "libtool" "m4" "make" "ncurses" "openldap" "patch" "pkg-config" "sparse" "subversion" "texinfo" "zlib"))
