;;; gradus/tui.scm — the console front-end.  It drives the same wizard core a
;;; future Web front-end will drive, so the pages stay identical.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus tui)
  #:use-module (ncurses curses)
  #:use-module (gradus answers)
  #:use-module (gradus config)
  #:use-module (gradus install)
  #:use-module (gradus render)
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
  (let* ((rows (getmaxy win))
         (previous (wizard-back wizard))
         (hint (if (eq? (wizard-step previous) (wizard-step wizard))
                   "Esc: first page    Ctrl-C: quit"
                   (format #f "Esc: back to ~a    Ctrl-C: quit"
                           (wizard-step previous)))))
    (put win (- rows 2) 2 hint)
    (put win (- rows 1) 2
         (format #f " ~a: ~a " (tr wizard 'step) (wizard-step wizard))))
  (refresh win))

;; ----------------------------------------------------------------- input


;; ------------------------------------------------------------ back handling
;;
;; Every widget asks to go back through %back-handler.  The innermost container
;; decides what "back" means there: a field cancels its edit, a form keeps its
;; values, and only the page loop moves to the previous page.  New widgets get
;; the right behaviour by calling (request-back!) and nothing else.

;; NB: make-parameter treats a procedure argument as a converter, not as the
;; initial value, so the default is #f and the outermost meaning of "back" is
;; applied by REQUEST-BACK! itself.
(define %back-handler (make-parameter #f))

(define (request-back!)
  "Go back one step: whatever the innermost container says that means."
  (let ((handler (%back-handler)))
    (if handler (handler) (throw 'gradus-back #t))))

(define (call-with-back-handler handler thunk)
  "Run THUNK with HANDLER as the meaning of \"back\" for its widgets."
  (parameterize ((%back-handler handler))
    (thunk)))

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
            ((= k 27) (request-back!))
            ((= k 3) (quit!))
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
            ((= k 27) (request-back!))
            ((= k 3) (quit!))
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
              ((or (member entry '("." ".."))
                   (string-prefix? "loop" entry)
                   (string-prefix? "ram" entry)
                   (string-prefix? "zram" entry)
                   (string-prefix? "sr" entry)
                   (string-prefix? "dm-" entry)
                   (string-prefix? "md" entry))
               (loop found))
              ((not (file-exists? (format #f "/sys/block/~a/size" entry)))
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

(define (replace-at lst i value)
  (append (take lst i) (list value) (drop lst (+ i 1))))

(define (make-field label kind value options)
  (vector label kind value options))
(define (field-label f) (vector-ref f 0))
(define (field-kind f) (vector-ref f 1))
(define (field-value f) (vector-ref f 2))
(define (field-options f) (vector-ref f 3))
(define (field-with-value f v) (make-field (field-label f) (field-kind f) v (field-options f)))

(define (show-value v)
  (cond ((string? v) v) ((symbol? v) (symbol->string v))
        ((eq? v #t) "yes") ((eq? v #f) "no") (else (format #f "~a" v))))

(define (draw-form win title fields selected)
  (clear win)
  (box win (acs-vline) (acs-hline))
  (put win 0 2 (format #f " ~a " title))
  (let loop ((fs fields) (row 4) (i 0))
    (unless (null? fs)
      (let* ((f (car fs))
             (mark (if (= i selected) ">" " "))
             (val (if (eq? (field-kind f) 'action)
                      ""
                      (format #f ": ~a" (show-value (field-value f))))))
        (put win row 2 (format #f "~a ~a~a" mark (field-label f) val)))
      (loop (cdr fs) (+ row 1) (+ i 1))))
  (put win (+ 4 (length fields) 2) 2 "j/k or arrows move   Enter choose   Esc back   Ctrl-C quit")
  (refresh win))

(define %cancelled (list 'cancelled))

(define (edit-field win field)
  "Edit one field.  Menus are the default; text is the exception.

Back inside a field cancels that field: the list closes or the edit is dropped,
and the form keeps whatever it had.  Leaving the page takes another back press,
on the form itself."
  (let ((kind (field-kind field)))
    (call-with-back-handler
     (lambda () %cancelled)
     (lambda ()
       (cond
        ((eq? kind 'menu)
         (clear win)
         (box win (acs-vline) (acs-hline))
         (put win 0 2 (format #f " ~a " (field-label field)))
         (let* ((options (map show-value (field-options field)))
                (current (let loop ((o options) (i 0))
                           (cond ((null? o) 0)
                                 ((equal? (car o) (show-value (field-value field))) i)
                                 (else (loop (cdr o) (+ i 1)))))))
           (let ((picked (choose win 3 (field-label field) options current)))
             (if (integer? picked)
                 (list-ref (field-options field) picked)
                 (field-value field)))))
        ((eq? kind 'text)
         (clear win)
         (box win (acs-vline) (acs-hline))
         (put win 0 2 (format #f " ~a " (field-label field)))
         (put win 3 2 "Type a value; Enter accepts.")
         (let ((typed (read-line* win 5 2 "> " (show-value (field-value field)) #t)))
           (if (string? typed) typed (field-value field))))
        (else (field-value field)))))))

(define (form win title fields)
  "A page made of rows: move with the arrows, Enter picks a value.  Returns the
fields once an `action' row is activated."
  (let loop ((fields fields) (selected 0))
    (draw-form win title fields selected)
    (let ((k (key-code (getch win))))
      (cond ((or (= k KEY_UP) (= k 107))       ; k
             (loop fields (max 0 (- selected 1))))
            ((or (= k KEY_DOWN) (= k 106))     ; j
             (loop fields (min (- (length fields) 1) (+ selected 1))))
            ;; A digit jumps straight to that row: one keystroke is easier to
            ;; get through a serial console than a run of arrows.
            ((and (>= k 49) (<= k 57) (<= (- k 49) (- (length fields) 1)))
             (loop fields (- k 49)))
            ((= k 27) (request-back!))
            ((= k 3) (quit!))
            ;; c: accept the page without walking to its Continue row
            ((and (= k 99)
                  (any (lambda (f) (eq? (field-kind f) 'action)) fields))
             fields)
            ((or (= k 10) (= k 13))
             (let ((f (list-ref fields selected)))
               (if (eq? (field-kind f) 'action)
                   fields
                   (loop (replace-at fields selected
                                    (field-with-value f (edit-field win f)))
                         selected))))
            (else (loop fields selected))))))

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

(define (size-of win label value)
  "A size from a menu, or a typed value when the menu offered `custom'."
  (if (equal? value "custom (type a value)")
      (begin
        (clear win)
        (box win (acs-vline) (acs-hline))
        (put win 2 2 (string-append label " in MiB (0 has the usual meaning):"))
        (let ((line (read-line* win 4 2 "> " "" #t)))
          (or (string->number line) 0)))
      value))

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
  (let* ((disks (%disks))
         (labels (map (lambda (d)
                        (format #f "~a  (~a MiB)~a"
                                (%disk-name d) (%disk-mib d) (%disk-note d)))
                      disks))
         (efi? (eq? (firmware-bootloader) 'grub-efi))
         (fields (list (make-field "Target disk" 'menu
                                   (if (pair? labels) (car labels) "no disk found")
                                   labels)
                       (make-field "Layout" 'menu "standard partitions"
                                   (list "standard partitions" "LVM"))
                       (make-field "Root filesystem" 'menu "ext4"
                                   (list "ext4" "btrfs" "xfs"))
                       (make-field "ESP size (MiB, EFI only)" 'menu 1024
                                   (list 512 1024 2048 "custom (type a value)"))
                       (make-field "Swap size (MiB, 0 = none)" 'menu 0
                                   (list 0 1024 2048 4096 8192 "custom (type a value)"))
                       (make-field "Root size (MiB, 0 = rest of disk)" 'menu 0
                                   (list 0 8192 16384 32768 "custom (type a value)"))
                       (make-field "Encrypt root" 'menu "no" (list "no" "yes (LUKS1)"))
                       (make-field "Continue" 'action #f '())))
         (r (form win "Storage" fields)))
    (let* ((label (field-value (list-ref r 0)))
           (index (or (list-index (lambda (l) (equal? l label)) labels) 0))
           (entry (list-ref disks index))
           (disk (%disk-name entry))
           (total (%disk-mib entry))
           (mode (if (equal? "LVM" (field-value (list-ref r 1))) 'lvm 'simple))
           (fs (field-value (list-ref r 2)))
           (esp (size-of win "ESP size" (field-value (list-ref r 3))))
           (swap (size-of win "Swap size" (field-value (list-ref r 4))))
           (root (size-of win "Root size" (field-value (list-ref r 5))))
           (encrypt (equal? "yes (LUKS1)" (field-value (list-ref r 6)))))
      (clear win)
      (box win (acs-vline) (acs-hline))
      (put win 0 2 " Planned layout ")
      (show-plan win total efi? esp swap root)
      (put win (+ 7 (length (car (layout-rows total efi? esp swap root)))) 2
           (format #f "Filesystem: ~a    Layout: ~a" fs mode))
      (put win (+ 8 (length (car (layout-rows total efi? esp swap root)))) 2
           "Enter accepts    Esc changes the values")
      (refresh win)
      (let ((k (key-code (getch win))))
        (cond ((= k 27) (page-storage win wizard))
              ((= k 3) (quit!))
              (else
               (let ((storage (storage-answers mode disk
                                               #:esp-size esp #:swap-size swap
                                               #:root-size root #:filesystem fs)))
                 (if (not encrypt)
                     (wizard-next (wizard-set wizard 'storage storage))
                     (begin
                       (clear win) (box win (acs-vline) (acs-hline))
                       (put win 2 2 "Passphrase for the encrypted root:")
                       (let ((first (read-line* win 4 2 "> " "" #f)))
                         (put win 6 2 "Again:")
                         (let ((again (read-line* win 8 2 "> " "" #f)))
                           (unless (equal? first again)
                             (error "the two passphrases do not match"))
                           (when (> swap 0)
                             (error "an encrypted install cannot keep a separate swap partition; choose 0"))
                           (when (eq? mode 'lvm)
                             (error "encryption is not implemented for LVM storage yet"))
                           (wizard-next
                            (wizard-set wizard 'storage
                                        (storage-answers
                                         mode disk #:esp-size esp #:swap-size swap
                                         #:root-size root #:filesystem fs
                                         #:encryption
                                         (list (cons 'mode 'luks)
                                               (cons 'name "cryptroot")
                                               (cons 'passphrase first))))))))))))))))

(define %keyboards
  '("us" "gb" "de" "fr" "es" "it" "pt" "nl" "be" "ch" "at" "se" "no" "dk"
    "fi" "is" "pl" "cz" "sk" "hu" "ro" "ru" "ua" "tr" "gr" "il" "br" "ca"
    "dvorak" "colemak"))

(define %timezones
  '("UTC" "Europe/London" "Europe/Dublin" "Europe/Lisbon" "Europe/Madrid"
    "Europe/Paris" "Europe/Brussels" "Europe/Amsterdam" "Europe/Berlin"
    "Europe/Zurich" "Europe/Vienna" "Europe/Prague" "Europe/Warsaw"
    "Europe/Budapest" "Europe/Rome" "Europe/Athens" "Europe/Helsinki"
    "Europe/Stockholm" "Europe/Oslo" "Europe/Copenhagen" "Europe/Kyiv"
    "Europe/Moscow" "Europe/Istanbul" "Asia/Jerusalem" "Asia/Dubai"
    "Asia/Karachi" "Asia/Kolkata" "Asia/Dhaka" "Asia/Bangkok"
    "Asia/Shanghai" "Asia/Hong_Kong" "Asia/Taipei" "Asia/Singapore"
    "Asia/Tokyo" "Asia/Seoul" "Australia/Sydney" "Australia/Perth"
    "Pacific/Auckland" "America/Sao_Paulo" "America/Argentina/Buenos_Aires"
    "America/Santiago" "America/Mexico_City" "America/Los_Angeles"
    "America/Denver" "America/Chicago" "America/New_York" "America/Toronto"
    "Africa/Cairo" "Africa/Lagos" "Africa/Johannesburg" "Africa/Nairobi"))

(define %locales
  '("en_US.utf8" "en_GB.utf8" "de_DE.utf8" "fr_FR.utf8" "es_ES.utf8"
    "it_IT.utf8" "pt_PT.utf8" "pt_BR.utf8" "nl_NL.utf8" "sv_SE.utf8"
    "da_DK.utf8" "fi_FI.utf8" "nb_NO.utf8" "pl_PL.utf8" "cs_CZ.utf8"
    "ru_RU.utf8" "uk_UA.utf8" "tr_TR.utf8" "el_GR.utf8" "he_IL.utf8"
    "ar_SA.utf8" "hi_IN.utf8" "zh_CN.utf8" "zh_TW.utf8" "ja_JP.utf8"
    "ko_KR.utf8"))

(define (page-locale win wizard)
  (let* ((fields (list (make-field "Keyboard layout" 'menu "us" %keyboards)
                       (make-field "Timezone" 'menu "UTC" %timezones)
                       (make-field "Locale" 'menu "en_US.utf8" %locales)
                       (make-field "NTP time sync" 'menu "yes" (list "yes" "no"))
                       (make-field "Continue" 'action #f '())))
         (r (form win "Localisation" fields)))
    (wizard-next
     (wizard-set
      (wizard-set (wizard-set (wizard-set wizard 'keyboard (field-value (list-ref r 0)))
                              'timezone (field-value (list-ref r 1)))
                  'locale (field-value (list-ref r 2)))
      'ntp (equal? "yes" (field-value (list-ref r 3)))))))

(define (page-source win wizard)
  (let loop ((services (list (list (cons 'url "https://mirror.sjtu.edu.cn/guix")
                                   (cons 'kind 'mirror))
                              (list (cons 'url "https://ci.guix.gnu.org")
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
          ;; A server the operator adds goes first: they added it for a reason,
          ;; and the seeded official server already has everything anyway.
          (loop (cons (list (cons 'url url) (cons 'kind 'mirror))
                      services))))
       ((= action 1)
        (if (null? services)
            (loop services)
            (let* ((labels (map (lambda (s) (assq-ref s 'url)) services))
                   (i (choose win row "Remove which server?" labels 0)))
              (loop (append (take services i)
                            (drop services (+ i 1)))))))
       (else
        (frame win wizard)
        (put win 3 2 "HTTP proxy for the installation (empty for none):")
        (let ((proxy (read-line* win 5 2 "> " "" #t)))
          (wizard-next
           (wizard-set
            (wizard-set wizard 'source
                        (list (cons 'substitute-services services)))
            'proxy (if (string-null? proxy)
                       #f
                       ;; The readers expect the contract's association list;
                       ;; a bare string made `assq-ref' die mid-install.
                       (list (cons 'http proxy)
                             (cons 'https proxy)))))))))))

(define (page-boot win wizard)
  (let* ((default-index (if (eq? (firmware-bootloader) 'grub-efi) 1 0))
         (fields (list (make-field "Bootloader" 'menu
                                   (if (= default-index 1) "grub-efi" "grub-bios")
                                   (list "grub-bios" "grub-efi"))
                       (make-field "Menu timeout (s)" 'menu 5 (list 0 3 5 10 30))
                       (make-field "Kernel arguments" 'menu "quiet"
                                   (list "quiet" "none" "console=ttyS0 quiet"))
                       (make-field "Serial console" 'menu "no" (list "no" "yes (ttyS0)"))
                       (make-field "Continue" 'action #f '())))
         (r (form win "Boot loader" fields))
         (bootloader (string->symbol (field-value (list-ref r 0))))
         (timeout (field-value (list-ref r 1)))
         (args (field-value (list-ref r 2)))
         (serial (equal? "yes (ttyS0)" (field-value (list-ref r 3))))
         (arguments (cond ((equal? args "quiet") (list "quiet"))
                          ((equal? args "none") '())
                          (else (string-tokenize args)))))
    (wizard-next
     (wizard-set
      wizard 'boot
      (append (list (cons 'bootloader bootloader)
                    (cons 'timeout timeout)
                    (cons 'extra-kernel-arguments arguments))
              (if serial
                  (list (cons 'terminal-outputs '(console serial))
                        (cons 'terminal-inputs '(serial)))
                  '()))))))

(define %extra-packages
  '("htop" "vim" "git" "tmux" "curl" "rsync" "btrfs-progs" "xfsprogs"))

(define (page-software win wizard)
  (let loop ((selected (or (assq-ref (assq-ref (wizard-answers wizard) 'software)
                                      'extra-packages)
                           '()))
             (cursor 0))
    (clear win)
    (box win (acs-vline) (acs-hline))
    (put win 0 2 " Extra software ")
    (put win 2 2 "Space or Enter marks a package; Continue accepts.")
    (let draw ((items %extra-packages) (row 4) (i 0))
      (unless (null? items)
        (put win row 2 (format #f "~a [~a] ~a"
                               (if (= i cursor) ">" " ")
                               (if (member (car items) selected) "x" " ")
                               (car items)))
        (draw (cdr items) (+ row 1) (+ i 1))))
    (put win (+ 4 (length %extra-packages)) 2
         (format #f "~a Continue"
                 (if (= cursor (length %extra-packages)) ">" " ")))
    (refresh win)
    (let ((k (key-code (getch win))))
      (cond ((= k KEY_UP) (loop selected (max 0 (- cursor 1))))
            ((= k KEY_DOWN)
             (loop selected (min (length %extra-packages) (+ cursor 1))))
            ((= k 27) (request-back!))
            ((= k 3) (quit!))
            ((= k 99)                      ; c: accept
             (wizard-next
              (wizard-set wizard 'software
                          (list (cons 'extra-packages selected)))))
            ((or (= k 10) (= k 13) (= k 32))
             (if (= cursor (length %extra-packages))
                 (wizard-next
                  (wizard-set wizard 'software
                              (list (cons 'extra-packages selected))))
                 (let ((package (list-ref %extra-packages cursor)))
                   (loop (if (member package selected)
                             (delete package selected)
                             (cons package selected))
                         cursor))))
            (else (loop selected cursor))))))

(define (%interfaces)
  "Names of the network interfaces on this machine."
  (let ((dir (opendir "/sys/class/net")))
    (let loop ((found '()))
      (let ((entry (readdir dir)))
        (cond ((eof-object? entry) (closedir dir) (reverse found))
              ((member entry '("." ".." "lo")) (loop found))
              (else (loop (cons entry found))))))))

(define (page-network win wizard)
  (let* ((fields (list (make-field "Host name" 'text "gradus" '())
                       (make-field "Address" 'menu "Automatic (DHCP)"
                                   (list "Automatic (DHCP)" "Static"))
                       (make-field "Continue" 'action #f '())))
         (r (form win "Network" fields))
         (host (field-value (list-ref r 0)))
         (static? (equal? "Static" (field-value (list-ref r 1)))))
    (if (not static?)
        (wizard-next (wizard-set (wizard-set wizard 'host-name host)
                                 'network (list (cons 'management 'dhcp))))
        (let* ((ifs (%interfaces))
               (r2 (form win "Static address"
                         (list (make-field "Interface" 'menu
                                           (if (pair? ifs) (car ifs) "eth0")
                                           (if (pair? ifs) ifs (list "eth0")))
                               (make-field "Address/prefix" 'text "192.168.1.10/24" '())
                               (make-field "Gateway" 'text "192.168.1.1" '())
                               (make-field "DNS" 'text "1.1.1.1" '())
                               (make-field "Continue" 'action #f '())))))
          (wizard-next
           (wizard-set (wizard-set wizard 'host-name host)
                       'network (list (cons 'management 'static)
                                      (cons 'interface (field-value (list-ref r2 0)))
                                      (cons 'address (field-value (list-ref r2 1)))
                                      (cons 'gateway (field-value (list-ref r2 2)))
                                      (cons 'name-servers
                                            (list (field-value (list-ref r2 3)))))))))))

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

(define (wizard-goto wizard step)
  "Jump to STEP, keeping the answers collected so far."
  (list (car wizard) step (caddr wizard)))

(define (page-review win wizard)
  ;; A summary a human can check, with a way back into each page that feeds it.
  (let* ((a (wizard-answers wizard))
         (storage (assq-ref a 'storage))
         (source (assq-ref a 'source))
         (services (assq-ref source 'substitute-services))
         (boot (assq-ref a 'boot))
         (users (assq-ref a 'users))
         (software (assq-ref (assq-ref a 'software) 'extra-packages))
         (rows (list (cons "host name  " (or (assq-ref a 'host-name) "gradus"))
                     (cons "disk       " (format #f "~a (~a)"
                                                 (assq-ref storage 'disk)
                                                 (or (assq-ref storage 'filesystem) "ext4")))
                     (cons "layout     " (format #f "~a, swap ~a MiB"
                                                 (assq-ref storage 'mode)
                                                 (or (assq-ref storage 'swap-size) 0)))
                     (cons "bootloader " (format #f "~a~a"
                                                 (assq-ref boot 'bootloader)
                                                 (if (assq-ref boot 'terminal-outputs)
                                                     " (serial)" "")))
                     (cons "substitutes" (if (pair? services)
                                             (assq-ref (car services) 'url)
                                             "official"))
                     (cons "packages   " (if (pair? software)
                                             (string-join software " ")
                                             "(none)"))
                     (cons "accounts   " (string-join
                                          (map (lambda (u) (assq-ref u 'name)) users)
                                          ", "))
                     (cons "system     " (format #f "~a, ~a, keyboard ~a, NTP ~a"
                                                 (or (assq-ref a 'timezone) "UTC")
                                                 (or (assq-ref a 'locale) "en_US.utf8")
                                                 (or (assq-ref a 'keyboard) "us")
                                                 (if (assq-ref a 'ntp) "on" "off"))))))
    (clear win)
    (box win (acs-vline) (acs-hline))
    (put win 0 2 " Review ")
    (let loop ((items rows) (row 3))
      (unless (null? items)
        (put win row 2 (format #f "~a: ~a" (car (car items)) (cdr (car items))))
        (loop (cdr items) (+ row 1))))
    (let ((choice (choose win (+ 5 (length rows)) "What next?"
                          (list "install"
                                "change localisation"
                                "change storage"
                                "change boot loader"
                                "change software"
                                "change network"
                                "change users")
                          0)))
      (case choice
        ;; the answers schema has no `reviewed' key
        ((0) (wizard-next wizard))
        ((1) (wizard-goto wizard 'locale))
        ((2) (wizard-goto wizard 'storage))
        ((3) (wizard-goto wizard 'boot))
        ((4) (wizard-goto wizard 'software))
        ((5) (wizard-goto wizard 'network))
        (else (wizard-goto wizard 'users))))))

;; Set by run-tui: when true, the final wizard step checks and prints the
;; plan without writing anything (contract §2, validation mode).
(define %dry-run? (make-parameter #f))

(define (page-install win wizard)
  (clear win)
  (box win (acs-vline) (acs-hline))
  (put win 0 2 " Installing ")
  (put win 2 2 "The installer is about to:")
  (put win 4 2 "  [1/4] check the declaration")
  (put win 5 2 "  [2/4] mount the target")
  (put win 6 2 "  [3/4] install the system")
  (put win 7 2 "  [4/4] install the boot loader")
  (put win 9 2 "Press Enter to begin; the log follows on this console.")
  (refresh win)
  (getch win)
  (let ((answers (with-defaults (wizard-answers wizard)))
        (answers-file "/tmp/gradus-answers.scm")
        (root "/mnt/target"))
    (endwin)
    (call-with-output-file answers-file
      (lambda (port)
        (format port ";; written by the gradus installer~%~s~%" answers)))
    (if (%dry-run?)
        ;; Validation mode: every check, the rendered plan, nothing written.
        (begin
          (validate-answers answers)
          (display (plan->string
                    (configuration-plan (render-answers answers))))
          (format #t "~%dry run: nothing was written~%")
          0)
        (begin
          (catch #t
            (lambda ()
              (install-answers/alist answers answers-file root)
              (format #t "~a~%  ~a/etc/config.scm~%" (tr wizard 'done) root))
            (lambda (key . args)
              (format (current-error-port) "install failed: ~a ~s~%" key args)))
          0))))

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

(define (run-tui dry-run?)
  "Run the interactive installer in this terminal.  When DRY-RUN? is true the
wizard runs normally and the final step checks and prints the plan without
writing anything, per contract §2 (validation mode)."
  (parameterize ((%dry-run? dry-run?))
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
     0)))
