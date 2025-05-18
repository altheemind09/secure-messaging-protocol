;; SECURE-MESSAGING-PROTOCOL - STAGE 3

;; Full implementation of a decentralized blockchain messaging system
;; with comprehensive user management, message handling, and system maintenance.

;; Status codes
(define-constant STATUS-PARTICIPANT-UNREGISTERED u200)
(define-constant STATUS-PARTICIPANT-EXISTS u201)
(define-constant STATUS-ACCESS-DENIED u202)
(define-constant STATUS-COMMUNICATION-NOT-FOUND u203)
(define-constant STATUS-CONTENT-LIMIT-EXCEEDED u204)
(define-constant STATUS-CRYPTO-KEY-INVALID u205)
(define-constant STATUS-PROCESS-FAILURE u206)
(define-constant STATUS-CONNECTION-NOT-FOUND u207)
(define-constant STATUS-CONNECTION-EXISTS u208)
(define-constant STATUS-SELF-CONNECTION-PROHIBITED u209)
(define-constant STATUS-COMMUNICATION-EXPIRED u210)
(define-constant STATUS-QUOTA-EXCEEDED u211)

;; System parameters
(define-constant CONTENT-SIZE-LIMIT u1024)
(define-constant CRYPTO-KEY-LENGTH u33)
(define-constant CONNECTION-LIMIT u100)
(define-constant DEFAULT-EXPIRATION-PERIOD u1440) ;; ~10 days (10 min blocks)

;; GLOBAL STATE

;; Protocol governance
(define-data-var protocol-governor principal tx-sender)

;; Network statistics
(define-data-var communication-counter uint u0)
(define-data-var participant-counter uint u0)

;; DATA STRUCTURES

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
    validity-block-limit: uint,
    category: (string-utf8 20)  ;; "normal", "private", etc.
  }
)

;; Pending communications tracker per participant
(define-map participant-pending-items principal (list 50 uint))

;; Authorized connections for each participant
(define-map participant-network principal (list CONNECTION-LIMIT principal))

;; QUERY FUNCTIONS

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

;; Retrieve pending communications for participant
(define-read-only (fetch-participant-pending (address principal))
  (default-to (list) (map-get? participant-pending-items address))
)

;; Get total communications in system
(define-read-only (fetch-communication-volume)
  (var-get communication-counter)
)

;; Get participant connections
(define-read-only (fetch-participant-connections (address principal))
  (default-to (list) (map-get? participant-network address))
)


;; Check if communication has expired
(define-read-only (is-communication-valid (item-id uint))
  (let (
    (communication-data (unwrap! (fetch-communication item-id) false))
    (current-height (unwrap-panic (get-block-info? height u0)))
  )
    (< current-height (get validity-block-limit communication-data))
  )
)

;; PUBLIC FUNCTIONS - PARTICIPANT MANAGEMENT

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
    
    ;; Initialize empty pending items
    (map-set participant-pending-items caller (list))
    
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

;; PUBLIC FUNCTIONS - COMMUNICATIONS

;; Send secure communication to another participant
(define-public (transmit-secure-content (recipient principal) 
                                      (encrypted-payload (buff 1024))
                                      (content-category (string-utf8 20))
                                      (validity-period uint))
  (let (
    (sender tx-sender)
    (sender-profile (fetch-participant-data sender))
    (recipient-profile (fetch-participant-data recipient))
    (message-identifier (var-get communication-counter))
    (current-time (unwrap-panic (get-block-info? time u0)))
    (current-height (unwrap-panic (get-block-info? height u0)))
    (expiration-height (if (> validity-period u0) 
                       (+ current-height validity-period)
                       (+ current-height DEFAULT-EXPIRATION-PERIOD)))
    (recipient-pending (fetch-participant-pending recipient))
  )
    ;; Validate both participants are registered
    (asserts! (get verified sender-profile) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    (asserts! (get verified recipient-profile) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    
    ;; Verify connection is established
    (asserts! (is-valid-connection sender recipient)
              (err STATUS-ACCESS-DENIED))
    
    ;; Store the communication
    (map-set communication-store message-identifier
      {
        origin: sender,
        destination: recipient,
        secure-content: encrypted-payload,
        creation-timestamp: current-time,
        confirmed: false,
        confirmation-timestamp: none,
        validity-block-limit: expiration-height,
        category: content-category
      }
    )
    
    ;; Update recipient's pending items
    (map-set participant-pending-items 
             recipient
             (append recipient-pending message-identifier))
    
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
    (current-height (unwrap-panic (get-block-info? height u0)))
    (pending-items (fetch-participant-pending caller))
  )
    ;; Verify caller is intended recipient
    (asserts! (is-eq (get destination communication-data) caller) 
              (err STATUS-ACCESS-DENIED))
    
    ;; Check validity
    (asserts! (< current-height (get validity-block-limit communication-data))
              (err STATUS-COMMUNICATION-EXPIRED))
    
    ;; Update confirmation status
    (map-set communication-store item-id
      (merge communication-data { 
        confirmed: true,
        confirmation-timestamp: (some current-time)
      })
    )
    
    ;; Remove from pending items
    (map-set participant-pending-items 
             caller 
             (filter non-matching-item pending-items))
    
    ;; Update activity timestamp
    (map-set participant-registry caller
      (merge (fetch-participant-data caller) { 
        last-interaction: current-time
      })
    )
    
    (ok true)
  )
)

;; Helper function for filtering items
(define-private (non-matching-item (id uint))
  (not (is-eq id item-id))
)

;; Remove communication
(define-public (remove-communication (item-id uint))
  (let (
    (caller tx-sender)
    (communication-data (unwrap! (fetch-communication item-id) 
                          (err STATUS-COMMUNICATION-NOT-FOUND)))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Verify caller is sender or recipient
    (asserts! (or 
               (is-eq (get origin communication-data) caller)
               (is-eq (get destination communication-data) caller))
             (err STATUS-ACCESS-DENIED))
    
    ;; If recipient is removing, update pending items if needed
    (if (and 
         (is-eq (get destination communication-data) caller)
         (not (get confirmed communication-data)))
        (map-set participant-pending-items 
                 caller 
                 (filter non-matching-item 
                         (fetch-participant-pending caller)))
        true)
    
    ;; Remove the communication
    (map-delete communication-store item-id)
    
    ;; Update activity timestamp
    (map-set participant-registry caller
      (merge (fetch-participant-data caller) { 
        last-interaction: current-time
      })
    )
    
    (ok true)
  )
)

;; CONNECTION MANAGEMENT

;; Establish new connection
(define-public (create-connection (target-participant principal))
  (let (
    (caller tx-sender)
    (caller-profile (fetch-participant-data caller))
    (target-profile (fetch-participant-data target-participant))
    (current-connections (fetch-participant-connections caller))
  )
    ;; Verify both participants are registered
    (asserts! (get verified caller-profile) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    (asserts! (get verified target-profile) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    
    ;; Cannot connect to self
    (asserts! (not (is-eq caller target-participant))
              (err STATUS-SELF-CONNECTION-PROHIBITED))
    
    ;; Check if connection already exists
    (asserts! (not (is-valid-connection caller target-participant))
              (err STATUS-CONNECTION-EXISTS))
    
    ;; Check connection limit
    (asserts! (< (len current-connections) CONNECTION-LIMIT)
              (err STATUS-QUOTA-EXCEEDED))
    
    ;; Add connection
    (map-set participant-network 
             caller 
             (append current-connections target-participant))
    
    (ok true)
  )
)

;; Remove connection
(define-public (remove-connection (target-participant principal))
  (let (
    (caller tx-sender)
    (current-connections (fetch-participant-connections caller))
  )
    ;; Check if connection exists
    (asserts! (is-valid-connection caller target-participant)
              (err STATUS-CONNECTION-NOT-FOUND))
    
    ;; Remove connection
    (map-set participant-network 
             caller 
             (filter non-matching-connection current-connections))
    
    (ok true)
  )
)

;; Helper function for filtering connections
(define-private (non-matching-connection (address principal))
  (not (is-eq address target-participant))
)

;; MAINTENANCE FUNCTIONS

;; Clear expired communications
(define-public (process-expired-communications)
  (let (
    (caller tx-sender)
    (pending-items (fetch-participant-pending caller))
    (current-height (unwrap-panic (get-block-info? height u0)))
    (valid-pending-items (filter is-item-valid pending-items))
  )
    ;; Update pending items list with only valid communications
    (map-set participant-pending-items caller valid-pending-items)
    
    ;; Update last activity timestamp
    (map-set participant-registry caller
      (merge (fetch-participant-data caller) { 
        last-interaction: (unwrap-panic (get-block-info? time u0))
      })
    )
    
    (ok true)
  )
)

;; Helper function to check if an item is valid (not expired)
(define-private (is-item-valid (item-id uint))
  (let (
    (item-data (unwrap! (fetch-communication item-id) false))
    (current-height (unwrap-panic (get-block-info? height u0)))
  )
    (if (and
         item-data
         (< current-height (get validity-block-limit item-data)))
        true
        false)
  )
)

;; Bulk process communications for maintenance
(define-public (bulk-process-communications (item-ids (list 20 uint)))
  (let (
    (caller tx-sender)
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Verify caller is registered
    (asserts! (is-participant-verified caller) 
              (err STATUS-PARTICIPANT-UNREGISTERED))
    
    ;; Process each communication (simplified implementation)
    ;; Would normally iterate through and process each item
    
    ;; Update last activity timestamp
    (map-set participant-registry caller
      (merge (fetch-participant-data caller) { 
        last-interaction: current-time
      })
    )
    
    (ok true)
  )
)

;; GOVERNANCE FUNCTIONS

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

;; Update protocol parameters
(define-public (update-protocol-settings (new-expiry-period uint))
  (begin
    ;; Only governor can update settings
    (asserts! (is-eq tx-sender (var-get protocol-governor)) 
              (err STATUS-ACCESS-DENIED))
    
    ;; Would update settings here if we had mutable protocol settings
    ;; This is just a placeholder for potential future upgrades
    
    (ok true)
  )
)