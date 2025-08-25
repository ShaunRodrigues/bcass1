
/*pragma solidity ^0.8.20;
import "./ElectionBase.sol";
contract CondorcetElection is ElectionBase {
    string[] public candidates;
    uint8[][] public rankings;
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
        require(_cands.length >= 2 && _cands.length <= MAX_CANDIDATES, "Condorcet: candidate bounds");
        candidates = _cands;
    }

    // ballotEncoded = abi.encode(uint8[] fullRanking)
    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        uint n = candidates.length;
        require(pref.length == n, "Condorcet: full ranking required");
        bool[] memory seen = new bool[](n);
        for (uint i = 0; i < n; i++) {
            require(pref[i] < n && !seen[pref[i]], "Condorcet: bad ranking");
            seen[pref[i]] = true;
        }
        rankings.push(pref);
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint n = candidates.length;

        // pairwise[i][j] = ballots preferring i over j
        uint[][] memory pairwise = new uint[][](n);
        for (uint i = 0; i < n; i++) pairwise[i] = new uint[](n);

        for (uint b = 0; b < rankings.length; b++) {
            uint8[] storage r = rankings[b];
            uint8[] memory pos = new uint8[](n);
            for (uint i = 0; i < n; i++) pos[r[i]] = uint8(i);
            for (uint i = 0; i < n; i++) {
                for (uint j = 0; j < n; j++) if (i != j) {
                    if (pos[i] < pos[j]) pairwise[i][j]++;
                }
            }
        }

        // Condorcet winner?
        for (uint i = 0; i < n; i++) {
            bool beatsAll = true;
            for (uint j = 0; j < n; j++) if (i != j) {
                if (pairwise[i][j] <= pairwise[j][i]) { beatsAll = false; break; }
            }
            if (beatsAll) { winner = i; emit FinalizedEvent(); return; }
        }

        // Minimax (smallest max defeat)
        uint bestIdx = 0;
        uint bestScore = type(uint).max;
        bool init = false;
        for (uint i = 0; i < n; i++) {
            uint maxDefeat = 0;
            for (uint j = 0; j < n; j++) if (i != j) {
                if (pairwise[j][i] > pairwise[i][j]) {
                    uint margin = pairwise[j][i] - pairwise[i][j];
                    if (margin > maxDefeat) maxDefeat = margin;
                }
            }
            if (!init || maxDefeat < bestScore) { bestScore = maxDefeat; bestIdx = i; init = true; }
        }
        winner = bestIdx;
        emit FinalizedEvent();
    }
}
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract CondorcetElection is ElectionBase {
    string[] public candidates;      // labels
    uint8[][] public rankings;       // full rankings required
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

        _electionBaseInit(_registry, _eId, _name, _commitDeadline, _revealDeadline);
        require(_cands.length >= 2 && _cands.length <= 15, "cand bounds");
        delete candidates;
        for (uint i = 0; i < _cands.length; i++) {
        candidates.push(_cands[i]);
        }

        _setOwner(_owner);
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        require(pref.length == candidates.length, "full ranking required");
        uint n = candidates.length; bool[] memory seen = new bool[](n);
        for (uint i = 0; i < pref.length; i++) { require(pref[i] < n && !seen[pref[i]], "bad rank"); seen[pref[i]] = true; }
        rankings.push(pref);
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint n = candidates.length;
        uint[][] memory pairwise = new uint[][](n);
        for (uint i = 0; i < n; i++) { pairwise[i] = new uint[](n); }

        for (uint b = 0; b < rankings.length; b++) {
            uint8[] storage r = rankings[b];
            uint8[] memory pos = new uint8[](n);
            for (uint i = 0; i < n; i++) { pos[r[i]] = uint8(i); }
            for (uint i = 0; i < n; i++) {
                for (uint j = 0; j < n; j++) if (i != j) {
                    if (pos[i] < pos[j]) { pairwise[i][j]++; }
                }
            }
        }

        // Condorcet winner?
        for (uint i = 0; i < n; i++) {
            bool beatsAll = true;
            for (uint j = 0; j < n; j++) if (i != j) { if (pairwise[i][j] <= pairwise[j][i]) { beatsAll = false; break; } }
            if (beatsAll) { winner = i; emit Finalized(); return; }
        }

        // Minimax fallback (winning votes)
        uint bestIdx = 0; uint bestScore = type(uint).max; bool init = false;
        for (uint i = 0; i < n; i++) {
            uint maxDefeat = 0;
            for (uint j = 0; j < n; j++) if (i != j) {
                if (pairwise[j][i] > pairwise[i][j]) {
                    uint margin = pairwise[j][i] - pairwise[i][j];
                    if (margin > maxDefeat) maxDefeat = margin;
                }
            }
            if (!init || maxDefeat < bestScore) { bestScore = maxDefeat; bestIdx = i; init = true; }
        }
        winner = bestIdx;
        emit Finalized();
    }
}
