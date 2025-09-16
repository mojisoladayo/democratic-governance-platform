;; voting-booth
;; Manages secure ballot creation and voting processes, ensures voter anonymity while preventing double-voting, provides real-time vote tallying, and maintains immutable election records.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_STATE (err u422))
(define-constant ERR_EXPIRED (err u410))
(define-constant ERR_ALREADY_VOTED (err u420))

;; Data Variables
(define-data-var contract-version uint u1)
(define-data-var total-elections uint u0)
(define-data-var total-voters uint u0)
(define-data-var contract-active bool true)

;; Data Maps
(define-map elections
    { election-id: uint }
    {
        title: (string-ascii 100),
        description: (string-ascii 500),
        start-time: uint,
        end-time: uint,
        status: (string-ascii 20),
        total-votes: uint,
        created-by: principal,
        created-at: uint
    }
)

(define-map election-positions
    { election-id: uint, position: (string-ascii 50) }
    {
        candidates: (list 10 (string-ascii 100)),
        total-votes: uint,
        is-active: bool
    }
)

(define-map votes
    { election-id: uint, voter: principal, position: (string-ascii 50) }
    {
        candidate: (string-ascii 100),
        timestamp: uint,
        vote-hash: (buff 32)
    }
)

(define-map registered-voters
    { voter: principal }
    {
        registration-date: uint,
        is-verified: bool,
        elections-voted: uint,
        last-vote: uint
    }
)

(define-map vote-counts
    { election-id: uint, position: (string-ascii 50), candidate: (string-ascii 100) }
    { count: uint }
)

(define-map election-administrators
    { election-id: uint, admin: principal }
    { permissions: (string-ascii 50), granted-at: uint }
)

;; Read-only functions
(define-read-only (get-contract-version)
    (var-get contract-version)
)

(define-read-only (get-total-elections)
    (var-get total-elections)
)

(define-read-only (get-total-voters)
    (var-get total-voters)
)

(define-read-only (is-contract-active)
    (var-get contract-active)
)

(define-read-only (get-election (election-id uint))
    (map-get? elections { election-id: election-id })
)

(define-read-only (get-election-position (election-id uint) (position (string-ascii 50)))
    (map-get? election-positions { election-id: election-id, position: position })
)

(define-read-only (get-vote-count (election-id uint) (position (string-ascii 50)) (candidate (string-ascii 100)))
    (default-to 
        { count: u0 } 
        (map-get? vote-counts { election-id: election-id, position: position, candidate: candidate })
    )
)

(define-read-only (is-voter-registered (voter principal))
    (match (map-get? registered-voters { voter: voter })
        voter-info (get is-verified voter-info)
        false
    )
)

(define-read-only (has-voted (election-id uint) (voter principal) (position (string-ascii 50)))
    (is-some (map-get? votes { election-id: election-id, voter: voter, position: position }))
)

(define-read-only (get-voter-info (voter principal))
    (map-get? registered-voters { voter: voter })
)

(define-read-only (is-election-active (election-id uint))
    (match (map-get? elections { election-id: election-id })
        election-data
        (and 
            (is-eq (get status election-data) "active")
            (>= block-height (get start-time election-data))
            (<= block-height (get end-time election-data))
        )
        false
    )
)

;; Private functions
(define-private (is-authorized (user principal))
    (is-eq user CONTRACT_OWNER)
)

(define-private (increment-election-counter)
    (var-set total-elections (+ (var-get total-elections) u1))
)

(define-private (increment-voter-counter)
    (var-set total-voters (+ (var-get total-voters) u1))
)

(define-private (get-current-time)
    block-height
)

(define-private (validate-time-range (start-time uint) (end-time uint))
    (and (> start-time block-height) (> end-time start-time))
)

(define-private (is-election-admin (election-id uint) (user principal))
    (or 
        (is-authorized user)
        (is-some (map-get? election-administrators { election-id: election-id, admin: user }))
    )
)

;; Administrative functions
(define-public (set-contract-active (active bool))
    (begin
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        (var-set contract-active active)
        (ok true)
    )
)

(define-public (register-voter (voter principal))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-none (map-get? registered-voters { voter: voter })) ERR_ALREADY_EXISTS)
        
        (map-set registered-voters
            { voter: voter }
            {
                registration-date: (get-current-time),
                is-verified: true,
                elections-voted: u0,
                last-vote: u0
            }
        )
        
        (increment-voter-counter)
        (ok true)
    )
)

(define-public (grant-election-admin (election-id uint) (admin principal))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-some (map-get? elections { election-id: election-id })) ERR_NOT_FOUND)
        
        (map-set election-administrators
            { election-id: election-id, admin: admin }
            { permissions: "admin", granted-at: (get-current-time) }
        )
        (ok true)
    )
)

;; Core business functions
(define-public (create-election (title (string-ascii 100)) (description (string-ascii 500)) (start-time uint) (end-time uint))
    (let
        (
            (election-id (var-get total-elections))
            (current-time (get-current-time))
        )
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        (asserts! (validate-time-range start-time end-time) ERR_INVALID_INPUT)
        (asserts! (> (len title) u0) ERR_INVALID_INPUT)
        
        (map-set elections
            { election-id: election-id }
            {
                title: title,
                description: description,
                start-time: start-time,
                end-time: end-time,
                status: "pending",
                total-votes: u0,
                created-by: tx-sender,
                created-at: current-time
            }
        )
        
        (increment-election-counter)
        (ok election-id)
    )
)

(define-public (add-election-position (election-id uint) (position (string-ascii 50)) (candidates (list 10 (string-ascii 100))))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-election-admin election-id tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-some (map-get? elections { election-id: election-id })) ERR_NOT_FOUND)
        (asserts! (> (len candidates) u0) ERR_INVALID_INPUT)
        
        (map-set election-positions
            { election-id: election-id, position: position }
            {
                candidates: candidates,
                total-votes: u0,
                is-active: true
            }
        )
        (ok true)
    )
)

(define-public (start-election (election-id uint))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-election-admin election-id tx-sender) ERR_UNAUTHORIZED)
        
        (match (map-get? elections { election-id: election-id })
            election-data
            (begin
                (asserts! (is-eq (get status election-data) "pending") ERR_INVALID_STATE)
                (asserts! (>= block-height (get start-time election-data)) ERR_INVALID_STATE)
                
                (map-set elections
                    { election-id: election-id }
                    (merge election-data { status: "active" })
                )
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (cast-vote (election-id uint) (position (string-ascii 50)) (candidate (string-ascii 100)))
    (let
        (
            (current-time (get-current-time))
            (vote-hash (keccak256 (concat (concat (unwrap-panic (to-consensus-buff? tx-sender)) (unwrap-panic (to-consensus-buff? candidate))) (unwrap-panic (to-consensus-buff? current-time)))))
        )
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-voter-registered tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-election-active election-id) ERR_INVALID_STATE)
        (asserts! (not (has-voted election-id tx-sender position)) ERR_ALREADY_VOTED)
        
        ;; Verify candidate exists in position
        (match (map-get? election-positions { election-id: election-id, position: position })
            position-data
            (begin
                (asserts! (get is-active position-data) ERR_INVALID_STATE)
                (asserts! (is-some (index-of (get candidates position-data) candidate)) ERR_INVALID_INPUT)
                
                ;; Record the vote
                (map-set votes
                    { election-id: election-id, voter: tx-sender, position: position }
                    {
                        candidate: candidate,
                        timestamp: current-time,
                        vote-hash: vote-hash
                    }
                )
                
                ;; Update vote count
                (match (map-get? vote-counts { election-id: election-id, position: position, candidate: candidate })
                    existing-count
                    (map-set vote-counts
                        { election-id: election-id, position: position, candidate: candidate }
                        { count: (+ (get count existing-count) u1) }
                    )
                    (map-set vote-counts
                        { election-id: election-id, position: position, candidate: candidate }
                        { count: u1 }
                    )
                )
                
                ;; Update election total votes
                (match (map-get? elections { election-id: election-id })
                    election-data
                    (map-set elections
                        { election-id: election-id }
                        (merge election-data { total-votes: (+ (get total-votes election-data) u1) })
                    )
                    false
                )
                
                ;; Update position total votes
                (map-set election-positions
                    { election-id: election-id, position: position }
                    (merge position-data { total-votes: (+ (get total-votes position-data) u1) })
                )
                
                ;; Update voter stats
                (match (map-get? registered-voters { voter: tx-sender })
                    voter-data
                    (map-set registered-voters
                        { voter: tx-sender }
                        (merge voter-data {
                            elections-voted: (+ (get elections-voted voter-data) u1),
                            last-vote: current-time
                        })
                    )
                    false
                )
                
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (finalize-election (election-id uint))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-election-admin election-id tx-sender) ERR_UNAUTHORIZED)
        
        (match (map-get? elections { election-id: election-id })
            election-data
            (begin
                (asserts! (is-eq (get status election-data) "active") ERR_INVALID_STATE)
                (asserts! (>= block-height (get end-time election-data)) ERR_INVALID_STATE)
                
                (map-set elections
                    { election-id: election-id }
                    (merge election-data { status: "finalized" })
                )
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

;; Emergency functions
(define-public (emergency-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-active false)
        (ok true)
    )
)

(define-public (emergency-unpause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-active true)
        (ok true)
    )
)
