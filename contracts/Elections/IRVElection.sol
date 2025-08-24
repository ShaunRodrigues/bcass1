// SPDX-License-Identifier: MIT
/*pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract IRVElection is ElectionBase {
    string[] public candidates;
    uint8[][] public rankings; // each ballot: full ranking of length n
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
        require(_cands.length >= 2 && _cands.length <= MAX_CANDIDATES, "IRV: candidate bounds");
        candidates = _cands;
    }

    // ballotEncoded = abi.encode(uint8[] fullRanking)
    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        uint n = candidates.length;
        require(pref.length == n, "IRV: full ranking required");
        bool[] memory seen = new bool[](n);
        for (uint i = 0; i < n; i++) {
            require(pref[i] < n && !seen[pref[i]], "IRV: bad ranking");
            seen[pref[i]] = true;
        }
        rankings.push(pref);
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint n = candidates.length;
        bool[] memory eliminated = new bool[](n);
        uint remaining = n;

        while (true) {
            uint[] memory tally = new uint[](n);
            for (uint b = 0; b < rankings.length; b++) {
                uint8[] storage r = rankings[b];
                for (uint k = 0; k < r.length; k++) {
                    uint8 c = r[k];
                    if (!eliminated[c]) { tally[c]++; break; }
                }
            }

            uint totalVotes = rankings.length;
            // majority?
            for (uint i = 0; i < n; i++) {
                if (!eliminated[i] && tally[i] * 2 > totalVotes) {
                    winner = i;
                    emit FinalizedEvent();
                    return;
                }
            }

            // find min among active
            uint minVotes = type(uint).max;
            uint minIdx = 0;
            bool tie = true;
            uint lastVotes = 0;
            bool first = true;
            for (uint i = 0; i < n; i++) {
                if (eliminated[i]) continue;
                if (first) { minVotes = tally[i]; minIdx = i; lastVotes = tally[i]; first = false; }
                else {
                    if (tally[i] < minVotes) { minVotes = tally[i]; minIdx = i; }
                    if (tally[i] != lastVotes) tie = false;
                }
            }

            if (tie) {
                // deterministic tie-break: lowest index wins
                for (uint i = 0; i < n; i++) if (!eliminated[i]) { winner = i; emit FinalizedEvent(); return; }
            }

            eliminated[minIdx] = true;
            remaining--;
            if (remaining == 1) {
                for (uint i = 0; i < n; i++) if (!eliminated[i]) { winner = i; emit FinalizedEvent(); return; }
            }
        }
    }
}
*/

pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract IRVElection is ElectionBase {
    string[] public candidates;                 // labels
    uint8[][] public rankings;                  // ballots: list of rankings (candidate indices)
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
        require(_cands.length >= 2 && _cands.length <= 20, "cand bounds");
        delete candidates; // clear old storage just in case
    for (uint i = 0; i < _cands.length; i++) {
        candidates.push(_cands[i]);
        }
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
        rankings.push(pref);
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint n = candidates.length;
        bool[] memory eliminated = new bool[](n);
        uint remaining = n;

        while (true) {
            // Tally first active preferences
            uint[] memory tally = new uint[](n);
            for (uint b = 0; b < rankings.length; b++) {
                uint8[] storage r = rankings[b];
                for (uint k = 0; k < r.length; k++) {
                    uint8 c = r[k];
                    if (!eliminated[c]) { tally[c]++; break; }
                }
            }
            // Check majority
            uint totalVotes = rankings.length;
            for (uint i = 0; i < n; i++) {
                if (eliminated[i]) continue;
                if (tally[i] * 2 > totalVotes) { winner = i; emit Finalized(); return; }
            }
            // Find min tally among active
            uint minVotes = type(uint).max; uint minIdx = 0; bool tie = true; uint lastVotes = 0; bool first = true;
            for (uint i = 0; i < n; i++) if (!eliminated[i]) {
                if (first) { minVotes = tally[i]; minIdx = i; lastVotes = tally[i]; first = false; } else {
                    if (tally[i] < minVotes) { minVotes = tally[i]; minIdx = i; }
                    if (tally[i] != lastVotes) tie = false;
                }
            }
            if (tie) { // break tie by lowest index
                for (uint i = 0; i < n; i++) { if (!eliminated[i]) { winner = i; emit Finalized(); return; } }
            }
            // Eliminate lowest
            eliminated[minIdx] = true; remaining--; if (remaining == 1) {
                for (uint i = 0; i < n; i++) if (!eliminated[i]) { winner = i; emit Finalized(); return; }
            }
        }
    }
}
