;;; gradus/tui.scm — the console front-end.  It drives the same wizard core a
;;; future Web front-end will drive, so the pages stay identical.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus tui)
  #:use-module (ncurses curses)
  #:use-module (gradus answers)
  #:use-module (gradus install)
  #:use-module (gradus utils)
  #:use-module (gradus wizard)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:export (run-tui))

;; The input model follows the guile-ncurses manual: `cbreak!' makes single
;; characters available immediately, and `getnstr' does the line editing,
;; returning when <NL>, <CR> or <EOF> arrives.  Nothing here needs `raw!'.

(define %strings
  (list
   '((title . "Gradus 安装向导") (step . "步骤")
     (lang . "界面语言")
     (source . "安装源") (proxy . "HTTP 代理（可留空）")
     (storage . "存储") (disk . "目标磁盘") (mode . "布局方式")
     (users . "用户") (username . "用户名")
     (review . "确认") (confirm . "开始安装？(y/n)")
     (installing . "正在安装，请勿关机……") (done . "安装完成")
     (choose . "输入序号后回车")
     (simple . "标准分区") (lvm . "LVM"))
   '((title . "Gradus installer") (step . "step")
     (lang . "Interface language")
     (source . "Installation source") (proxy . "HTTP proxy (may be empty)")
     (storage . "Storage") (disk . "Target disk") (mode . "Layout")
     (users . "User") (username . "User name")
     (review . "Review") (confirm . "Start the installation? (y/n)")
     (installing . "Installing; do not power off…")
     (done . "Installation finished")
     (choose . "Type a number and press Enter")
     (simple . "Standard partitions") (lvm . "LVM"))))

(define (tr wizard key)
  "The string for KEY in the language the wizard has chosen."
  (let* ((lang (or (assq-ref (wizard-answers wizard) 'ui-language) 0))
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
  "Draw LABEL with DEFAULT and read a line.  An empty answer means DEFAULT."
  (put win y 2 (format #f "~a [~a]: " label default))
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
    (refresh win)
    (let* ((answer (getnstr win 8))
           (n (and answer (string->number answer))))
      (cond ((and (integer? n) (>= n 1) (<= n (length options))) (- n 1))
            ((string-null? (or answer "")) default-index)
            (else (loop))))))

;; ----------------------------------------------------------------- pages

(define (page-language win wizard)
  ;; No language is chosen yet, so this page is bilingual by design.
  (clear win)
  (box win (acs-vline) (acs-hline))
  (put win 0 2 " Gradus ")
  (put win 2 2 "1 简体中文")
  (put win 3 2 "2 English")
  (put win 5 2 "输入序号后回车 / Type a number and press Enter")
  (refresh win)
  (let* ((answer (getnstr win 8))
         (choice (if (equal? (or answer "") "2") 1 0)))
    (wizard-next (wizard-set wizard 'ui-language choice))))

(define (page-source win wizard)
  (let* ((proxy (ask wizard win 3 (tr wizard 'proxy) ""))
         (w (if (string-null? proxy)
                (wizard-set wizard 'source '())
                (wizard-set wizard 'source
                            (list 'proxy (list 'http proxy
                                               'https proxy
                                               'no-proxy '("10.0.2.100")))))))
    (wizard-next w)))

(define (page-storage win wizard)
  (let* ((mode (ask-number wizard win 3 (tr wizard 'mode)
                           (list (tr wizard 'simple) (tr wizard 'lvm))
                           0))
         (mode-sym (if (zero? mode) 'simple 'lvm))
         (disk (ask wizard win 9 (tr wizard 'disk) "/dev/vda"))
         (w (wizard-set wizard 'storage
                        (append (list 'mode mode-sym 'disk disk)
                                (if (eq? mode-sym 'lvm)
                                    '((volume-group . "vg0")
                                      (volumes ((name . "root")
                                                (size . "100%FREE"))))
                                    '())))))
    (wizard-next w)))

(define (page-users win wizard)
  (let* ((name (ask wizard win 3 (tr wizard 'username) "user"))
         (w (wizard-set wizard 'users
                        (list (list 'name name 'group "users")))))
    (wizard-next w)))

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
