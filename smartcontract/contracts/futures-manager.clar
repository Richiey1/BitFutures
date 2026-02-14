;; Futures Manager with Events

(define-data-var next-future-id uint u1)

(define-map futures uint { 
  trader: principal, 
  asset: (string-ascii 32), 
  price: uint, 
  expiry: uint,
  status: (string-ascii 20)
})

(define-map positions {future-id: uint, trader: principal} uint)

(define-constant ERR_FUTURE_NOT_FOUND (err u500))
(define-constant ERR_FUTURE_EXPIRED (err u501))
(define-constant ERR_NOT_TRADER (err u502))
(define-constant ERR_INVALID_EXPIRY (err u503))
(define-constant ERR_ZERO_PRICE (err u504))
(define-constant ERR_INVALID_AMOUNT (err u505))
(define-constant ERR_POSITION_NOT_FOUND (err u506))
(define-constant ERR_INSUFFICIENT_POSITION (err u507))
(define-constant ERR_FUTURE_NOT_EXPIRED (err u508))
(define-constant ERR_ALREADY_SETTLED (err u509))
(define-constant ERR_ALREADY_CANCELLED (err u510))
(define-constant ERR_ALREADY_EXPIRED (err u511))

(define-public (create-future (asset (string-ascii 32)) (price uint) (expiry uint))
  (let ((future-id (var-get next-future-id)))
    ;; Validations
    (asserts! (> price u0) ERR_ZERO_PRICE)
    (asserts! (> expiry burn-block-height) ERR_INVALID_EXPIRY)
    
    ;; Create future
    (map-set futures future-id { 
      trader: tx-sender, 
      asset: asset, 
      price: price, 
      expiry: expiry,
      status: "active"
    })
    (var-set next-future-id (+ future-id u1))
    
    ;; Log future created event
    (print {
      event: "future-created",
      future-id: future-id,
      trader: tx-sender,
      asset: asset,
      price: price,
      expiry: expiry,
      status: "active",
      block-height: burn-block-height
    })
    
    (ok future-id)
  )
)

(define-public (open-position (future-id uint) (size uint))
  (let ((future (unwrap! (map-get? futures future-id) ERR_FUTURE_NOT_FOUND)))
    ;; Validations
    (asserts! (is-eq (get status future) "active") ERR_FUTURE_EXPIRED)
    (asserts! (> (get expiry future) burn-block-height) ERR_FUTURE_EXPIRED)
    (asserts! (> size u0) ERR_INVALID_AMOUNT)
    
    ;; Update position
    (let ((current-size (default-to u0 (map-get? positions {future-id: future-id, trader: tx-sender}))))
      (map-set positions {future-id: future-id, trader: tx-sender} (+ current-size size))
    )
    
    ;; Log position opened event
    (print {
      event: "position-opened",
      future-id: future-id,
      trader: tx-sender,
      size: size,
      asset: (get asset future),
      price: (get price future),
      block-height: burn-block-height
    })
    
    (ok true)
  )
)

(define-public (close-position (future-id uint) (size uint))
  (let ((future (unwrap! (map-get? futures future-id) ERR_FUTURE_NOT_FOUND))
        (current-size (unwrap! (map-get? positions {future-id: future-id, trader: tx-sender}) ERR_POSITION_NOT_FOUND)))
    ;; Validations
    (asserts! (>= current-size size) ERR_INSUFFICIENT_POSITION)
    (asserts! (> size u0) ERR_INVALID_AMOUNT)
    
    ;; Update position and capture new-size in the same let block
    (let ((new-size (- current-size size)))
      (if (> new-size u0)
        (map-set positions {future-id: future-id, trader: tx-sender} new-size)
        (map-delete positions {future-id: future-id, trader: tx-sender})
      )
      
      ;; Log position closed event - now new-size is in scope
      (print {
        event: "position-closed",
        future-id: future-id,
        trader: tx-sender,
        size: size,
        remaining-size: (if (> new-size u0) new-size u0),
        asset: (get asset future),
        block-height: burn-block-height
      })
    )
    
    (ok true)
  )
)

(define-public (settle-future (future-id uint) (settlement-price uint))
  (let ((future (unwrap! (map-get? futures future-id) ERR_FUTURE_NOT_FOUND)))
    ;; Validations
    (asserts! (is-eq tx-sender (get trader future)) ERR_NOT_TRADER)
    (asserts! (<= (get expiry future) burn-block-height) ERR_FUTURE_NOT_EXPIRED)
    (asserts! (is-eq (get status future) "active") ERR_ALREADY_SETTLED)
    
    ;; Update future status
    (map-set futures future-id (merge future { status: "settled" }))
    
    ;; Log settlement event
    (print {
      event: "future-settled",
      future-id: future-id,
      trader: (get trader future),
      asset: (get asset future),
      original-price: (get price future),
      settlement-price: settlement-price,
      block-height: burn-block-height
    })
    
    (ok true)
  )
)

(define-public (cancel-future (future-id uint))
  (let ((future (unwrap! (map-get? futures future-id) ERR_FUTURE_NOT_FOUND)))
    ;; Validations
    (asserts! (is-eq tx-sender (get trader future)) ERR_NOT_TRADER)
    (asserts! (> (get expiry future) burn-block-height) ERR_FUTURE_EXPIRED)
    (asserts! (is-eq (get status future) "active") ERR_ALREADY_CANCELLED)
    
    ;; Update future status
    (map-set futures future-id (merge future { status: "cancelled" }))
    
    ;; Log future cancelled event
    (print {
      event: "future-cancelled",
      future-id: future-id,
      trader: tx-sender,
      asset: (get asset future),
      price: (get price future),
      expiry: (get expiry future),
      block-height: burn-block-height
    })
    
    (ok true)
  )
)

(define-public (expire-future (future-id uint))
  (let ((future (unwrap! (map-get? futures future-id) ERR_FUTURE_NOT_FOUND)))
    ;; Validations
    (asserts! (<= (get expiry future) burn-block-height) ERR_FUTURE_NOT_EXPIRED)
    (asserts! (is-eq (get status future) "active") ERR_ALREADY_EXPIRED)
    
    ;; Update future status
    (map-set futures future-id (merge future { status: "expired" }))
    
    ;; Log future expired event
    (print {
      event: "future-expired",
      future-id: future-id,
      trader: (get trader future),
      asset: (get asset future),
      price: (get price future),
      expiry: (get expiry future),
      block-height: burn-block-height
    })
    
    (ok true)
  )
)

;; ======================== READ-ONLY FUNCTIONS ========================

(define-read-only (get-future (future-id uint))
  (map-get? futures future-id))

(define-read-only (get-position (future-id uint) (trader principal))
  (map-get? positions {future-id: future-id, trader: trader}))

(define-read-only (get-next-future-id)
  (var-get next-future-id))

(define-read-only (is-future-active (future-id uint))
  (match (map-get? futures future-id)
    future (and (is-eq (get status future) "active") 
                (> (get expiry future) burn-block-height))
    false))

(define-read-only (get-future-status (future-id uint))
  (match (map-get? futures future-id)
    future (ok (get status future))
    (err ERR_FUTURE_NOT_FOUND)))

(define-read-only (get-time-until-expiry (future-id uint))
  (match (map-get? futures future-id)
    future (if (> (get expiry future) burn-block-height)
              (ok (- (get expiry future) burn-block-height))
              (ok u0))
    (err ERR_FUTURE_NOT_FOUND)))

(define-read-only (get-total-positions (future-id uint))
  (ok u0)) ;; Simplified - would need to iterate in real implementation
