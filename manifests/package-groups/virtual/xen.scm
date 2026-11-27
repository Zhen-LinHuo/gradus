;;; Xen Virtual Machine Host Server
;;;
;;; From the openSUSE Tumbleweed pattern 'xen_server + xen_tools' (patterns-
;;; server).
;;; Packages with no same-named Guix package were removed.
;;; Same-upstream renames (SUSE name -> Guix name):
;;;   xen-libs -> xen
;;;   xen-tools -> xen
;;;   virt-install -> virt-manager
;;;   libvirt-daemon-xen -> libvirt
;;;   libvirt-client -> libvirt
;;;   libvirt-daemon-config-network -> libvirt
;;; Removed (no Guix package):
;;;   tftp
;;;   tigervnc
;;;   xen-doc-html
;;; Merged from the two TW Xen patterns (xen_server, xen_tools).
(specifications->manifest
 (list "xen" "libvirt" "virt-manager" "openssh" "vim" "virt-viewer" "xauth"))
