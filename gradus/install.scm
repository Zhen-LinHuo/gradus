;;; gradus/install.scm — the installation backend shared by every front-end.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus install)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (gradus utils)
  #:use-module (gradus fs)
  #:use-module (gradus selection)
  #:use-module (gradus storage)
  #:use-module (gradus render)
  #:use-module (gradus serialize)
  #:use-module (gradus answers)
  #:use-module (gradus config)
  #:use-module (gradus provenance)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (ice-9 format)
  #:use-module (guix build utils)
  #:export (mount-plan
            resolve-source
            install-config
            install-answers
            install-answers/alist
            apply-proxy-environment
            restart-guix-daemon))


(define (resolve-source source)
  "Turn LABEL=... into a device path: mount would resolve it through
/dev/disk/by-label, which only exists once udev has noticed the new
filesystem -- and an installer mounts seconds after mkfs.  findfs scans the
devices directly and needs no udev."
  (if (and (string? source) (string-prefix? "LABEL=" source))
      (let* ((port         (open-input-pipe (string-append (system-tool "findfs") " " source)))
             (line (read-line port))
             (status (close-pipe port)))
        (if (and (string? line) (string-prefix? "/dev/" line))
            line
            source))
      source))

(define (mount-plan plan root)
  "Mount every file system in PLAN beneath ROOT, parents first.  Return #t on
success; raise on the first failure."
  (for-each
   (lambda (fs)
     (let* ((point (assoc-ref fs 'mount-point))
            (target (if (string=? point "/")
                        root
                        (string-append root point)))
            (source (resolve-source (assoc-ref fs 'source)))
            (type (assoc-ref fs 'type))
            (options (assoc-ref fs 'options)))
       (mkdir-p target)
       (log-line "mounting ~a on ~a (~a)" source target type)
       (let ((args (append (list "mount" "-t" type)
                           (if (and (string? options)
                                    (not (string=? options "")))
                               (list "-o" options)
                               '())
                           (list source target))))
         (unless (zero? (apply run-command/stream args))
           (error "mount failed" source target)))))
   (assoc-ref plan 'file-systems))
  #t)

(define (install-config config-file root)
  "Validate CONFIG-FILE and install it beneath ROOT."
  (log-line "==> [1/4] checking the declaration: ~a" config-file)
  (unless (zero? (run-command/stream "guix" "system" "build"
                                     "--dry-run" "--no-grafts" config-file))
    (exit +exit-validation+))
  (let ((os (load-configuration config-file)))
    ;; A previous attempt may have left the target mounted, or files behind in
    ;; it; guix's mount refuses a non-empty directory, and an installer must be
    ;; safe to run twice.
    (log-line "==> [2/4] clearing ~a" root)
    (system* "sh" "-c" (string-append "umount -R " root " 2>/dev/null || true"))
    (when (zero? (status:exit-val (system* "mountpoint" "-q" root)))
      (error "the target is still mounted; unmount it first" root))
    (when (file-exists? root)
      (unless (zero? (status:exit-val
                      (system* "sh" "-c"
                               (string-append "find " root
                                              " -mindepth 1 -maxdepth 1 -exec rm -rf {} +"))))
        (error "cannot empty the target directory" root)))
    ;; mkfs has just written a label; the /dev/disk/by-label link appears once
    ;; udev has looked at the device.  Without this, mounting by label fails
    ;; with "can't find LABEL=...".
    (system* "sh" "-c" "udevadm trigger --settle 2>/dev/null || true")
    (log-line "==> [2/4] mounting the target beneath ~a" root)
    (catch #t
      (lambda () (mount-plan (configuration-plan os) root))
      (lambda (key . args)
        (log-line "cannot prepare the target: ~a" args)
        (exit +exit-target+)))
    (log-line "==> [3/4] installing the system (downloads may take 10-30 minutes)")
    (unless (zero? (run-command/stream "guix" "system" "init" config-file root))
      (exit +exit-install+))
    (write-provenance root config-file "config")
    (finish-target root)
    (log-line "==> [4/4] installed; declaration kept at ~a/etc/config.scm" root)))

;; Shut the target down after the last write.  Leaving it mounted shuts the
;; filesystem down uncleanly: on ext the journal stays unapplied, the free
;; counts in the superblock go stale, and GRUB can no longer read the
;; filesystem it is about to boot — it falls into rescue mode claiming
;; normal.mod is missing while the file sits right there.
;;
;; How a filesystem settles is its own business and its own tool: the row in
;; the capability table names the command (ext2/3/4 run e2fsck; btrfs and xfs
;; settle with the clean unmount alone, and btrfs check is a recovery tool
;; rather than a routine one).  A filesystem with no row is settled by the
;; unmount alone.
(define (findmnt-fields point)
  "Return the (source . type) filesystem mounted at POINT, or #f."
  (let ((port (open-pipe* OPEN_READ "findmnt" "-n" "-o" "SOURCE,FSTYPE" point)))
    (let ((line (read-line port)))
      (close-pipe port)
      (and (not (eof-object? line))
           (let ((fields (string-tokenize (string-trim-both line))))
             (and (= (length fields) 2)
                  (cons (first fields) (second fields))))))))

(define (finish-target root)
  "Unmount ROOT and settle its filesystem with the command its capability row
names.  Raise an installer error if the target stays mounted or the check
cannot repair the filesystem."
  (unless (member root '("/" "//"))
    (let* ((mounted (findmnt-fields root))
           (row (and mounted (fs-lookup (cdr mounted))))
           (settle (and row (fs-capability-settle row))))
      (log-line "==> unmounting ~a" root)
      (system* "sh" "-c" (string-append "umount -R " root " 2>/dev/null || true"))
      (when (zero? (status:exit-val (system* "mountpoint" "-q" root)))
        (error "the target is still mounted; it cannot be shut down cleanly" root))
      (let ((device (and mounted (car mounted))))
        (when (and settle device (file-exists? device))
          (log-line "==> checking ~a" device)
          (let ((status (status:exit-val
                         (system* "sh" "-c"
                                  (string-append (string-join settle " ")
                                                 " " device
                                                 " >/dev/null 2>&1")))))
            ;; The checker exits with a bitmask: 1 means errors corrected, 4
            ;; means errors left uncorrected — the latter must not be reported
            ;; as a successful install.
            (when (and status (>= status 4))
              (error "the filesystem check could not repair the target" device))))))))

(define (authorize-declared-keys answers)
  "Authorise the signing keys the answers name, when they are readable.  A
failure is reported, not fatal: an unauthorised builder simply will not be
used, and the installation falls back to the sources it can trust."
  (for-each
   (lambda (key)
     (when (file-exists? key)
       (unless (zero? (run-command/stream
                       "sh" "-c"
                       (format #f "guix archive --authorize < ~a" key)))
         (log-line "could not authorise ~a; its substitutes will be refused" key))))
   (selection-signing-keys answers)))

(define (apply-proxy-environment answers)
  "Put the proxy from the answers into this process's environment: channel
fetches and any HTTP the installer performs itself read these variables."
  (let ((environment (selection-proxy-environment answers)))
    (unless (null? environment)
      (for-each (lambda (pair) (setenv (car pair) (cdr pair)))
                environment)
      (log-line "proxy: http=~a https=~a no_proxy=~a"
                (or (assoc-ref environment "http_proxy") "-")
                (or (assoc-ref environment "https_proxy") "-")
                (or (assoc-ref environment "no_proxy") "-")))))

(define (wait-for-daemon-socket attempts)
  "Wait for the guix-daemon socket, up to ATTEMPTS seconds."
  (cond ((file-exists? "/var/guix/daemon-socket/socket") #t)
        ((zero? attempts) #f)
        (else (sleep 1) (wait-for-daemon-socket (- attempts 1)))))

(define (restart-guix-daemon answers)
  "Restart guix-daemon so that it inherits the proxy environment and the
declared substitute URLs.  Substitutes are fetched by the daemon, so
exporting the variables in this process does not reach them.  The restart is
part of every install; GRADUS_NO_DAEMON_RESTART=1 leaves a daemon the
operator does not own alone."
  (when (not (getenv "GRADUS_NO_DAEMON_RESTART"))
    (log-line "restarting guix-daemon to apply the proxy")
    (unless (zero? (run-command/stream "herd" "stop" "guix-daemon"))
      (log-line "could not stop guix-daemon")
      (exit +exit-install+))
    ;; A rerun must not leave a previous daemon competing for the store
    ;; locks; the restart owns the daemon from here on.
    (run-command/stream "pkill" "-x" "guix-daemon")
    (sleep 1)
    (let* ((urls (selection-substitute-urls answers))
           (url-option (if (pair? urls)
                           (string-append " --substitute-urls='"
                                          (string-join urls " ") "'")
                           "")))
      (unless (zero? (run-command/stream
                      "sh" "-c"
                      (string-append
                       "guix-daemon --build-users-group=guixbuild"
                       url-option
                       " >/var/log/gradus-daemon.log 2>&1 &")))
        (log-line "could not start guix-daemon")
        (exit +exit-install+)))
    (unless (wait-for-daemon-socket 20)
      (log-line "the daemon socket did not appear; restore it with 'herd start guix-daemon'")
      (exit +exit-install+))))

(define (install-answers/alist answers answers-file root)
  "Prepare the target from the ANSWERS alist, render, mount and install.
ANSWERS-FILE is where the answers are (or will be) recorded for provenance."
  (let* ((answers (validate-answers answers))
         (device-map (prepare-target answers))
         (os (render-answers/devices answers device-map))
         (declaration "/tmp/gradus-declaration.scm"))
    (apply-proxy-environment answers)
    (restart-guix-daemon answers)
    (serialize-to-file declaration answers device-map)
    (log-line "mounting the target beneath ~a" root)
    (catch #t
      (lambda () (mount-plan (configuration-plan os) root))
      (lambda (key . args)
        (log-line "cannot prepare the target: ~a" args)
        (exit +exit-target+)))
    (authorize-declared-keys answers)
    (log-line "installing")
    (let* ((urls (selection-substitute-urls answers))
           (options (if (null? urls) '()
                        (list (string-append "--substitute-urls="
                                             (string-join urls " "))))))
      (when (pair? urls)
        (log-line "substitutes: ~a" (string-join urls " ")))
      (unless (zero? (apply run-command/stream
                            (append (list "guix" "system" "init")
                                    options
                                    (list declaration root))))
        (exit +exit-install+)))
    (write-provenance root declaration "answers")
    (finish-target root)
    (log-line "installed; declaration kept at ~a/etc/config.scm" root)))

(define (install-answers answers-file root)
  "Read ANSWERS-FILE and install the system it describes beneath ROOT."
  (install-answers/alist (read-answers answers-file) answers-file root))
