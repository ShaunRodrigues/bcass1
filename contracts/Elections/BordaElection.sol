/*
pragma solidity ^0.8.20;
import "./ElectionBase.sol";

contract BordaElection is ElectionBase {
    string[] public candidates;
    uint8[][] public rankings;
    uint256[] public scores;
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
        require(_cands.length >= 2 && _cands.length <= MAX_CANDIDATES, "Borda: candidate bounds");
        candidates = _cands;
        scores = new uint256[](_cands.length);
    }

    // ballotEncoded = abi.encode(uint8[] fullRanking)
    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        uint n = candidates.length;
        require(pref.length == n, "Borda: full ranking required");
        bool[] memory seen = new bool[](n);
        for (uint i = 0; i < n; i++) {
            require(pref[i] < n && !seen[pref[i]], "Borda: bad ranking");
            seen[pref[i]] = true;
        }
        rankings.push(pref);
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint n = candidates.length;
        for (uint b = 0; b < rankings.length; b++) {
            uint8[] storage r = rankings[b];
            // Borda score: (n - pos - 1) gives top candidate n-1, last 0
            for (uint pos = 0; pos < n; pos++) {
                uint8 c = r[pos];
                scores[c] += (n - pos - 1);
            }
        }
        uint bestScore = 0;
        uint bestIdx = 0;
        for (uint i = 0; i < n; i++) {
            if (scores[i] > bestScore) { bestScore = scores[i]; bestIdx = i; }
        }
        winner = bestIdx;
        emit FinalizedEvent();
    }
}*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract BordaElection is ElectionBase {
    string[] public candidates;
    uint256[] public scores;
    bool public computed;
    uint256 public winner;

    bool private initialized;

    function initialize(
        VoterRegistry _registry,
        string calldata _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] calldata _cands,
        address _owner
    ) external {
        require(!initialized, "initialized");
        initialized = true;

        _electionBaseInit(_registry, _name, _electionId, _commitDeadline, _revealDeadline);
        require(_cands.length >= 2 && _cands.length <= 50, "cand bounds");
        delete candidates;
        for (uint i = 0; i < _cands.length; i++) {
        candidates.push(_cands[i]);
        }
        scores = new uint256[](_cands.length);

        _setOwner(_owner);
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        require(pref.length == candidates.length, "full ranking required");
        uint n = candidates.length;
        bool[] memory seen = new bool[](n);
        for (uint i = 0; i < pref.length; i++) {
            require(pref[i] < n && !seen[pref[i]], "bad rank");
            seen[pref[i]] = true;
        }
        // Borda scoring: top gets n-1, next n-2, ... last 0
        for (uint i = 0; i < pref.length; i++) {
            uint idx = pref[i];
            scores[idx] += (n - 1 - i);
        }
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint maxScore = 0;
        uint win = 0;
        for (uint i = 0; i < scores.length; i++) {
            if (scores[i] > maxScore) {
                maxScore = scores[i];
                win = i;
            }
        }
        winner = win;
        emit Finalized();
    }
}
