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
     (users . "用户") (username . "用户名")
     (review . "确认") (confirm . "开始安装？(y/n)")
     (installing . "正在安装，请勿关机……") (done . "安装完成")
     (choose . "输入序号后回车")
     (simple . "标准分区") (lvm . "LVM"))
   '((title . "Gradus installer") (step . "step")
     (lang . "Interface language")
     (source . "Installation source") (substitute . "Substitute server URL")
     (proxy . "HTTP proxy (may be empty)") (disks . "Disks found")
     (storage . "Storage") (disk . "Target disk") (mode . "Layout")
     (users . "User") (username . "User name")
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

(define (page-source win wizard)
  (let* ((url (ask wizard win 3 (tr wizard 'substitute)
                   "https://ci.guix.gnu.org"))
         (proxy (ask wizard win 6 (tr wizard 'proxy) ""))
         (services (if (string-null? url)
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
                                        (cons 'no-proxy '("10.0.2.100")))))))))
    (wizard-next (wizard-set wizard 'source source))))

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
  "Whole disks a human could install onto.  Loop, ram and device-mapper nodes
are not disks, and a disk that is mounted or holds the running system is
excluded: offering it would only lead to a refused installation."
  (let ((dir (opendir "/sys/block")))
    (let loop ((found '()))
      (let ((entry (readdir dir)))
        (cond ((eof-object? entry)
               (closedir dir)
               (filter (lambda (name)
                         (not (disk-busy? (%disk-name name))))
                       (reverse found)))
              ((or (string-prefix? "loop" entry)
                   (string-prefix? "ram" entry)
                   (string-prefix? "zram" entry)
                   (string-prefix? "sr" entry)
                   (string-prefix? "dm-" entry)
                   (string-prefix? "md" entry))
               (loop found))
              (else (loop (cons entry found))))))))

(define (page-storage win wizard)
  (let* ((disks (%disks))
         (_ (when (null? disks)
              (error "no installable disk was found: every disk is in use or absent")))
         (labels (map (lambda (entry)
                        (format #f "~a  (~,1f GB)" (%disk-name entry)
                                (%disk-size entry)))
                      disks))
         (choice (ask-number wizard win 3 (tr wizard 'disks) labels 0))
         (disk (%disk-name (list-ref disks choice)))
         (mode-row (+ 6 (length labels)))
         (mode (ask-number wizard win mode-row (tr wizard 'mode)
                           (list (tr wizard 'simple) (tr wizard 'lvm))
                           0))
         (mode-sym (if (zero? mode) 'simple 'lvm))
         (w (wizard-set wizard 'storage (storage-answers mode-sym disk))))
    (wizard-next w)))

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
  (let loop ((entries (wizard-answers wizard)) (row 2))
    (unless (null? entries)
      (put win row 2 (format #f "~a = ~s" (car (car entries)) (cdr (car entries))))
      (loop (cdr entries) (+ row 1))))
  (put win 14 2 (tr wizard 'confirm))
  (refresh win)
  (let ((answer (string-downcase (or (getnstr win 8) ""))))
    (if (member answer '("y" "yes"))
        (wizard-next wizard)
        (wizard-back wizard))))

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
    (source . ,page-source)
    (storage . ,page-storage)
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
