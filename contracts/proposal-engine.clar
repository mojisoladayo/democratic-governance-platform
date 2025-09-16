;; proposal-engine
;; Handles proposal submission and review workflows, manages community discussion and amendment processes, tracks voting outcomes, and automates policy implementation based on approved measures.

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
(define-data-var total-proposals uint u0)
(define-data-var contract-active bool true)
(define-data-var minimum-voting-period uint u144) ;; ~1 day in blocks
(define-data-var quorum-threshold uint u1000) ;; Minimum votes needed

;; Data Maps
(define-map proposals
    { proposal-id: uint }
    {
        title: (string-ascii 100),
        description: (string-ascii 1000),
        proposer: principal,
        category: (string-ascii 50),
        voting-start: uint,
        voting-end: uint,
        status: (string-ascii 20),
        implementation-data: (string-ascii 500),
        created-at: uint,
        updated-at: uint
    }
)

(define-map proposal-votes
    { proposal-id: uint, voter: principal }
    {
        vote: bool, ;; true = yes, false = no
        voting-power: uint,
        timestamp: uint,
        comment: (string-ascii 500)
    }
)

(define-map proposal-results
    { proposal-id: uint }
    {
        yes-votes: uint,
        no-votes: uint,
        total-votes: uint,
        total-voting-power: uint,
        participation-rate: uint,
        result: (string-ascii 20)
    }
)

(define-map voting-delegates
    { delegator: principal }
    {
        delegate: principal,
        voting-power: uint,
        delegation-start: uint,
        is-active: bool
    }
)

(define-map proposal-amendments
    { proposal-id: uint, amendment-id: uint }
    {
        amendment-text: (string-ascii 500),
        proposed-by: principal,
        status: (string-ascii 20),
        votes-for: uint,
        votes-against: uint,
        created-at: uint
    }
)

(define-map community-members
    { member: principal }
    {
        voting-power: uint,
        proposals-submitted: uint,
        proposals-voted: uint,
        reputation-score: uint,
        joined-at: uint,
        is-active: bool
    }
)

;; Read-only functions
(define-read-only (get-contract-version)
    (var-get contract-version)
)

(define-read-only (get-total-proposals)
    (var-get total-proposals)
)

(define-read-only (is-contract-active)
    (var-get contract-active)
)

(define-read-only (get-minimum-voting-period)
    (var-get minimum-voting-period)
)

(define-read-only (get-quorum-threshold)
    (var-get quorum-threshold)
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-proposal-result (proposal-id uint))
    (map-get? proposal-results { proposal-id: proposal-id })
)

(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-community-member (member principal))
    (map-get? community-members { member: member })
)

(define-read-only (get-voting-delegate (delegator principal))
    (map-get? voting-delegates { delegator: delegator })
)

(define-read-only (has-voted (proposal-id uint) (voter principal))
    (is-some (map-get? proposal-votes { proposal-id: proposal-id, voter: voter }))
)

(define-read-only (is-proposal-active (proposal-id uint))
    (match (map-get? proposals { proposal-id: proposal-id })
        proposal-data
        (and 
            (is-eq (get status proposal-data) "active")
            (>= block-height (get voting-start proposal-data))
            (<= block-height (get voting-end proposal-data))
        )
        false
    )
)

(define-read-only (calculate-proposal-outcome (proposal-id uint))
    (match (map-get? proposal-results { proposal-id: proposal-id })
        results
        (let
            (
                (total-votes (get total-votes results))
                (yes-votes (get yes-votes results))
                (no-votes (get no-votes results))
            )
            (if (>= total-votes (var-get quorum-threshold))
                (if (> yes-votes no-votes)
                    "passed"
                    "failed"
                )
                "insufficient-quorum"
            )
        )
        "not-found"
    )
)

;; Private functions
(define-private (is-authorized (user principal))
    (is-eq user CONTRACT_OWNER)
)

(define-private (increment-proposal-counter)
    (var-set total-proposals (+ (var-get total-proposals) u1))
)

(define-private (get-current-time)
    block-height
)

(define-private (validate-voting-period (start-time uint) (end-time uint))
    (and 
        (> start-time block-height) 
        (> end-time start-time)
        (>= (- end-time start-time) (var-get minimum-voting-period))
    )
)

(define-private (is-community-member (user principal))
    (match (map-get? community-members { member: user })
        member-data (get is-active member-data)
        false
    )
)

(define-private (get-voting-power (user principal))
    (match (map-get? community-members { member: user })
        member-data 
        (if (get is-active member-data)
            (get voting-power member-data)
            u0
        )
        u0
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

(define-public (set-minimum-voting-period (period uint))
    (begin
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> period u0) ERR_INVALID_INPUT)
        (var-set minimum-voting-period period)
        (ok period)
    )
)

(define-public (set-quorum-threshold (threshold uint))
    (begin
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> threshold u0) ERR_INVALID_INPUT)
        (var-set quorum-threshold threshold)
        (ok threshold)
    )
)

(define-public (register-community-member (member principal) (voting-power uint))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> voting-power u0) ERR_INVALID_INPUT)
        (asserts! (is-none (map-get? community-members { member: member })) ERR_ALREADY_EXISTS)
        
        (map-set community-members
            { member: member }
            {
                voting-power: voting-power,
                proposals-submitted: u0,
                proposals-voted: u0,
                reputation-score: u100,
                joined-at: (get-current-time),
                is-active: true
            }
        )
        (ok true)
    )
)

;; Core business functions
(define-public (submit-proposal (title (string-ascii 100)) (description (string-ascii 1000)) (category (string-ascii 50)) (voting-duration uint) (implementation-data (string-ascii 500)))
    (let
        (
            (proposal-id (var-get total-proposals))
            (current-time (get-current-time))
            (voting-start (+ current-time u144)) ;; Start voting in ~1 day
            (voting-end (+ voting-start voting-duration))
        )
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-community-member tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> (len title) u0) ERR_INVALID_INPUT)
        (asserts! (> (len description) u0) ERR_INVALID_INPUT)
        (asserts! (validate-voting-period voting-start voting-end) ERR_INVALID_INPUT)
        
        (map-set proposals
            { proposal-id: proposal-id }
            {
                title: title,
                description: description,
                proposer: tx-sender,
                category: category,
                voting-start: voting-start,
                voting-end: voting-end,
                status: "pending",
                implementation-data: implementation-data,
                created-at: current-time,
                updated-at: current-time
            }
        )
        
        ;; Initialize proposal results
        (map-set proposal-results
            { proposal-id: proposal-id }
            {
                yes-votes: u0,
                no-votes: u0,
                total-votes: u0,
                total-voting-power: u0,
                participation-rate: u0,
                result: "pending"
            }
        )
        
        ;; Update proposer stats
        (match (map-get? community-members { member: tx-sender })
            member-data
            (map-set community-members
                { member: tx-sender }
                (merge member-data {
                    proposals-submitted: (+ (get proposals-submitted member-data) u1)
                })
            )
            false
        )
        
        (increment-proposal-counter)
        (ok proposal-id)
    )
)

(define-public (start-proposal-voting (proposal-id uint))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        
        (match (map-get? proposals { proposal-id: proposal-id })
            proposal-data
            (begin
                (asserts! (is-eq (get status proposal-data) "pending") ERR_INVALID_STATE)
                (asserts! (>= block-height (get voting-start proposal-data)) ERR_INVALID_STATE)
                
                (map-set proposals
                    { proposal-id: proposal-id }
                    (merge proposal-data {
                        status: "active",
                        updated-at: (get-current-time)
                    })
                )
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool) (comment (string-ascii 500)))
    (let
        (
            (voter-power (get-voting-power tx-sender))
            (current-time (get-current-time))
        )
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-community-member tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-proposal-active proposal-id) ERR_INVALID_STATE)
        (asserts! (not (has-voted proposal-id tx-sender)) ERR_ALREADY_VOTED)
        (asserts! (> voter-power u0) ERR_UNAUTHORIZED)
        
        ;; Record the vote
        (map-set proposal-votes
            { proposal-id: proposal-id, voter: tx-sender }
            {
                vote: vote,
                voting-power: voter-power,
                timestamp: current-time,
                comment: comment
            }
        )
        
        ;; Update proposal results
        (match (map-get? proposal-results { proposal-id: proposal-id })
            current-results
            (map-set proposal-results
                { proposal-id: proposal-id }
                (merge current-results {
                    yes-votes: (if vote (+ (get yes-votes current-results) u1) (get yes-votes current-results)),
                    no-votes: (if vote (get no-votes current-results) (+ (get no-votes current-results) u1)),
                    total-votes: (+ (get total-votes current-results) u1),
                    total-voting-power: (+ (get total-voting-power current-results) voter-power)
                })
            )
            false
        )
        
        ;; Update voter stats
        (match (map-get? community-members { member: tx-sender })
            member-data
            (map-set community-members
                { member: tx-sender }
                (merge member-data {
                    proposals-voted: (+ (get proposals-voted member-data) u1),
                    reputation-score: (+ (get reputation-score member-data) u1)
                })
            )
            false
        )
        
        (ok true)
    )
)

(define-public (finalize-proposal (proposal-id uint))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        
        (match (map-get? proposals { proposal-id: proposal-id })
            proposal-data
            (begin
                (asserts! (is-eq (get status proposal-data) "active") ERR_INVALID_STATE)
                (asserts! (>= block-height (get voting-end proposal-data)) ERR_INVALID_STATE)
                
                (let
                    (
                        (outcome (calculate-proposal-outcome proposal-id))
                    )
                    ;; Update proposal status
                    (map-set proposals
                        { proposal-id: proposal-id }
                        (merge proposal-data {
                            status: "finalized",
                            updated-at: (get-current-time)
                        })
                    )
                    
                    ;; Update results with final outcome
                    (match (map-get? proposal-results { proposal-id: proposal-id })
                        current-results
                        (map-set proposal-results
                            { proposal-id: proposal-id }
                            (merge current-results {
                                result: outcome
                            })
                        )
                        false
                    )
                    
                    (ok outcome)
                )
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
        
        (match (map-get? proposals { proposal-id: proposal-id })
            proposal-data
            (begin
                (asserts! (is-eq (get status proposal-data) "finalized") ERR_INVALID_STATE)
                (asserts! (is-eq (calculate-proposal-outcome proposal-id) "passed") ERR_INVALID_STATE)
                
                (map-set proposals
                    { proposal-id: proposal-id }
                    (merge proposal-data {
                        status: "executed",
                        updated-at: (get-current-time)
                    })
                )
                (ok true)
            )
            ERR_NOT_FOUND
        )
    )
)

(define-public (delegate-voting-power (delegate principal))
    (let
        (
            (delegator-power (get-voting-power tx-sender))
        )
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-community-member tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-community-member delegate) ERR_INVALID_INPUT)
        (asserts! (not (is-eq tx-sender delegate)) ERR_INVALID_INPUT)
        (asserts! (> delegator-power u0) ERR_UNAUTHORIZED)
        
        (map-set voting-delegates
            { delegator: tx-sender }
            {
                delegate: delegate,
                voting-power: delegator-power,
                delegation-start: (get-current-time),
                is-active: true
            }
        )
        (ok true)
    )
)

(define-public (revoke-delegation)
    (begin
        (asserts! (var-get contract-active) ERR_INVALID_STATE)
        (asserts! (is-some (map-get? voting-delegates { delegator: tx-sender })) ERR_NOT_FOUND)
        
        (match (map-get? voting-delegates { delegator: tx-sender })
            delegation-data
            (map-set voting-delegates
                { delegator: tx-sender }
                (merge delegation-data { is-active: false })
            )
            false
        )
        (ok true)
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
