
/*pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract FPTPElection is ElectionBase {
    string[] public candidates;
    uint256[] public tallies;
    bool public computed;
    uint256 public winner;
    bool private initialized;

    uint256 public constant MAX_CANDIDATES = 100;

    constructor(
        VoterRegistry reg,
        string memory _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] memory _cands
    ) ElectionBase(reg, _name, _electionId, _commitDeadline, _revealDeadline) {
        require(_cands.length >= 2 && _cands.length <= MAX_CANDIDATES, "FPTP: candidate bounds");
        candidates = _cands;
        tallies = new uint256[](_cands.length);
    }

    // ballotEncoded = abi.encode(uint256 candidateIndex)
    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint256 choice = abi.decode(ballotEncoded, (uint256));
        require(choice < candidates.length, "FPTP: bad candidate");
        tallies[choice] += 1;
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint256 maxVotes = 0;
        uint256 win = 0;
        for (uint i = 0; i < tallies.length; i++) {
            if (tallies[i] > maxVotes) { maxVotes = tallies[i]; win = i; }
        }
        winner = win;
        emit FinalizedEvent();
    }
}*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract FPTPElection is ElectionBase {
    string[] public candidates; // metadata labels
    uint256[] public tallies;   // votes per candidate
    bool public computed;
    uint256 public winner;      // index

    bool private initialized;

    /// @notice initialize for clones
    function initialize(
        VoterRegistry _registry,
        address _eId,
        string calldata _name,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] calldata _cands,
        address _owner
    ) external {
        require(!initialized, "initialized");
        initialized = true;

        _electionBaseInit(_registry, _eId, _name, _commitDeadline, _revealDeadline);

        require(_cands.length >= 2 && _cands.length <= 50, "cand bounds");
        delete candidates; // clear old storage just in case
    for (uint i = 0; i < _cands.length; i++) {
        candidates.push(_cands[i]);
    }
        tallies = new uint256[](_cands.length);

        // set owner last
        _setOwner(_owner);
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint256 choice = abi.decode(ballotEncoded, (uint256));
        require(choice < candidates.length, "bad cand");
        tallies[choice] += 1;
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint256 maxVotes = 0;
        uint256 win = 0;
        for (uint i = 0; i < tallies.length; i++) {
            if (tallies[i] > maxVotes) {
                maxVotes = tallies[i];
                win = i;
            }
        }
        winner = win;
        emit Finalized();
    }
}
