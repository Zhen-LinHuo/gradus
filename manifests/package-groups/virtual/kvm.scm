;;; KVM Host Server
;;;
;;; From the openSUSE Tumbleweed pattern 'kvm_server + kvm_tools' (patterns-
;;; server).
;;; Packages with no same-named Guix package were removed.
;;; Same-upstream renames (SUSE name -> Guix name):
;;;   libvirt-daemon-config-network -> libvirt
;;;   libvirt-daemon-driver-network -> libvirt
;;;   libvirt-daemon-driver-qemu -> libvirt
;;;   libvirt-daemon-driver-storage-core -> libvirt
;;;   libvirt-daemon-qemu -> libvirt
;;;   libvirt-client -> libvirt
;;; Removed (no Guix package):
;;;   tftp
;;;   virt-v2v
;;; Merged from the two TW KVM patterns (kvm_server, kvm_tools).
(specifications->manifest
 (list "libvirt" "virt-manager" "openssh" "vim" "virt-viewer" "xauth"))
