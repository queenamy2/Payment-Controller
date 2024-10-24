;; Conditional Payment Smart Contract
;; Supports multiple payment types, batch operations, and advanced conditions

;; Error Constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u1))
(define-constant ERR-PAYMENT-RECORD-NOT-FOUND (err u2))
(define-constant ERR-PAYMENT-ALREADY-CLAIMED (err u3))
(define-constant ERR-PAYMENT-CONDITIONS-NOT-MET (err u4))
(define-constant ERR-PAYMENT-EXPIRED (err u5))
(define-constant ERR-INVALID-PAYMENT-AMOUNT (err u6))
(define-constant ERR-INVALID-TOKEN-CONTRACT (err u7))
(define-constant ERR-INVALID-ESCROW-AGENT (err u8))
(define-constant ERR-BATCH-OPERATION-FAILED (err u9))
(define-constant ERR-INSUFFICIENT-TOKEN-BALANCE (err u10))

;; Data Types and Storage
(define-data-var contract-administrator principal tx-sender)

(define-map payment-records
    {transaction-id: uint}
    {
        payment-initiator: principal,
        payment-beneficiary: principal,
        payment-amount: uint,
        token-contract-address: (optional principal),
        condition-contract-address: principal,
        condition-verification-function: (string-ascii 128),
        payment-expiration-block: uint,
        payment-status-claimed: bool,
        designated-escrow-agent: (optional principal),
        confirmation-required: bool,
        transaction-metadata: (optional (string-utf8 256))
    }
)

(define-map user-transaction-counter principal uint)
(define-map payment-confirmation-status {transaction-id: uint, confirming-party: principal} bool)
(define-map user-transaction-history principal (list 50 uint))
(define-map registered-escrow-agents principal bool)

;; Private Function Implementations
(define-private (verify-payment-conditions (payment-verification-data {condition-contract-address: principal, 
                                                                     condition-verification-function: (string-ascii 128)}))
    (contract-call? 
        (unwrap-panic (as-contract (get condition-contract-address payment-verification-data))) 
        (get condition-verification-function payment-verification-data)
    )
)

(define-private (increment-user-transaction-count (user-address principal))
    (let ((current-transaction-count (default-to u0 (map-get? user-transaction-counter user-address))))
        (map-set user-transaction-counter user-address (+ current-transaction-count u1))
        (+ current-transaction-count u1)
    )
)

(define-private (update-user-transaction-history (user-address principal) (transaction-id uint))
    (let ((existing-transactions (default-to (list) (map-get? user-transaction-history user-address))))
        (map-set user-transaction-history 
            user-address 
            (unwrap-panic (as-max-len? (append existing-transactions transaction-id) u50))
        )
    )
)

(define-private (execute-token-transfer (token-contract-address principal) 
                                      (transfer-amount uint) 
                                      (sender-address principal) 
                                      (recipient-address principal))
    (contract-call? token-contract-address transfer transfer-amount sender-address recipient-address)
)

;; Administrative Functions
(define-public (transfer-contract-ownership (new-administrator-address principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-administrator)) ERR-UNAUTHORIZED-ACCESS)
        (var-set contract-administrator new-administrator-address)
        (ok true)
    )
)

(define-public (register-new-escrow-agent (agent-address principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-administrator)) ERR-UNAUTHORIZED-ACCESS)
        (map-set registered-escrow-agents agent-address true)
        (ok true)
    )
)

;; Core Payment Functions
(define-public (create-conditional-payment 
    (recipient-address principal) 
    (payment-amount uint) 
    (token-contract-address (optional principal))
    (condition-contract-address principal) 
    (condition-function-name (string-ascii 128))
    (expiration-block-height uint)
    (escrow-agent-address (optional principal))
    (requires-confirmation bool)
    (payment-metadata (optional (string-utf8 256)))
)
    (let (
        (transaction-id (increment-user-transaction-count tx-sender))
        (selected-token-contract (default-to .STX token-contract-address))
    )
        (asserts! (> payment-amount u0) ERR-INVALID-PAYMENT-AMOUNT)
        (asserts! (> expiration-block-height block-height) ERR-PAYMENT-EXPIRED)
        (match escrow-agent-address agent-address
            (asserts! (default-to false (map-get? registered-escrow-agents agent-address)) ERR-INVALID-ESCROW-AGENT)
            true
        )

        ;; Execute token transfer to contract
        (if (is-some token-contract-address)
            (try! (execute-token-transfer selected-token-contract payment-amount tx-sender (as-contract tx-sender)))
            (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)))
        )

        ;; Create payment transaction record
        (map-set payment-records 
            {transaction-id: transaction-id}
            {
                payment-initiator: tx-sender,
                payment-beneficiary: recipient-address,
                payment-amount: payment-amount,
                token-contract-address: token-contract-address,
                condition-contract-address: condition-contract-address,
                condition-verification-function: condition-function-name,
                payment-expiration-block: expiration-block-height,
                payment-status-claimed: false,
                designated-escrow-agent: escrow-agent-address,
                confirmation-required: requires-confirmation,
                transaction-metadata: payment-metadata
            }
        )

        ;; Update transaction histories
        (update-user-transaction-history tx-sender transaction-id)
        (update-user-transaction-history recipient-address transaction-id)

        (ok transaction-id)
    )
)

(define-public (claim-conditional-payment (transaction-id uint))
    (let (
        (payment-record (unwrap! (map-get? payment-records {transaction-id: transaction-id}) 
                                ERR-PAYMENT-RECORD-NOT-FOUND))
        (current-block-height block-height)
    )
        (asserts! (is-eq tx-sender (get payment-beneficiary payment-record)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (not (get payment-status-claimed payment-record)) ERR-PAYMENT-ALREADY-CLAIMED)
        (asserts! (<= current-block-height (get payment-expiration-block payment-record)) ERR-PAYMENT-EXPIRED)

        ;; Verify conditions and confirmations
        (asserts! (is-ok (verify-payment-conditions {
            condition-contract-address: (get condition-contract-address payment-record),
            condition-verification-function: (get condition-verification-function payment-record)
        })) ERR-PAYMENT-CONDITIONS-NOT-MET)

        (when (get confirmation-required payment-record)
            (asserts! (default-to false (map-get? payment-confirmation-status 
                {transaction-id: transaction-id, confirming-party: (get payment-initiator payment-record)})) 
                ERR-PAYMENT-CONDITIONS-NOT-MET)
        )

        ;; Update payment status
        (map-set payment-records 
            {transaction-id: transaction-id}
            (merge payment-record {payment-status-claimed: true})
        )

        ;; Execute payment transfer
        (match (get token-contract-address payment-record) token-address
            (as-contract (execute-token-transfer token-address 
                                               (get payment-amount payment-record) 
                                               tx-sender 
                                               (get payment-beneficiary payment-record)))
            (as-contract (stx-transfer? (get payment-amount payment-record)
                                      tx-sender 
                                      (get payment-beneficiary payment-record)))
        )
    )
)

(define-public (confirm-transaction (transaction-id uint))
    (let ((payment-record (unwrap! (map-get? payment-records {transaction-id: transaction-id}) 
                                  ERR-PAYMENT-RECORD-NOT-FOUND)))
        (asserts! (or 
            (is-eq tx-sender (get payment-initiator payment-record))
            (is-some (match (get designated-escrow-agent payment-record) agent-address 
                (and (is-eq tx-sender agent-address) true)
                false
            ))
        ) ERR-UNAUTHORIZED-ACCESS)

        (map-set payment-confirmation-status 
                 {transaction-id: transaction-id, confirming-party: tx-sender} 
                 true)
        (ok true)
    )
)

;; Batch Processing Functions
(define-public (create-multiple-payments 
    (recipient-addresses (list 20 principal)) 
    (payment-amounts (list 20 uint)) 
    (condition-contract-address principal) 
    (condition-function-name (string-ascii 128)))
    (let ((transaction-ids (list)))
        (ok (fold process-batch-payment recipient-addresses payment-amounts transaction-ids))
    )
)

(define-private (process-batch-payment 
    (recipient-address principal) 
    (payment-amount uint) 
    (accumulated-ids (list 20 uint)))
    (match (create-conditional-payment 
        recipient-address payment-amount none condition-contract-address condition-function-name 
        (+ block-height u1000) none false none)
        transaction-id (unwrap-panic (as-max-len? (append accumulated-ids transaction-id) u20))
        error-code accumulated-ids
    )
)

;; Query Functions
(define-read-only (get-transaction-details (transaction-id uint))
    (map-get? payment-records {transaction-id: transaction-id})
)

(define-read-only (get-user-transactions (user-address principal))
    (map-get? user-transaction-history user-address)
)

(define-read-only (get-transaction-confirmation-status (transaction-id uint) (confirming-party principal))
    (default-to false (map-get? payment-confirmation-status 
                               {transaction-id: transaction-id, confirming-party: confirming-party}))
)

(define-read-only (verify-escrow-agent-status (agent-address principal))
    (default-to false (map-get? registered-escrow-agents agent-address))
)