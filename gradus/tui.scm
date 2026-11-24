;;; gradus/tui.scm — the console front-end.  It drives the same wizard core a
;;; future Web front-end will drive, so the pages stay identical.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus tui)
  #:use-module (ncurses curses)
  #:use-module (gradus answers)
  #:use-module (gradus install)
  #:use-module (gradus storage)
  #:use-module (gnu system shadow)
  #:use-module (gradus utils)
  #:use-module (gradus wizard)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (run-tui))

;; The input model follows the guile-ncurses manual: `cbreak!' makes single
;; characters available immediately, and `getnstr' does the line editing,
;; returning when <NL>, <CR> or <EOF> arrives.  Nothing here needs `raw!'.

(define %strings
  (list
   '((title . "Gradus 安装向导") (step . "步骤")
     (lang . "界面语言")
     (source . "安装源") (substitute . "Substitute 源地址")
     (proxy . "HTTP 代理（可留空）") (disks . "检测到的磁盘")
     (storage . "存储") (disk . "目标磁盘") (mode . "布局方式")
     (esp-size . "ESP 大小 (MiB)") (swap-size . "swap 大小 (MiB，0=不建)")
     (root-size . "root 大小 (MiB，0=剩余全部)")
     (encrypt . "加密 root？(y/n，使用 LUKS1)")
     (passphrase . "加密口令") (passphrase-again . "再输一次")
     (users . "用户") (username . "用户名")
     (password . "用户密码") (password-again . "再输一次")
     (root-password . "root 密码")
     (timezone . "时区") (locale . "语言区域")
     (keyboard . "键盘布局") (ntp . "启用 NTP 对时？(y/n)")
     (bootloader . "引导器") (timeout . "菜单等待秒数")
     (kernel-args . "额外内核参数（空格分隔）")
     (packages . "额外软件包（空格分隔，可留空）")
     (hostname . "主机名") (management . "网络管理方式")
     (back . "[b] 返回上一步")
     (review . "确认") (confirm . "开始安装？(y/n)")
     (installing . "正在安装，请勿关机……") (done . "安装完成")
     (choose . "输入序号后回车")
     (simple . "标准分区") (lvm . "LVM"))
   '((title . "Gradus installer") (step . "step")
     (lang . "Interface language")
     (source . "Installation source") (substitute . "Substitute server URL")
     (proxy . "HTTP proxy (may be empty)") (disks . "Disks found")
     (storage . "Storage") (disk . "Target disk") (mode . "Layout")
     (esp-size . "ESP size (MiB)") (swap-size . "Swap size (MiB, 0 = none)")
     (root-size . "Root size (MiB, 0 = rest of disk)")
     (encrypt . "Encrypt root? (y/n, uses LUKS1)")
     (passphrase . "Passphrase") (passphrase-again . "Again")
     (users . "User") (username . "User name")
     (password . "User password") (password-again . "Again")
     (root-password . "Root password")
     (timezone . "Timezone") (locale . "Locale")
     (keyboard . "Keyboard layout") (ntp . "Enable NTP time sync? (y/n)")
     (bootloader . "Bootloader") (timeout . "Menu timeout (seconds)")
     (kernel-args . "Extra kernel arguments (space separated)")
     (packages . "Extra packages (space separated, may be empty)")
     (hostname . "Host name") (management . "Network management")
     (back . "[b] back")
     (review . "Review") (confirm . "Start the installation? (y/n)")
     (installing . "Installing; do not power off…")
     (done . "Installation finished")
     (choose . "Type a number and press Enter")
     (simple . "Standard partitions") (lvm . "LVM"))))

(define (tr wizard key)
  "The string for KEY in the language the wizard has chosen."
  (let* ((lang (wizard-language wizard))
         (table (list-ref %strings (min lang (- (length %strings) 1)))))
    (assq-ref table key)))

;; --------------------------------------------------------------- drawing

(define (put win y x text)
  "Write TEXT at (Y, X) in WIN."
  (addstr win text #:y y #:x x))

(define (frame win wizard)
  "Paint the box, the title and the current step."
  (clear win)
  (box win (acs-vline) (acs-hline))
  (put win 0 2 (format #f " ~a " (tr wizard 'title)))
  (let ((rows (getmaxy win)))
    (put win (- rows 1) 2
         (format #f " ~a: ~a " (tr wizard 'step) (wizard-step wizard))))
  (refresh win))

;; ----------------------------------------------------------------- input

(define (ask wizard win y label default)
  "Draw LABEL with DEFAULT, read a line, and leave the cursor on the next row."
  (put win y 2 (format #f "~a (~a): " label default))
  (put win (+ y 1) 2 "> ")
  (refresh win)
  (let ((answer (getnstr win 200)))
    (if (or (not answer) (string-null? answer)) default answer)))

(define (ask-number wizard win y label options default-index)
  "Draw LABEL and numbered OPTIONS, then read a number.  Returns the index."
  (let loop ()
    (put win y 2 label)
    (let index-loop ((items options) (row (+ y 1)) (n 1))
      (unless (null? items)
        (put win row 4 (format #f "~a ~a" n (car items)))
        (index-loop (cdr items) (+ row 1) (+ n 1))))
    (put win (+ y 1 (length options)) 2 (tr wizard 'choose))
    (put win (+ y 2 (length options)) 2 "> ")
    (refresh win)
    (let* ((answer (getnstr win 8))
           (n (and answer (string->number answer))))
      (cond ((and (integer? n) (>= n 1) (<= n (length options))) (- n 1))
            ((string-null? (or answer "")) default-index)
            (else (loop))))))

(define (back? value)
  "Whether VALUE is the operator asking to go back one page."
  (and (string? value) (equal? (string-downcase value) "b")))

;; ----------------------------------------------------------------- pages

(define (page-language win wizard)
  ;; A text console font holds at most 512 glyphs, so this front-end cannot
  ;; render Chinese at all: offering it would promise something the console
  ;; cannot deliver.  The Chinese strings stay in %strings for the graphical
  ;; and web front-ends.
  (clear win)
  (box win (acs-vline) (acs-hline))
  (put win 0 2 " Gradus ")
  (put win 2 2 "This installer runs in English on a text console.")
  (put win 4 2 "A Chinese interface is available in the graphical and web")
  (put win 5 2 "installers, which are not yet part of this release.")
  (put win 7 2 "Press Enter to continue.")
  (put win 9 2 "> ")
  (refresh win)
  (getnstr win 8)
  (wizard-next (wizard-set-language wizard 1)))

(define (%disk-name entry)
  (string-append "/dev/" entry))

(define (%disk-size entry)
  "Size of the block device ENTRY in GB, from sysfs."
  (let ((path (format #f "/sys/block/~a/size" entry)))
    (if (file-exists? path)
        (let ((sectors (call-with-input-file path
                         (lambda (port)
                           (or (string->number (string-trim-both (read-line port))) 0)))))
          (/ (* sectors 512.0) (expt 1024 3)))
        0)))

(define (%disks)
  "Whole block devices.  Loop, ram and device-mapper nodes are not disks.  A
disk that is in use is listed too, with its mount points, so the operator can
see why: hiding a disk they expect is worse than showing it with a warning."
  (let ((dir (opendir "/sys/block")))
    (let loop ((found '()))
      (let ((entry (readdir dir)))
        (cond ((eof-object? entry)
               (closedir dir)
               (reverse found))
              ((or (string-prefix? "loop" entry)
                   (string-prefix? "ram" entry)
                   (string-prefix? "zram" entry)
                   (string-prefix? "sr" entry)
                   (string-prefix? "dm-" entry)
                   (string-prefix? "md" entry))
               (loop found))
              (else (loop (cons entry found))))))))

(define (%mounts)
  "The (device . mount-point) pairs currently mounted."
  (let ((lines (string-split
                (call-with-input-file "/proc/mounts" read-string) #\newline)))
    (filter-map
     (lambda (line)
       (let ((fields (string-split line #\space)))
         (and (>= (length fields) 2)
              (cons (list-ref fields 0) (list-ref fields 1)))))
     lines)))

(define (%disk-mounts disk)
  "Mount points held by DISK or any of its partitions."
  (filter-map (lambda (entry)
                (and (string-prefix? disk (car entry)) (cdr entry)))
              (%mounts)))

(define (ram-mib)
  "The machine's memory, in MiB, from /proc/meminfo."
  (call-with-input-file "/proc/meminfo"
    (lambda (port)
      (let loop ((line (read-line port)))
        (cond ((eof-object? line) 1024)
              ((string-prefix? "MemTotal:" line)
               (let ((fields (string-tokenize line)))
                 (max 1024 (quotient (or (string->number (cadr fields)) 1048576) 1024))))
              (else (loop (read-line port))))))))

(define (page-storage win wizard)
  (let* ((disks (%disks))
         (_ (when (null? disks)
              (error "no disk was found on this machine")))
         (info (map (lambda (name)
                      (cons name (%disk-mounts (%disk-name name))))
                    disks))
         (labels (map (lambda (entry)
                        (let ((name (car entry))
                              (mounts (cdr entry)))
                          (format #f "~a  (~,1f GB)~a"
                                  (%disk-name name) (%disk-size name)
                                  (if (null? mounts) ""
                                      (format #f "   [in use: ~a]"
                                              (string-join mounts ", "))))))
                      info))
         (choice (ask-number wizard win 3 (tr wizard 'disks) labels 0))
         (chosen (list-ref info choice))
         (disk (%disk-name (car chosen)))
         (mounts (cdr chosen)))
    (when (member "/" mounts)
      (error "that disk holds the running system; choose another one"))
    (when (pair? mounts)
      (put win (+ 5 (length labels)) 2
           (format #f "~a is in use (~a); it will be unmounted."
                   disk (string-join mounts ", ")))
      (put win (+ 7 (length labels)) 2 "Continue? (y/n)")
      (put win (+ 8 (length labels)) 2 "> ")
      (refresh win)
      (unless (member (string-downcase (or (getnstr win 8) "")) '("y" "yes"))
        (error "the operator declined to unmount the disk"))
      (for-each (lambda (mount)
                  (run-command/stream "umount" "-R" mount))
                mounts))
    (let* ((mode-row (+ 10 (length labels)))
           (mode (ask-number wizard win mode-row (tr wizard 'mode)
                              (list (tr wizard 'simple) (tr wizard 'lvm))
                              0))
           (mode-sym (if (zero? mode) 'simple 'lvm))
           (esp-row (+ 14 (length labels)))
           (esp (ask wizard win esp-row (tr wizard 'esp-size) "1024"))
           (swap-row (+ 17 (length labels)))
           (swap-default (number->string (default-swap-size (ram-mib))))
           (swap (ask wizard win swap-row (tr wizard 'swap-size) swap-default))
           (root-row (+ 20 (length labels)))
           (root (ask wizard win root-row (tr wizard 'root-size) "0"))
           (encrypt-row (+ 23 (length labels)))
           (encrypt (ask wizard win encrypt-row (tr wizard 'encrypt) "n"))
           (encryption
            (and (member (string-downcase encrypt) '("y" "yes"))
                 (let* ((first (ask-password wizard win (+ encrypt-row 2)
                                            (tr wizard 'passphrase)))
                        (again (ask-password wizard win (+ encrypt-row 4)
                                            (tr wizard 'passphrase-again))))
                   (unless (equal? first again)
                     (error "the two passphrases do not match"))
                   (list (cons 'mode 'luks)
                         (cons 'name "cryptroot")
                         (cons 'passphrase first)))))
           (swap-mib (or (string->number swap) 0))
           (_ (when (and encryption (> swap-mib 0))
                (error
                 "an encrypted install cannot use a separate swap partition (it would be plaintext); set the swap size to 0")))
           (_ (when (and encryption (eq? mode-sym 'lvm))
                (error
                 "encryption is not implemented for LVM storage yet; choose simple storage or drop the encryption")))
           (storage (storage-answers mode-sym disk
                                     #:esp-size (or (string->number esp) 1024)
                                     #:swap-size swap-mib
                                     #:root-size (or (string->number root) 0)
                                     #:encryption encryption)))
      (wizard-next (wizard-set wizard 'storage storage)))))

(define (ask-password wizard win y label)
  "Read a password without echoing it."
  (put win y 2 (format #f "~a: " label))
  (put win (+ y 1) 2 "> ")
  (refresh win)
  (noecho!)
  (let ((answer (getnstr win 200)))
    (echo!)
    answer))

(define (salt)
  "A salt for crypt, unique per run."
  (format #f "$6$~a" (number->string (+ (current-time) (getpid)) 16)))

(define (page-locale win wizard)
  (let ((keyboard (ask wizard win 3 (tr wizard 'keyboard) "us")))
    (if (back? keyboard)
        (wizard-back wizard)
        (let ((timezone (ask wizard win 6 (tr wizard 'timezone) "UTC")))
          (if (back? timezone)
              (wizard-back wizard)
              (let ((locale (ask wizard win 9 (tr wizard 'locale) "en_US.utf8")))
                (if (back? locale)
                    (wizard-back wizard)
                    (let ((ntp (ask wizard win 12 (tr wizard 'ntp) "y")))
                      (if (back? ntp)
                          (wizard-back wizard)
                          (let ((ntp-on (not (member (string-downcase ntp)
                                                     '("n" "no")))))
                            (wizard-next
                             (wizard-set
                              (wizard-set
                               (wizard-set
                                (wizard-set wizard 'keyboard keyboard)
                                'timezone timezone)
                               'locale locale)
                              'ntp ntp-on))))))))))))

(define (page-source win wizard)
  (let* ((url (ask wizard win 3 (tr wizard 'substitute)
                   "https://ci.guix.gnu.org"))
         (proxy (ask wizard win 6 (tr wizard 'proxy) "")))
    (cond
     ((back? url) (wizard-back wizard))
     ((back? proxy) (wizard-back wizard))
     (else
      (let* ((services (if (string-null? url)
                           '()
                           (list (list (cons 'name "primary")
                                       (cons 'url url)
                                       (cons 'kind 'official)))))
             (source (append
                      (if (null? services) '()
                          (list (cons 'substitute-services services)))
                      (if (string-null? proxy) '()
                          (list (cons 'proxy
                                      (list (cons 'http proxy)
                                            (cons 'https proxy)
                                            (cons 'no-proxy '()))))))))
        (wizard-next (wizard-set wizard 'source source)))))))

(define (page-boot win wizard)
  (let* ((default-index (if (eq? (firmware-bootloader) 'grub-efi) 1 0))
         (choice (ask-number wizard win 3 (tr wizard 'bootloader)
                             (list "grub-bios" "grub-efi") default-index))
         (wait (ask wizard win 7 (tr wizard 'timeout) "5"))
         (args (ask wizard win 10 (tr wizard 'kernel-args) "")))
    (cond
     ((back? wait) (wizard-back wizard))
     ((back? args) (wizard-back wizard))
     (else
      (let* ((bootloader (if (zero? choice) 'grub-bios 'grub-efi))
             (seconds (or (string->number wait) 5))
             (arguments (if (string-null? args)
                            '()
                            (string-split args #\space)))
             (boot (list (cons 'bootloader bootloader)
                         (cons 'timeout seconds)
                         (cons 'extra-kernel-arguments arguments))))
        (wizard-next (wizard-set wizard 'boot boot)))))))

(define (page-software win wizard)
  (let ((names (ask wizard win 3 (tr wizard 'packages) "")))
    (if (back? names)
        (wizard-back wizard)
        (wizard-next
         (wizard-set wizard 'software
                     (list (cons 'extra-packages
                                 (if (string-null? names) '()
                                     (string-split names #\space)))))))))

(define (page-network win wizard)
  (let ((name (ask wizard win 3 (tr wizard 'hostname) "gradus")))
    (if (back? name)
        (wizard-back wizard)
        (wizard-next
         (wizard-set (wizard-set wizard 'host-name name)
                     'network (list (cons 'management 'dhcp)))))))

(define (page-users win wizard)
  (let* ((name (ask wizard win 3 (tr wizard 'username) "user"))
         (password (ask-password wizard win 5 (tr wizard 'password)))
         (again (ask-password wizard win 7 (tr wizard 'password-again)))
         (root (ask-password wizard win 9 (tr wizard 'root-password)))
         (root-again (ask-password wizard win 11 (tr wizard 'password-again)))
         (_ (unless (equal? password again)
              (error "the two passwords do not match")))
         (_ (unless (equal? root root-again)
              (error "the two root passwords do not match")))
         (s (salt))
         (w (wizard-set wizard 'users
                        (list (list (cons 'name name)
                                    (cons 'group "users")
                                    (cons 'password (crypt password s)))))))
    (wizard-next (wizard-set w 'root-password (crypt root s)))))

(define (page-review win wizard)
  ;; A summary a human can check, not a dump of the answer form: passwords are
  ;; hashes at this point and must not be shown at all.
  (let* ((a (wizard-answers wizard))
         (storage (assq-ref a 'storage))
         (source (assq-ref a 'source))
         (services (assq-ref source 'substitute-services))
         (boot (assq-ref a 'boot))
         (users (assq-ref a 'users)))
    (put win 2 2 (format #f "host name   : ~a" (or (assq-ref a 'host-name) "gradus")))
    (put win 3 2 (format #f "disk        : ~a" (assq-ref storage 'disk)))
    (put win 4 2 (format #f "layout      : ~a" (assq-ref storage 'mode)))
    (put win 5 2 (format #f "bootloader  : ~a" (assq-ref boot 'bootloader)))
    (put win 6 2 (format #f "substitutes : ~a"
                         (if (pair? services)
                             (assq-ref (car services) 'url)
                             "official (default)")))
    (put win 7 2 (format #f "accounts    : root, ~a"
                         (string-join (map (lambda (u) (assq-ref u 'name)) users)
                                      ", ")))
    (put win 8 2 (format #f "system      : ~a, ~a, keyboard ~a, NTP ~a"
                         (or (assq-ref a 'timezone) "UTC")
                         (or (assq-ref a 'locale) "en_US.utf8")
                         (or (assq-ref a 'keyboard) "us")
                         (if (assq-ref a 'ntp) "on" "off")))
    (put win 9 2 (format #f "kernel args : ~a"
                         (string-join (or (assq-ref boot 'extra-kernel-arguments)
                                          '())
                                      " ")))
    (put win 10 2 (format #f "packages    : ~a"
                          (string-join
                           (or (assq-ref (assq-ref a 'software) 'extra-packages) '())
                           " ")))
    (put win 11 2 "Passwords are stored as hashes and are not displayed.")
    (put win 13 2 (tr wizard 'confirm))
    (put win 14 2 "> ")
    (refresh win)
    (let ((answer (string-downcase (or (getnstr win 8) ""))))
      (if (member answer '("y" "yes"))
          (wizard-next wizard)
          (wizard-back wizard)))))

(define (page-install win wizard)
  (put win 3 2 (tr wizard 'installing))
  (refresh win)
  (let ((answers (with-defaults (wizard-answers wizard)))
        (answers-file "/tmp/gradus-answers.scm")
        (root "/mnt/target"))
    (endwin)
    (call-with-output-file answers-file
      (lambda (port)
        (format port ";; written by the gradus installer~%~s~%" answers)))
    (catch #t
      (lambda ()
        (install-answers/alist answers answers-file root)
        (format #t "~a~%  ~a/etc/config.scm~%" (tr wizard 'done) root))
      (lambda (key . args)
        (format (current-error-port) "install failed: ~a ~s~%" key args)))
    0))

(define %pages
  `((language . ,page-language)
    (locale . ,page-locale)
    (source . ,page-source)
    (storage . ,page-storage)
    (boot . ,page-boot)
    (software . ,page-software)
    (network . ,page-network)
    (users . ,page-users)
    (review . ,page-review)
    (install . ,page-install)))

;; ------------------------------------------------------------------ main

(define (run-tui)
  "Run the interactive installer in this terminal."
  (let ((win (initscr)))
    (cbreak!)
    (let loop ((wizard (make-wizard)))
      (cond
       ((wizard-complete? wizard)
        ((cdr (assoc 'install %pages)) win wizard))
       (else
        (frame win wizard)
        (let ((page (cdr (assoc (wizard-step wizard) %pages))))
          (catch #t
            (lambda ()
              (loop (page win wizard)))
            (lambda (key . args)
              (endwin)
              (format (current-error-port) "page error at ~a: ~a ~s~%"
                      (wizard-step wizard) key args)
              1))))))
    0))
