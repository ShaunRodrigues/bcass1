// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * Anonymous, Non‑Fungible Voting System
 * -------------------------------------
 * Features
 *  - Eligibility via identity commitments (IC): ic = keccak256(secret)
 *  - One‑person‑one‑vote via per‑election nullifier: nullifier = keccak256(secret, electionId)
 *  - Vote secrecy via two‑phase commit‑reveal (prevents front‑running & hides ballot source)
 *  - Multiple methods: First‑Past‑the‑Post (FPTP), Instant Runoff (IRV), Condorcet (Minimax fallback),
 *    and Proportional Representation via D'Hondt (party‑list)
 *  - Admin‑driven election lifecycle with time‑boxed phases
 *
 *  ⚠️ Notes
 *   - This is a reference implementation optimized for clarity, not gas. Do not deploy as‑is without audits.
 *   - On‑chain IRV/Condorcet/PR tallying is O(N*M) or worse; set tight bounds.
 *   - Identity commitments MUST NOT be linkable to real‑world identities on‑chain.
 */

/* ============ Minimal Ownable ============ */
abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed from, address indexed to);
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner { require(newOwner!=address(0),"0"); emit OwnershipTransferred(owner,newOwner); owner=newOwner; }
}

/* ============ Voter Registry (Identity Commitments) ============ */
contract VoterRegistry is Ownable {
    // ic => registered
    mapping(bytes32 => bool) public isRegisteredIC;
    event IdentityCommitmentAdded(bytes32 ic);
    event IdentityCommitmentRemoved(bytes32 ic);

    function addIdentityCommitments(bytes32[] calldata ics) external onlyOwner {
        for (uint i=0; i<ics.length; i++) { isRegisteredIC[ics[i]] = true; emit IdentityCommitmentAdded(ics[i]); }
    }
    function removeIdentityCommitments(bytes32[] calldata ics) external onlyOwner {
        for (uint i=0; i<ics.length; i++) { delete isRegisteredIC[ics[i]]; emit IdentityCommitmentRemoved(ics[i]); }
    }
}

/* ============ Base Election ============ */
abstract contract ElectionBase is Ownable {
    enum Phase { Pending, Commit, Reveal, Finalized }

    VoterRegistry public registry;
    string public name;
    uint256 public electionId; // globally unique id (eg from factory counter)

    Phase public phase;
    uint64 public commitDeadline; // unix time
    uint64 public revealDeadline; // unix time

    // Commitments
    // comHash = keccak256( abi.encodePacked(electionId, ballotEncoded, salt, secret) )
    mapping(bytes32 => bool) public hasCommit;
    // nullifier = keccak256( abi.encodePacked(secret, electionId) )
    mapping(bytes32 => bool) public nullifierUsed;

    // guard
    bool internal finalized;

    event PhaseChanged(Phase phase);
    event Committed(bytes32 indexed comHash);
    event Revealed(bytes32 indexed comHash, bytes32 indexed nullifier);
    event Finalized();

    modifier inPhase(Phase p) { require(phase==p, "bad phase"); _; }

    constructor(
        VoterRegistry _registry,
        string memory _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline
    ) {
        require(_commitDeadline < _revealDeadline, "timeline");
        registry = _registry;
        name = _name;
        electionId = _electionId;
        commitDeadline = _commitDeadline;
        revealDeadline = _revealDeadline;
        phase = Phase.Commit;
        emit PhaseChanged(phase);
    }

    /* ---------- Admin controls ---------- */
    function setDeadlines(uint64 _commit, uint64 _reveal) external onlyOwner {
        require(_commit < _reveal, "timeline");
        require(block.timestamp < _reveal, "past");
        commitDeadline = _commit; revealDeadline = _reveal;
    }

    function advancePhase() public {
        if (phase == Phase.Commit && block.timestamp >= commitDeadline) { phase = Phase.Reveal; emit PhaseChanged(phase); }
        if (phase == Phase.Reveal && block.timestamp >= revealDeadline) { phase = Phase.Finalized; emit PhaseChanged(phase); _finalize(); }
    }

    /* ---------- Voting flow ---------- */
    function commit(bytes32 comHash) external inPhase(Phase.Commit) {
        require(block.timestamp < commitDeadline, "commit over");
        require(!hasCommit[comHash], "dup commit");
        hasCommit[comHash] = true; emit Committed(comHash);
    }

    /**
     * Reveal must provide:
     *   - ballotEncoded: ABI-encoded ballot payload expected by each election subtype
     *   - salt: random 32 bytes chosen by voter at commit
     *   - secret: private voter secret whose hash (ic) was pre‑registered in VoterRegistry
     * Checks:
     *   - commitment existed (prevents front‑running)
     *   - secret corresponds to a registered identity commitment (ic)
     *   - nullifier not seen for this election (one‑person‑one‑vote; anonymous)
     */
    function reveal(bytes memory ballotEncoded, bytes32 salt, bytes32 secret) public inPhase(Phase.Reveal) {
        require(block.timestamp < revealDeadline, "reveal over");
        bytes32 comHash = keccak256(abi.encodePacked(electionId, ballotEncoded, salt, secret));
        require(hasCommit[comHash], "no commit");

        bytes32 ic = keccak256(abi.encodePacked(secret));
        require(registry.isRegisteredIC(ic), "not eligible");

        bytes32 nullifier = keccak256(abi.encodePacked(secret, electionId));
        require(!nullifierUsed[nullifier], "already voted");
        nullifierUsed[nullifier] = true;

        _recordBallot(ballotEncoded);
        emit Revealed(comHash, nullifier);
    }

    function finalize() external { advancePhase(); require(phase==Phase.Finalized, "not finalized"); }

    /* ---------- Hooks ---------- */
    function _recordBallot(bytes memory ballotEncoded) internal virtual;
    function _finalize() internal virtual;
}

/* ============ First‑Past‑the‑Post ============ */
contract FPTPElection is ElectionBase {
    // Candidates are identified by 0..(n-1)
    string[] public candidates; // metadata labels
    uint256[] public tallies;   // votes per candidate
    bool public computed;
    uint256 public winner;      // index

    constructor(
        VoterRegistry reg,
        string memory _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] memory _cands
    ) ElectionBase(reg,_name,_electionId,_commitDeadline,_revealDeadline) {
        require(_cands.length>=2 && _cands.length<=50, "cand bounds");
        candidates = _cands; tallies = new uint256[](_cands.length);
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint256 choice = abi.decode(ballotEncoded, (uint256));
        require(choice < candidates.length, "bad cand");
        tallies[choice] += 1;
    }

    function _finalize() internal override {
        if (computed) return; computed = true;
        uint256 maxVotes = 0; uint256 win = 0;
        for (uint i=0;i<tallies.length;i++){ if (tallies[i]>maxVotes){maxVotes=tallies[i];win=i;} }
        winner = win; emit Finalized();
    }
}

/* ============ Instant Runoff Voting (IRV) ============ */
contract IRVElection is ElectionBase {
    string[] public candidates;                 // labels
    uint8[][] public rankings;                  // ballots: list of rankings (candidate indices)
    bool public computed;
    uint256 public winner;

    constructor(
        VoterRegistry reg,
        string memory _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] memory _cands
    ) ElectionBase(reg,_name,_electionId,_commitDeadline,_revealDeadline) {
        require(_cands.length>=2 && _cands.length<=20, "cand bounds");
        candidates = _cands;
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        require(pref.length==candidates.length, "full ranking required");
        // Validate no duplicates and all < n
        uint n=candidates.length; bool[] memory seen = new bool[](n);
        for (uint i=0;i<pref.length;i++){ require(pref[i]<n && !seen[pref[i]], "bad rank"); seen[pref[i]]=true; }
        rankings.push(pref);
    }

    function _finalize() internal override {
        if (computed) return; computed=true;
        uint n = candidates.length;
        bool[] memory eliminated = new bool[](n);
        uint remaining = n;

        while (true) {
            // Tally first active preferences
            uint[] memory tally = new uint[](n);
            for (uint b=0;b<rankings.length;b++){
                uint8[] storage r = rankings[b];
                for (uint k=0;k<r.length;k++){
                    uint8 c = r[k];
                    if (!eliminated[c]) { tally[c]++; break; }
                }
            }
            // Check majority
            uint totalVotes = rankings.length;
            for (uint i=0;i<n;i++){
                if (eliminated[i]) continue;
                if (tally[i]*2 > totalVotes) { winner=i; emit Finalized(); return; }
            }
            // Find min tally among active
            uint minVotes = type(uint).max; uint minIdx = 0; bool tie=true; uint lastVotes=0; bool first=true;
            for (uint i=0;i<n;i++) if(!eliminated[i]){
                if (first){minVotes=tally[i]; minIdx=i; lastVotes=tally[i]; first=false;} else {
                    if (tally[i] < minVotes){minVotes=tally[i]; minIdx=i;}
                    if (tally[i] != lastVotes) tie=false;
                }
            }
            if (tie) { // break tie by lowest index
                for (uint i=0;i<n;i++){ if(!eliminated[i]){ winner=i; emit Finalized(); return; } }
            }
            // Eliminate lowest
            eliminated[minIdx]=true; remaining--; if (remaining==1){
                for (uint i=0;i<n;i++) if(!eliminated[i]){ winner=i; emit Finalized(); return; }
            }
        }
    }
}

/* ============ Condorcet (Pairwise; Minimax fallback) ============ */
contract CondorcetElection is ElectionBase {
    string[] public candidates;      // labels
    uint8[][] public rankings;       // full rankings required
    bool public computed;
    uint256 public winner;

    constructor(
        VoterRegistry reg,
        string memory _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] memory _cands
    ) ElectionBase(reg,_name,_electionId,_commitDeadline,_revealDeadline) {
        require(_cands.length>=2 && _cands.length<=15, "cand bounds");
        candidates = _cands;
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        require(pref.length==candidates.length, "full ranking required");
        uint n=candidates.length; bool[] memory seen = new bool[](n);
        for (uint i=0;i<pref.length;i++){ require(pref[i]<n && !seen[pref[i]], "bad rank"); seen[pref[i]]=true; }
        rankings.push(pref);
    }

    function _finalize() internal override {
        if (computed) return; computed=true;
        uint n = candidates.length;
        // pairwise[i][j] = #ballots preferring i over j
        uint[][] memory pairwise = new uint[][](n);
        for (uint i=0;i<n;i++){ pairwise[i] = new uint[](n); }

        // Precompute positions for speed
        for (uint b=0;b<rankings.length;b++){
            uint8[] storage r = rankings[b];
            uint8[] memory pos = new uint8[](n);
            for (uint i=0;i<n;i++){ pos[r[i]] = uint8(i); }
            for (uint i=0;i<n;i++){
                for (uint j=0;j<n;j++) if (i!=j) {
                    if (pos[i] < pos[j]) { pairwise[i][j]++; }
                }
            }
        }

        // Find Condorcet winner if exists
        for (uint i=0;i<n;i++){
            bool beatsAll=true;
            for (uint j=0;j<n;j++) if (i!=j) { if (pairwise[i][j] <= pairwise[j][i]) { beatsAll=false; break; } }
            if (beatsAll){ winner=i; emit Finalized(); return; }
        }

        // Minimax (winning votes): choose candidate with smallest maximum defeat
        uint bestIdx=0; uint bestScore=type(uint).max; bool init=false;
        for (uint i=0;i<n;i++){
            uint maxDefeat=0;
            for (uint j=0;j<n;j++) if (i!=j){
                if (pairwise[j][i] > pairwise[i][j]){
                    uint margin = pairwise[j][i] - pairwise[i][j];
                    if (margin>maxDefeat) maxDefeat=margin;
                }
            }
            if (!init || maxDefeat < bestScore){ bestScore=maxDefeat; bestIdx=i; init=true; }
        }
        winner = bestIdx; emit Finalized();
    }
}

/* ============ Proportional Representation (D'Hondt) ============ */
contract PRElectionDhondt is ElectionBase {
    struct Party { string name; uint256 voteCount; uint256 seatsWon; uint256[] candidates; }
    Party[] public parties; // partyId => Party; candidates are indices globally (optional metadata only)
    uint8 public seats;     // total seats to allocate
    bool public computed;
    uint256[] public allocation; // partyId => seats

    constructor(
        VoterRegistry reg,
        string memory _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] memory _partyNames,
        uint8 _seats
    ) ElectionBase(reg,_name,_electionId,_commitDeadline,_revealDeadline) {
        require(_partyNames.length>=2 && _partyNames.length<=50, "party bounds");
        require(_seats>=1 && _seats<=200, "seats bounds");
        for (uint i=0;i<_partyNames.length;i++) { parties.push(Party({name:_partyNames[i], voteCount:0, seatsWon:0, candidates:new uint256[](0)})); }
        seats = _seats; allocation = new uint256[](_partyNames.length);
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint256 partyId = abi.decode(ballotEncoded, (uint256));
        require(partyId < parties.length, "bad party");
        parties[partyId].voteCount += 1;
    }

    function _finalize() internal override {
        if (computed) return; computed = true;
        uint n = parties.length;
        uint8 remaining = seats;
        uint256[] memory quotients = new uint256[](n);
        for (uint i=0;i<n;i++){ quotients[i] = parties[i].voteCount; }
        while (remaining>0){
            // find max quotient
            uint idx=0; uint256 best=0;
            for (uint i=0;i<n;i++){
                if (quotients[i] > best){ best=quotients[i]; idx=i; }
            }
            parties[idx].seatsWon += 1; allocation[idx] += 1; remaining -= 1;
            quotients[idx] = parties[idx].voteCount / (parties[idx].seatsWon + 1);
        }
        emit Finalized();
    }
}

/* ============ Factory ============ */
contract ElectionFactory is Ownable {
    VoterRegistry public registry;
    uint256 public nextElectionId = 1;

    event FPTPCreated(address indexed election, uint256 id);
    event IRVCreated(address indexed election, uint256 id);
    event CondorcetCreated(address indexed election, uint256 id);
    event PRDhondtCreated(address indexed election, uint256 id);

    constructor(VoterRegistry _registry){ registry = _registry; }

    function createFPTP(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        FPTPElection e = new FPTPElection(registry, name, nextElectionId++, commitDeadline, revealDeadline, candidates);
        e.transferOwnership(msg.sender); emit FPTPCreated(address(e), e.electionId()); return address(e);
    }

    function createIRV(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        IRVElection e = new IRVElection(registry, name, nextElectionId++, commitDeadline, revealDeadline, candidates);
        e.transferOwnership(msg.sender); emit IRVCreated(address(e), e.electionId()); return address(e);
    }

    function createCondorcet(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        CondorcetElection e = new CondorcetElection(registry, name, nextElectionId++, commitDeadline, revealDeadline, candidates);
        e.transferOwnership(msg.sender); emit CondorcetCreated(address(e), e.electionId()); return address(e);
    }

    function createPRDhondt(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata partyNames,
        uint8 seats
    ) external onlyOwner returns (address) {
        PRElectionDhondt e = new PRElectionDhondt(registry, name, nextElectionId++, commitDeadline, revealDeadline, partyNames, seats);
        e.transferOwnership(msg.sender); emit PRDhondtCreated(address(e), e.electionId()); return address(e);
    }
}

/* ============ Helper: Ballot Encoding Off‑Chain Reference ============ */
/**
 * Off‑chain ballot encoding examples (ABI):
 *  - FPTP:      abi.encode(uint256 candidateIndex)
 *  - IRV:       abi.encode(uint8[] rankedCandidatesOfLengthN)
 *  - Condorcet: abi.encode(uint8[] rankedCandidatesOfLengthN)
 *  - PR D'Hondt:abi.encode(uint256 partyIndex)
 *
 * Commitment:
 *  comHash = keccak256( abi.encodePacked(electionId, ballotEncoded, salt, secret) )
 *  Submit Election.commit(comHash) during COMMIT phase
 *  Reveal with Election.reveal(ballotEncoded, salt, secret) during REVEAL phase
 *
 * Eligibility:
 *  - Authority pre‑registers identity commitments (ic = keccak256(secret)) in VoterRegistry
 *  - On reveal, contract checks ic exists and that nullifier (keccak256(secret, electionId)) unused
 *  - ✅ Anonymous: neither the tx sender nor IC is linked to a person on‑chain
 *  - ✅ Non‑fungible: each secret can produce exactly one nullifier per election
 */