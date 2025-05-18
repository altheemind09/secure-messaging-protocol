;; ===========================================================================
;; SECURE-MESSAGING-PROTOCOL - STAGE 1: CORE FUNCTIONALITY
;; ===========================================================================
;; Initial implementation of a decentralized blockchain messaging system
;; with basic user registration and message exchange capabilities.

;; ===========================================================================
;; DEFINITIONS & STATUS CODES
;; ===========================================================================

;; Status codes
(define-constant STATUS-PARTICIPANT-UNREGISTERED u200)
(define-constant STATUS-PARTICIPANT-EXISTS u201)
(define-constant STATUS-ACCESS-DENIED u202)
(define-constant STATUS-COMMUNICATION-NOT-FOUND u203)
(define-constant STATUS-CONTENT-LIMIT-EXCEEDED u204)

;; System parameters
(define-constant CONTENT-SIZE-LIMIT u1024)
(define-constant CRYPTO-KEY-LENGTH u33)
(define-constant DEFAULT-EXPIRATION-PERIOD u1440) ;; ~10 days (10 min blocks)

;; ===========================================================================
;; GLOBAL STATE
;; ===========================================================================

;; Protocol governance
(define-data-var protocol-governor principal tx-sender)

;; Network statistics
(define-data-var communication-counter uint u0)
(define-data-var participant-counter uint u0)

;; ===========================================================================
;; DATA STRUCTURES
;; ===========================================================================

;; Participant identity records
(define-map participant-registry principal 
  {
    verified: bool,
    crypto-public-key: (optional (buff 33)),
    registration-timestamp: uint,
    outbound-count: uint,
    inbound-count: uint,
    last-interaction: uint
  }
)

;; Communication storage
(define-map communication-store uint 
  {
    origin: principal,
    destination: principal,
    secure-content: (buff 1024),
    creation-timestamp: uint,
    confirmed: bool,
    confirmation-timestamp: (optional uint),
    validity-block-limit: uint
  }
)

;; ===========================================================================
;; QUERY FUNCTIONS
;; ===========================================================================

;; Retrieve participant profile data
(define-read-only (fetch-participant-data (address principal))
  (default-to 
    {
      verified: false,
      crypto-public-key: none,
      registration-timestamp: u0,
      outbound-count: u0,
      inbound-count: u0,
      last-interaction: u0
    }
    (map-get? participant-registry address)
  )
)

;; Verify participant registration status
(define-read-only (is-participant-verified (address principal))
  (get verified (fetch-participant-data address))
)

;; Retrieve communication by identifier
(define-read-only (fetch-communication (item-id uint))
  (map-get? communication-store item-id)
)

;; Get protocol metrics
(define-read-only (fetch-protocol-metrics)
  {
    total-communications: (var-get communication-counter),
    active-participants: (var-get participant-counter)
  }
)

;; ===========================================================================
;; PUBLIC FUNCTIONS - PARTICIPANT MANAGEMENT
;; ===========================================================================

;; Register new participant with cryptographic key
(define-public (register-participant (crypto-key (buff 33)))
  (let (
    (caller tx-sender)
    (current-profile (fetch-participant-data caller))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Ensure participant isn't already registered
    (asserts! (not (get verified current-profile)) 
              (err STATUS-PARTICIPANT-EXISTS))
    
    ;; Create participant profile
    (map-set participant-registry caller
      {
        verified: true,
        crypto-public-key: (some crypto-key),
        registration-timestamp: current-time,
        outbound-count: u0,
        inbound-count: u0,
        last-interaction: current-time
      }
    )
    
    ;; Update counter
    (var-set participant-counter (+ (var-get participant-counter) u1))
    (ok true)
  )
)

;; Update participant cryptographic key
(define-public (update-crypto-key (new-key (buff 33)))
  (let (
    (caller tx-sender)
    (current-profile (fetch-participant-data caller))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Verify participant is registered
    (asserts! (get verified current-profile) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    
    ;; Update key and activity timestamp
    (map-set participant-registry caller
      (merge current-profile { 
        crypto-public-key: (some new-key),
        last-interaction: current-time
      })
    )
    
    (ok true)
  )
)

;; ===========================================================================
;; PUBLIC FUNCTIONS - COMMUNICATIONS
;; ===========================================================================

;; Send secure communication to another participant
(define-public (transmit-secure-content (recipient principal) 
                                       (encrypted-payload (buff 1024)))
  (let (
    (sender tx-sender)
    (sender-profile (fetch-participant-data sender))
    (recipient-profile (fetch-participant-data recipient))
    (message-identifier (var-get communication-counter))
    (current-time (unwrap-panic (get-block-info? time u0)))
    (current-height (unwrap-panic (get-block-info? height u0)))
    (expiration-height (+ current-height DEFAULT-EXPIRATION-PERIOD))
  )
    ;; Validate both participants are registered
    (asserts! (get verified sender-profile) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    (asserts! (get verified recipient-profile) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    
    ;; Store the communication
    (map-set communication-store message-identifier
      {
        origin: sender,
        destination: recipient,
        secure-content: encrypted-payload,
        creation-timestamp: current-time,
        confirmed: false,
        confirmation-timestamp: none,
        validity-block-limit: expiration-height
      }
    )
    
    ;; Update communication counters
    (map-set participant-registry sender
      (merge sender-profile { 
        outbound-count: (+ (get outbound-count sender-profile) u1),
        last-interaction: current-time
      })
    )
    
    (map-set participant-registry recipient
      (merge recipient-profile { 
        inbound-count: (+ (get inbound-count recipient-profile) u1)
      })
    )
    
    ;; Increment counter
    (var-set communication-counter (+ message-identifier u1))
    
    (ok message-identifier)
  )
)

;; Confirm receipt of communication
(define-public (confirm-receipt (item-id uint))
  (let (
    (caller tx-sender)
    (communication-data (unwrap! (fetch-communication item-id) 
                          (err STATUS-COMMUNICATION-NOT-FOUND)))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Verify caller is intended recipient
    (asserts! (is-eq (get destination communication-data) caller) 
              (err STATUS-ACCESS-DENIED))
    
    ;; Update confirmation status
    (map-set communication-store item-id
      (merge communication-data { 
        confirmed: true,
        confirmation-timestamp: (some current-time)
      })
    )
    
    ;; Update activity timestamp
    (map-set participant-registry caller
      (merge (fetch-participant-data caller) { 
        last-interaction: current-time
      })
    )
    
    (ok true)
  )
)

;; ===========================================================================
;; GOVERNANCE FUNCTIONS
;; ===========================================================================

;; Initialize protocol
(define-public (initialize-protocol)
  (begin
    ;; Only governor can initialize
    (asserts! (is-eq tx-sender (var-get protocol-governor)) 
              (err STATUS-ACCESS-DENIED))
    (ok true)
  )
)

;; Transfer governance
(define-public (transfer-governance (new-governor principal))
  (begin
    ;; Only current governor can transfer
    (asserts! (is-eq tx-sender (var-get protocol-governor)) 
              (err STATUS-ACCESS-DENIED))
    (var-set protocol-governor new-governor)
    (ok true)
  )
)