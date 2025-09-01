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
        address _eId,
        string calldata _name,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] calldata _cands,
        address _owner
    ) external {
        require(!initialized, "initialized");
        initialized = true;

        _electionBaseInit(_registry, _eId,  _name, _commitDeadline, _revealDeadline);
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