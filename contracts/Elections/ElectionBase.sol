// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Ownable.sol";
import "../VoterRegistry.sol";

abstract contract ElectionBase is Ownable {
    enum Phase { Pending, Commit, Reveal, Finalized }

    VoterRegistry public registry;
    string public name;

    address election;

    Phase public phase;
    uint64 public commitDeadline;
    uint64 public revealDeadline;

    // Commitments
    // comHash = keccak256( abi.encodePacked(electionId, ballotEncoded, secret) )
    mapping(bytes32 => bool) public hasCommit;
    // nullifier = keccak256( abi.encodePacked(secret, electionId) )
    mapping(bytes32 => bool) public nullifierUsed;

    // guard
    bool internal finalized;

    event PhaseChanged(Phase phase);
    event Committed(bytes32 indexed comHash);
    event Revealed(bytes32 indexed comHash, bytes32 indexed nullifier);
    event Finalized();

    modifier inPhase(Phase p) { require(phase == p, "bad phase"); _; }

    // ---- initializer for proxy clones ----
    bool private baseInitialized;
    function _electionBaseInit(
        VoterRegistry _registry,
        address _electionId,
        string calldata _name,
        uint64 _commitDeadline,
        uint64 _revealDeadline
    ) internal {
        require(!baseInitialized, "base init");
        require(_commitDeadline < _revealDeadline, "timeline");
        baseInitialized = true;
        registry = _registry;
        name = _name;
        election = _electionId;
        commitDeadline = _commitDeadline;
        revealDeadline = _revealDeadline;
        phase = Phase.Commit;
        emit PhaseChanged(phase);
    }

    /* ---------- Admin controls ---------- */
    function setDeadlines(uint64 _commit, uint64 _reveal) external onlyOwner {
        require(_commit < _reveal, "timeline");
        require(block.timestamp < _reveal, "past");
        require(phase == Phase.Pending || phase == Phase.Commit, "too late");
        commitDeadline = _commit;
        revealDeadline = _reveal;
    }

    function advancePhase() public {
        if (phase == Phase.Commit && block.timestamp >= commitDeadline) {
            phase = Phase.Reveal;
            emit PhaseChanged(phase);
        }
        if (phase == Phase.Reveal && block.timestamp >= revealDeadline) {
            phase = Phase.Finalized;
            emit PhaseChanged(phase);
            _finalize();
        }
    }

    /* ---------- Voting flow ---------- */
    function commit(bytes32 comHash) external inPhase(Phase.Commit) {
        require(block.timestamp < commitDeadline, "commit over");
        require(!hasCommit[comHash], "dup commit");
        hasCommit[comHash] = true;
        emit Committed(comHash);
    }

    function reveal(bytes memory ballotEncoded, bytes32 secret) public inPhase(Phase.Reveal) {
        require(block.timestamp < revealDeadline, "reveal over");
        bytes32 comHash = keccak256(abi.encodePacked(election, ballotEncoded, secret));
        require(hasCommit[comHash], "no commit");

        bytes32 ic = keccak256(abi.encodePacked(msg.sender, election));
        require(registry.isActive(election, ic), "not eligible");

        bytes32 nullifier = keccak256(abi.encodePacked(secret, election));
        require(!nullifierUsed[nullifier], "already voted");
        nullifierUsed[nullifier] = true;

        _recordBallot(ballotEncoded);
        emit Revealed(comHash, nullifier);
    }

    function finalize() external { advancePhase(); require(phase == Phase.Finalized, "not finalized"); }

    /* ---------- Hooks to implement in child contracts ---------- */
    function _recordBallot(bytes memory ballotEncoded) internal virtual;
    function _finalize() internal virtual;
}