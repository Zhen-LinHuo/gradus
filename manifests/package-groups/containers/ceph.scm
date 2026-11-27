;;; Ceph base
;;;
;;; From the openSUSE Tumbleweed pattern 'containers-ceph_base' (patterns-ceph).
;;; Packages with no same-named Guix package were removed.
;;; Same-upstream renames (SUSE name -> Guix name):
;;;   ceph-base -> ceph
;;;   ceph-common -> ceph
;;;   ceph-fuse -> ceph
;;;   ceph-grafana-dashboards -> ceph
;;;   ceph-iscsi -> ceph
;;;   ceph-mds -> ceph
;;;   ceph-mgr -> ceph
;;;   ceph-mgr-cephadm -> ceph
;;;   ceph-mgr-dashboard -> ceph
;;;   ceph-mgr-diskprediction-local -> ceph
;;;   ceph-mgr-rook -> ceph
;;;   ceph-mon -> ceph
;;;   ceph-osd -> ceph
;;;   ceph-prometheus-alerts -> ceph
;;;   ceph-radosgw -> ceph
;;; Removed (no Guix package):
;;;   ca-certificates
;;;   cephadm
;;;   rbd-mirror
;;;   rbd-nbd
;;;   tcmu-runner-handler-rbd
(specifications->manifest
 (list "ceph" "e2fsprogs" "gptfdisk" "kmod" "lvm2"))
