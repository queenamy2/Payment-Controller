;; condition-trait.clar
;; Defines the base trait for payment conditions
(define-trait condition-trait (
    (verify-condition () (response bool uint))
))