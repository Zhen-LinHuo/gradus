;;; gradus/selection.scm — the selection models.
;;; Copyright © 2026 Zhen-Lin Huo <zhen-lin.huo@gmx.com>
;;;
;;; This file is part of Gradus.

(define-module (gradus selection)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (selection-substitute-services
            selection-substitute-urls
            selection-signing-keys
            selection-proxy-environment
            selection-kernel-arguments))

;; Substitutes: an ordered list, preference order.  The first reachable
;; server wins, and adding a server in the front-end places it first, so the
;; order in the answers is the order the daemon is told about.

(define (selection-substitute-services answers)
  "The substitute services declared in ANSWERS, in preference order."
  (or (assq-ref (assq-ref answers 'source) 'substitute-services) '()))

(define (selection-substitute-urls answers)
  "The substitute URLs from ANSWERS, in preference order."
  (filter-map (lambda (service) (assq-ref service 'url))
              (selection-substitute-services answers)))

(define (selection-signing-keys answers)
  "The signing-key file paths the answers name, in order.  A mirror of
official store paths needs none; an independent builder does."
  (filter-map (lambda (service) (assq-ref service 'key))
              (selection-substitute-services answers)))

;; Proxy: one canonical shape — an alist of environment names to values,
;; with absent variables omitted.  The Guix daemon honours http_proxy,
;; https_proxy and no_proxy, and a local cache must be reachable directly,
;; hence the explicit no_proxy list.  Consumers turn the alist into their own
;; presentation: setenv pairs for the installer process, "NAME=value" strings
;; for the declaration's environment field.

(define (selection-proxy-environment answers)
  "The proxy from ANSWERS as (name . value) pairs, or the empty list."
  (let ((proxy (assq-ref answers 'proxy)))
    (if proxy
        (filter-map
         (lambda (entry)
           (let ((name (car entry)) (value (cdr entry)))
             (and value (cons name value))))
         `(("http_proxy" . ,(assq-ref proxy 'http))
           ("https_proxy" . ,(assq-ref proxy 'https))
           ("no_proxy" . ,(and=> (assq-ref proxy 'no-proxy)
                                 (lambda (hosts) (string-join hosts ","))))))
        '())))

;; Kernel arguments: the preset plus the free list the boot page offers as
;; keep-default / none / edit.

(define (selection-kernel-arguments answers)
  "The kernel arguments from the boot section of ANSWERS, or the empty list."
  (or (assq-ref (assq-ref answers 'boot) 'extra-kernel-arguments) '()))
