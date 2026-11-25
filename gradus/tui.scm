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
    (put win (- rows 2) 2 "Esc: back    Ctrl-C: quit")
    (put win (- rows 1) 2
         (format #f " ~a: ~a " (tr wizard 'step) (wizard-step wizard))))
  (refresh win))

;; ----------------------------------------------------------------- input

(define %back 'gradus-back)

(define (quit!)
  "Abandon the installer; the main loop restores the terminal."
  (throw 'gradus-quit #t))

(define (key-code k)
  "guile-ncurses returns a character for ordinary keys and an integer for the
special ones; compare everything as an integer."
  (if (char? k) (char->integer k) k))

(define (mask chars)
  "The echo for a secret: one star per character."
  (make-list (length chars) #\*))

(define (insert-at chars pos ch)
  (append (take chars pos) (list ch) (drop chars pos)))

(define (delete-before chars pos)
  (if (zero? pos) chars (append (take chars (- pos 1)) (drop chars pos))))

(define (delete-at chars pos)
  (if (>= pos (length chars)) chars
      (append (take chars pos) (drop chars (+ pos 1)))))

(define (draw-line win y x prompt chars pos show?)
  "Paint PROMPT and the text, then put the cursor where the editing is."
  (let* ((shown (if show? chars (mask chars)))
         (len (+ x (string-length prompt) (length chars))))
    (put win y x (string-append prompt (list->string shown)))
    (move win y len)
    (clrtoeol win)
    ;; Place the cursor before refreshing, or the operator never sees it move.
    (move win y (+ x (string-length prompt) pos))
    (refresh win)))

(define (read-line* win y x prompt initial show?)
  "Edit a line: arrows and Home/End move the cursor, Backspace and Delete edit,
Enter accepts, Esc goes back a page, Ctrl-C quits, and `q' on an empty line
also quits.  The default is pre-filled so it can be edited rather than retyped."
  (let loop ((chars (string->list (or initial "")))
             (pos (length (string->list (or initial "")))))
    (draw-line win y x prompt chars pos show?)
    (let ((k (key-code (getch win))))
      (cond ((or (= k 10) (= k 13)) (list->string chars))
            ((= k 27) (throw 'gradus-back #t))
            ((= k 3) (quit!))
            ((and (= k 113) (null? chars)) (quit!))
            ((or (= k KEY_BACKSPACE) (= k 127) (= k 8))
             (loop (delete-before chars pos) (max 0 (- pos 1))))
            ((= k KEY_DC) (loop (delete-at chars pos) pos))
            ((= k KEY_LEFT) (loop chars (max 0 (- pos 1))))
            ((= k KEY_RIGHT) (loop chars (min (length chars) (+ pos 1))))
            ((= k KEY_HOME) (loop chars 0))
            ((= k KEY_END) (loop chars (length chars)))
            ((and (integer? k) (>= k 32) (< k 127))
             (loop (insert-at chars pos (integer->char k)) (+ pos 1)))
            (else (loop chars pos))))))

(define (ask wizard win y label default)
  "Ask for one line, pre-filled with DEFAULT."
  (put win y 2 (format #f "~a (~a)" label default))
  (read-line* win (+ y 1) 2 "> " default #t))

(define (choose win y label options default-index)
  "Pick one of OPTIONS with the arrow keys.  Returns the index."
  (let loop ((selected default-index))
    (put win y 2 label)
    (let draw ((items options) (row (+ y 1)) (i 0))
      (unless (null? items)
        (put win row 2 (if (= i selected) "> " "  "))
        (put win row 4 (car items))
        (draw (cdr items) (+ row 1) (+ i 1))))
    (put win (+ y 2 (length options)) 2 "(up/down, Enter; Esc back; q quit)")
    (refresh win)
    (let ((k (key-code (getch win))))
      (cond ((or (= k 10) (= k 13)) selected)
            ((= k 27) (throw 'gradus-back #t))
            ((= k 3) (quit!))
            ((= k 113) (quit!))
            ((or (= k KEY_UP) (= k 107))
             (loop (max 0 (- selected 1))))
            ((or (= k KEY_DOWN) (= k 106))
             (loop (min (- (length options) 1) (+ selected 1))))
            ((and (>= k 49) (<= k 57) (<= (- k 49) (- (length options) 1)))
             (loop (- k 49)))
            (else (loop selected))))))

(define (ask-number wizard win y label options default-index)
  "Pick one of OPTIONS; kept for the pages written before the menu widget."
  (choose win y label options default-index))

(define (back? value)
  "Retained for callers that still test a returned value."
  (eq? value %back))

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
  (put win 7 2 "Press Enter to continue, q to quit.")
  (read-line* win 9 2 "> " "" #t)
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

(define (ask-password wizard win y label)
  "Ask for a secret: the characters are not echoed."
  (put win y 2 label)
  (read-line* win (+ y 1) 2 "> " "" #f))

(define (salt)
  "A crypt(3) salt, so the password never leaves this process in clear."
  (let ((chars "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
    (string-append "$6$"
                   (list->string
                    (map (lambda (ignored)
                           (string-ref chars (random (string-length chars))))
                         (iota 8)))
                   "$")))

(define (%disk-mib entry)
  "Size of ENTRY in MiB."
  (let ((path (format #f "/sys/block/~a/size" entry)))
    (if (file-exists? path)
        (let ((sectors (call-with-input-file path
                         (lambda (port)
                           (or (string->number (string-trim-both (read-line port))) 0)))))
          (quotient (* sectors 512) (* 1024 1024)))
        0)))

(define (%disk-note entry)
  "Say when a disk is in use, rather than hiding it."
  (let ((dev (%disk-name entry)))
    (let ((used (filter (lambda (m) (string-prefix? dev (car m))) (%mounts))))
      (if (pair? used)
          (format #f "   [in use: ~a]" (cdr (car used)))
          ""))))

(define (pick win y label items)
  "Choose one of ITEMS, or type a value of one's own."
  (let* ((options (append items (list "(other - type it)")))
         (n (length options))
         (i (choose win y label options 0)))
    (if (= i (- n 1))
        (begin
          (put win (+ y 3 n) 2 "Value:")
          (read-line* win (+ y 4 n) 2 "> " "" #t))
        (list-ref items i))))

(define (layout-rows total efi? esp swap root)
  "The plan as (name start size) rows, plus the MiB used."
  (let* ((first (if efi? esp 1))
         (rows (if efi? (list (list "ESP" 1 esp)) (list (list "biosboot" 1 1))))
         (pos (+ 1 first))
         (rows (if (> swap 0) (append rows (list (list "swap" pos swap))) rows))
         (pos (+ pos (if (> swap 0) swap 0)))
         (root-size (if (> root 0) root (max 0 (- total pos))))
         (rows (append rows (list (list "root" pos root-size)))))
    (list rows (+ pos root-size))))

(define (show-plan win total efi? esp swap root)
  "Draw the layout table and return the MiB that stay unallocated."
  (let* ((plan (layout-rows total efi? esp swap root))
         (rows (car plan))
         (used (cadr plan)))
    (put win 3 2 "Partition     Start (MiB)   Size (MiB)")
    (let loop ((items rows) (row 4))
      (unless (null? items)
        (let ((entry (car items)))
          (put win row 2 (format #f "~a~a~a~a"
                                 (car entry)
                                 (make-string (max 1 (- 14 (string-length (car entry)))) #\space)
                                 (cadr entry)
                                 (make-string (max 1 (- 13 (string-length (number->string (cadr entry))))) #\space)))
          (put win row 28 (format #f "~a" (caddr entry))))
        (loop (cdr items) (+ row 1))))
    (let ((free (- total used)))
      (put win (+ 5 (length rows)) 2
           (format #f "Unallocated: ~a MiB of ~a MiB" free total))
      free)))

(define (page-storage win wizard)
  (frame win wizard)
  (let* ((disks (%disks))
         (labels (map (lambda (d)
                        (format #f "~a  (~a MiB)~a"
                                (%disk-name d) (%disk-mib d) (%disk-note d)))
                      disks)))
    (if (null? disks)
        (begin (put win 3 2 "No installable disks were found.")
               (put win 5 2 "Attach a disk and press any key to rescan.")
               (getch win)
               (page-storage win wizard))
        (let* ((index (choose win 3 (tr wizard 'disks) labels 0))
               (entry (list-ref disks index))
               (disk (%disk-name entry))
               (total (%disk-mib entry))
               (efi? (eq? (firmware-bootloader) 'grub-efi)))
          (frame win wizard)
          (put win 2 2 (format #f "~a: ~a MiB" disk total))
          (let* ((mode (choose win 4 (tr wizard 'mode)
                               (list (tr wizard 'simple) (tr wizard 'lvm)) 0))
                 (mode-sym (if (zero? mode) 'simple 'lvm)))
            (frame win wizard)
            (put win 2 2 (format #f "~a: ~a MiB   (~a free before partitioning)"
                                 disk total total))
            (let* ((esp (ask wizard win 4 (tr wizard 'esp-size) "1024"))
                   (default-swap (number->string (default-swap-size (ram-mib))))
                   (swap (ask wizard win 7 (tr wizard 'swap-size) default-swap))
                   (root (ask wizard win 10 (tr wizard 'root-size) "0")))
              (frame win wizard)
              (put win 2 2 (format #f "~a: ~a MiB" disk total))
              (let* ((esp-mib (or (string->number esp) 1024))
                     (swap-mib (or (string->number swap) 0))
                     (root-mib (or (string->number root) 0))
                     (free (show-plan win total efi? esp-mib swap-mib root-mib))
                     (choice (choose win (+ 7 (if efi? 3 3)) "Use this layout?"
                                     (list "yes" "change the sizes") 0)))
                (if (= choice 1)
                    (page-storage win wizard)
                    (begin
                      (frame win wizard)
                      (put win 2 2 (format #f "~a: ~a MiB" disk total))
                      (let* ((encrypt (choose win 4 (tr wizard 'encrypt)
                                              (list "no" "yes (LUKS1)") 0)))
                        (if (zero? encrypt)
                            (wizard-next
                             (wizard-set wizard 'storage
                                         (storage-answers mode-sym disk
                                                          #:esp-size esp-mib
                                                          #:swap-size swap-mib
                                                          #:root-size root-mib)))
                            (begin
                              (when (> swap-mib 0)
                                (error "an encrypted install cannot keep a separate swap partition; set the swap size to 0"))
                              (when (eq? mode-sym 'lvm)
                                (error "encryption is not implemented for LVM storage yet"))
                              (let ((first (ask-password wizard win 4 (tr wizard 'passphrase)))
                                    (again (ask-password wizard win 6 (tr wizard 'passphrase-again))))
                                (unless (equal? first again)
                                  (error "the two passphrases do not match"))
                                (wizard-next
                                 (wizard-set wizard 'storage
                                             (storage-answers mode-sym disk
                                                              #:esp-size esp-mib
                                                              #:swap-size swap-mib
                                                              #:root-size root-mib
                                                              #:encryption
                                                              (list (cons 'mode 'luks)
                                                                    (cons 'name "cryptroot")
                                                                    (cons 'passphrase first))))))))))))))))))

(define %keyboards
  '("us" "gb" "de" "fr" "es" "it" "se" "dvorak"))

(define %timezones
  '("UTC" "Europe/Berlin" "Europe/London" "Asia/Shanghai" "Asia/Tokyo"
    "America/New_York" "America/Los_Angeles"))

(define %locales
  '("en_US.utf8" "de_DE.utf8" "fr_FR.utf8" "zh_CN.utf8" "ja_JP.utf8"))

(define (page-locale win wizard)
  (frame win wizard)
  (let ((keyboard (pick win 3 (tr wizard 'keyboard) %keyboards)))
    (frame win wizard)
    (let ((timezone (pick win 3 (tr wizard 'timezone) %timezones)))
      (frame win wizard)
      (let ((locale (pick win 3 (tr wizard 'locale) %locales)))
        (frame win wizard)
        (let ((ntp (choose win 3 (tr wizard 'ntp) (list "yes" "no") 0)))
          (wizard-next
           (wizard-set
            (wizard-set (wizard-set (wizard-set wizard 'keyboard keyboard)
                                    'timezone timezone)
                        'locale locale)
            'ntp (zero? ntp))))))))

(define (page-source win wizard)
  (let loop ((services (list (list (cons 'url "https://ci.guix.gnu.org")
                                  (cons 'kind 'official)))))
    (frame win wizard)
    (put win 2 2 "Substitute servers, tried in this order:")
    (let draw ((items services) (row 4) (n 1))
      (unless (null? items)
        (put win row 4 (format #f "~a) ~a" n (assq-ref (car items) 'url)))
        (draw (cdr items) (+ row 1) (+ n 1))))
    (let* ((row (+ 5 (length services)))
           (action (choose win row "What next?"
                           (list "add a server" "remove a server" "continue")
                           2)))
      (cond
       ((= action 0)
        (frame win wizard)
        (put win 3 2 "Server URL (a mirror, or a guix publish instance):")
        (let ((url (read-line* win 5 2 "> " "https://" #t)))
          (loop (append services
                        (list (list (cons 'url url) (cons 'kind 'mirror)))))))
       ((= action 1)
        (if (null? services)
            (loop services)
            (let* ((labels (map (lambda (s) (assq-ref s 'url)) services))
                   (i (choose win row "Remove which server?" labels 0)))
              (loop (append (take services i) (drop services (+ i 1)))))))
       (else
        (frame win wizard)
        (put win 3 2 "HTTP proxy for the installation (empty for none):")
        (let ((proxy (read-line* win 5 2 "> " "" #t)))
          (wizard-next
           (wizard-set (wizard-set wizard 'source
                                   (list (cons 'substitute-services services)))
                       'proxy (if (string-null? proxy) #f proxy)))))))))

(define (page-boot win wizard)
  (frame win wizard)
  (let* ((default-index (if (eq? (firmware-bootloader) 'grub-efi) 1 0))
         (choice (choose win 3 (tr wizard 'bootloader)
                         (list "grub-bios" "grub-efi") default-index)))
    (frame win wizard)
    (let ((wait (ask wizard win 3 (tr wizard 'timeout) "5")))
      (frame win wizard)
      (put win 2 2 "Extra kernel arguments")
      (put win 3 2 "Most machines need none; serial consoles need console=ttyS0.")
      (let ((args-choice (choose win 5 "Kernel arguments"
                                 (list "keep the default (quiet)"
                                       "none"
                                       "edit the list") 0)))
        (let ((arguments
               (cond ((= args-choice 0) (list "quiet"))
                     ((= args-choice 1) '())
                     (else
                      (frame win wizard)
                      (put win 3 2 "Space separated, e.g. console=ttyS0 quiet")
                      (let ((line (read-line* win 5 2 "> " "quiet" #t)))
                        (string-tokenize line))))))
          (frame win wizard)
          (put win 3 2 "Serial console for this machine?")
          (put win 4 2 "Needed when there is no monitor, and to unlock an")
          (put win 5 2 "encrypted disk without one.")
          (let ((serial (choose win 7 "Serial console"
                                (list "no" "yes (ttyS0, 115200)") 0)))
            (wizard-next
             (wizard-set
              (wizard-set
               (wizard-set
                (wizard-set wizard 'boot
                            (append (list (cons 'bootloader
                                                (if (zero? choice) 'grub-bios 'grub-efi))
                                          (cons 'timeout (or (string->number wait) 5)))
                                    (cons 'extra-kernel-arguments arguments)
                                    (if (zero? serial)
                                        '()
                                        (list (cons 'terminal-outputs '(console serial))
                                              (cons 'terminal-inputs '(serial))))))
                'bootloader (if (zero? choice) 'grub-bios 'grub-efi)))))))))))

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
    ;; raw mode, not cbreak: cbreak leaves ISIG on, so ^C would signal the
    ;; process instead of reaching us as a key, and the installer has to shut
    ;; the terminal down cleanly itself.
    (raw!)
    ;; Without keypad mode the arrows arrive as the raw ESC [ A sequences,
    ;; and the leading ESC looks exactly like the "go back" key.
    (keypad! win #t)
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
              (cond
               ((eq? key 'gradus-back) (loop (wizard-back wizard)))
               ((eq? key 'gradus-quit)
                (endwin)
                (format (current-error-port) "Aborted; nothing was changed.~%")
                130)
               (else
                (endwin)
                (format (current-error-port) "page error at ~a: ~a ~s~%"
                        (wizard-step wizard) key args)
                1))))))))
    0))
