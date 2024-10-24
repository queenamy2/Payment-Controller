;; sip-010-trait-ft-standard.clar

(define-trait sip-010-trait
    (
        ;; Transfer from the caller to a new principal
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))

        ;; The human-readable name of the token
        (get-name () (response (string-ascii 32) uint))

        ;; The symbol or "ticker" for this token
        (get-symbol () (response (string-ascii 32) uint))

        ;; The number of decimals used
        (get-decimals () (response uint uint))

        ;; The balance of the passed principal
        (get-balance (principal) (response uint uint))

        ;; The total supply of tokens
        (get-total-supply () (response uint uint))

        ;; Optional URI for token metadata
        (get-token-uri () (response (optional (string-utf8 256)) uint))
    )
)