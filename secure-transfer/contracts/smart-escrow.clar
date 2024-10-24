;; Conditional Payment Smart Contract
;; Import traits
(use-trait condition-trait .condition-trait.condition-trait)
(use-trait ft-trait .sip-010-trait-ft-standard.sip-010-trait)

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
(define-constant ERR-INVALID-PRINCIPAL (err u11))
(define-constant ERR-INVALID-METADATA-LENGTH (err u12))

;; Data Types and Storage
(define-data-var contract-administrator principal tx-sender)

(define-map payment-records
    {transaction-id: uint}
    {
        payment-initiator: principal,
        payment-beneficiary: principal,
        payment-amount: uint,
        token-contract-address: (optional principal),
        condition-contract: principal,
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

;; Validation Functions
(define-private (validate-principal (address principal))
    (is-some (some address)))

(define-private (validate-metadata (metadata (optional (string-utf8 256))))
    (match metadata
        meta-str (if (< (len meta-str) u256) true false)
        true))

;; Private Functions
(define-private (verify-payment-conditions (condition-contract <condition-trait>))
    (match (as-contract 
            (contract-call? condition-contract verify-condition))
           success true 
           error false)
)

(define-private (increment-user-transaction-count (user-address principal))
    (let ((current-count (default-to u0 (map-get? user-transaction-counter user-address))))
        (map-set user-transaction-counter user-address (+ current-count u1))
        (+ current-count u1)
    )
)

(define-private (update-user-transaction-history (user-address principal) (transaction-id uint))
    (let ((existing-txs (default-to (list) (map-get? user-transaction-history user-address))))
        (map-set user-transaction-history 
            user-address 
            (unwrap-panic (as-max-len? (append existing-txs transaction-id) u50))
        )
    )
)

(define-private (execute-token-transfer 
    (token-contract <ft-trait>) 
    (transfer-amount uint) 
    (sender-address principal) 
    (recipient-address principal))
    (contract-call? token-contract transfer transfer-amount sender-address recipient-address none)
)

;; Administrative Functions
(define-public (transfer-contract-ownership (new-administrator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-administrator)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (validate-principal new-administrator) ERR-INVALID-PRINCIPAL)
        (var-set contract-administrator new-administrator)
        (ok true)
    )
)

(define-public (register-escrow-agent (agent-address principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-administrator)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (validate-principal agent-address) ERR-INVALID-PRINCIPAL)
        (map-set registered-escrow-agents agent-address true)
        (ok true)
    )
)

;; Core Payment Functions
(define-public (create-conditional-payment 
    (recipient-address principal) 
    (payment-amount uint) 
    (token-contract (optional <ft-trait>))
    (condition-contract <condition-trait>)
    (expiration-block-height uint)
    (escrow-agent-address (optional principal))
    (requires-confirmation bool)
    (payment-metadata (optional (string-utf8 256)))
)
    (let (
        (transaction-id (increment-user-transaction-count tx-sender))
        (token-principal (match token-contract
                          ft-token (some (contract-of ft-token))
                          none))
    )
        (begin
            ;; Input validation
            (asserts! (validate-principal recipient-address) ERR-INVALID-PRINCIPAL)
            (asserts! (> payment-amount u0) ERR-INVALID-PAYMENT-AMOUNT)
            (asserts! (> expiration-block-height block-height) ERR-PAYMENT-EXPIRED)
            (asserts! (validate-metadata payment-metadata) ERR-INVALID-METADATA-LENGTH)

            ;; Escrow validation
            (match escrow-agent-address 
                agent-address (begin
                    (asserts! (validate-principal agent-address) ERR-INVALID-PRINCIPAL)
                    (asserts! (default-to false (map-get? registered-escrow-agents agent-address)) 
                             ERR-INVALID-ESCROW-AGENT))
                true)

            ;; Handle token transfer
            (match token-contract
                ft-token (try! (execute-token-transfer ft-token 
                                                  payment-amount 
                                                  tx-sender 
                                                  (as-contract tx-sender)))
                (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender))))

            ;; Create payment record
            (map-set payment-records 
                {transaction-id: transaction-id}
                {
                    payment-initiator: tx-sender,
                    payment-beneficiary: recipient-address,
                    payment-amount: payment-amount,
                    token-contract-address: token-principal,
                    condition-contract: (contract-of condition-contract),
                    payment-expiration-block: expiration-block-height,
                    payment-status-claimed: false,
                    designated-escrow-agent: escrow-agent-address,
                    confirmation-required: requires-confirmation,
                    transaction-metadata: payment-metadata
                })

            ;; Transaction histories
            (update-user-transaction-history tx-sender transaction-id)
            (update-user-transaction-history recipient-address transaction-id)

            (ok transaction-id)
        )
    )
)

(define-public (claim-conditional-payment 
    (transaction-id uint) 
    (condition-contract <condition-trait>)
    (token-contract (optional <ft-trait>)))
    (let (
        (payment-record (unwrap! (map-get? payment-records {transaction-id: transaction-id}) 
                                ERR-PAYMENT-RECORD-NOT-FOUND))
    )
        (begin
            ;; Verify authorization and conditions
            (asserts! (is-eq tx-sender (get payment-beneficiary payment-record)) 
                     ERR-UNAUTHORIZED-ACCESS)
            (asserts! (not (get payment-status-claimed payment-record)) 
                     ERR-PAYMENT-ALREADY-CLAIMED)
            (asserts! (<= block-height (get payment-expiration-block payment-record)) 
                     ERR-PAYMENT-EXPIRED)
            (asserts! (is-eq (contract-of condition-contract) (get condition-contract payment-record)) 
                     ERR-UNAUTHORIZED-ACCESS)

            ;; Check payment conditions
            (asserts! (verify-payment-conditions condition-contract) 
                     ERR-PAYMENT-CONDITIONS-NOT-MET)

            ;; Check confirmations if required
            (if (get confirmation-required payment-record)
                (asserts! (default-to false (map-get? payment-confirmation-status 
                    {transaction-id: transaction-id, confirming-party: (get payment-initiator payment-record)})) 
                    ERR-PAYMENT-CONDITIONS-NOT-MET)
                true)

            ;; Payment status
            (map-set payment-records 
                {transaction-id: transaction-id}
                (merge payment-record {payment-status-claimed: true}))

            ;; Execute payment transfer
            (match (get token-contract-address payment-record)
                stored-token-principal 
                    (match token-contract
                        provided-token (if (is-eq stored-token-principal (contract-of provided-token))
                                (as-contract 
                                    (execute-token-transfer 
                                        provided-token
                                        (get payment-amount payment-record) 
                                        tx-sender 
                                        (get payment-beneficiary payment-record)))
                                ERR-INVALID-TOKEN-CONTRACT)
                        ERR-INVALID-TOKEN-CONTRACT)
                (as-contract 
                    (stx-transfer? 
                        (get payment-amount payment-record)
                        tx-sender 
                        (get payment-beneficiary payment-record))))
        )
    )
)

;; Batch Processing Functions
(define-private (zip-payment-info 
    (recipient principal) 
    (amount uint))
    {recipient: recipient, amount: amount}
)

(define-private (process-batch-payment
    (payment-info {recipient: principal, amount: uint})
    (state {condition-contract: <condition-trait>, accumulated-ids: (list 20 uint)}))
    (match (create-conditional-payment 
        (get recipient payment-info)
        (get amount payment-info)
        none 
        (get condition-contract state)
        (+ block-height u1000) 
        none 
        false 
        none)
        transaction-id (merge state 
            {accumulated-ids: (unwrap-panic (as-max-len? 
                (append (get accumulated-ids state) transaction-id) u20))})
        error-code state
    )
)

(define-public (create-multiple-payments 
    (recipient-addresses (list 20 principal)) 
    (payment-amounts (list 20 uint))
    (condition-contract <condition-trait>))
    (let (
        (payment-pairs (map zip-payment-info recipient-addresses payment-amounts))
        (initial-state {
            condition-contract: condition-contract,
            accumulated-ids: (list)
        })
    )
        (ok (get accumulated-ids 
            (fold process-batch-payment 
                  payment-pairs
                  initial-state)))
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

(define-read-only (get-escrow-agent-status (agent-address principal))
    (default-to false (map-get? registered-escrow-agents agent-address))
)

(define-read-only (get-administrator)
    (var-get contract-administrator)
)