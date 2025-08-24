/*
pragma solidity ^0.8.20;
import "./ElectionBase.sol";
contract PRElectionDhondt is ElectionBase {
    struct Party { string name; uint256 voteCount; uint256 seatsWon; }
    Party[] public parties;
    uint8 public seats;
    uint16 public thresholdBps; // basis points (0 disables)
    uint256[] public allocation;
    bool public computed;
    bool private initialized;

    uint256 public constant MAX_PARTIES = 100;

    function initialize(
        string memory _name,
        uint256 _electionId,
        uint64 _commitDeadline,
        uint64 _revealDeadline,
        string[] memory _partyNames,
        uint8 _seats,
        uint16 _thresholdBps
    ) external  {
        require(!initialized, "Already initialized");
        initialized = true;
        require(_partyNames.length >= 2 && _partyNames.length <= MAX_PARTIES, "PR: party bounds");
        require(_seats >= 1 && _seats <= 200, "PR: seats bounds");
        require(_thresholdBps < 10000, "PR: threshold invalid");

        require(!initialized, "Already initialized");
        initialized = true;

        name = _name;
        electionId = _electionId;
        commitDeadline = _commitDeadline;
        revealDeadline = _revealDeadline;
        thresholdBps=_thresholdBps;
        seats=_seats;

    

        for (uint i = 0; i < _partyNames.length; i++) parties.push(Party({ name: _partyNames[i], voteCount: 0, seatsWon: 0 }));
        seats = _seats;
        thresholdBps = _thresholdBps;
        allocation = new uint256[](_partyNames.length);
        super.transferOwnership(owner);
    }

    // ballotEncoded = abi.encode(uint256 partyIndex)
    function _recordBallot(bytes memory ballotEncoded) internal override {
        require(revealCount <= MAX_VOTERS, "PR: max voters");
        uint256 partyId = abi.decode(ballotEncoded, (uint256));
        require(partyId < parties.length, "PR: bad party");
        parties[partyId].voteCount += 1;
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;
        uint n = parties.length;
        uint256 totalVotes = 0;
        for (uint i = 0; i < n; i++) totalVotes += parties[i].voteCount;

        bool[] memory eligible = new bool[](n);
        for (uint i = 0; i < n; i++) {
            if (thresholdBps == 0) eligible[i] = true;
            else eligible[i] = (totalVotes > 0) && (parties[i].voteCount * 10000 >= uint256(thresholdBps) * totalVotes);
            parties[i].seatsWon = 0;
            allocation[i] = 0;
        }

        for (uint sAlloc = 0; sAlloc < seats; sAlloc++) {
            uint bestIdx = type(uint).max;
            uint256 bestNum = 0;
            uint256 bestDen = 1;
            for (uint p = 0; p < n; p++) {
                if (!eligible[p]) continue;
                uint256 num = parties[p].voteCount;
                uint256 den = parties[p].seatsWon + 1;
                if (bestIdx == type(uint).max) { bestIdx = p; bestNum = num; bestDen = den; }
                else {
                    uint256 left = num * bestDen;
                    uint256 right = bestNum * den;
                    if (left > right || (left == right && p < bestIdx)) {
                        bestIdx = p; bestNum = num; bestDen = den;
                    }
                }
            }
            if (bestIdx == type(uint).max) break;
            parties[bestIdx].seatsWon += 1;
            allocation[bestIdx] += 1;
        }

        emit FinalizedEvent();
    }
}
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract PRElectionDhondt is ElectionBase {
    struct Party { string name; uint256 voteCount; uint256 seatsWon; uint256[] candidates; }
    Party[] public parties; // partyId => Party
    uint8 public seats;     // total seats to allocate
    bool public computed;
    uint256[] public allocation; // partyId => seats
    uint16 public thresholdBps; // e.g. 500 = 5.00%

    bool private initialized;

    function initialize(
    VoterRegistry _registry,
    string calldata _name,
    uint256 _electionId,
    uint64 _commitDeadline,
    uint64 _revealDeadline,
    string[] calldata _partyNames,
    uint8 _seats,
    uint16 _thresholdBps,
    address _owner
) external {
    require(!initialized, "initialized");
    initialized = true;

    _electionBaseInit(_registry, _name, _electionId, _commitDeadline, _revealDeadline);

    require(_partyNames.length >= 2 && _partyNames.length <= 50, "party bounds");
    require(_seats >= 1 && _seats <= 200, "seats bounds");

    seats = _seats;
    thresholdBps = _thresholdBps;

    // Ensure parties is empty (fresh clone should be empty but this is defensive)
    delete parties;

    // Copy party names element-by-element into storage
    for (uint i = 0; i < _partyNames.length; i++) {
        parties.push();                               // append empty Party
        Party storage p = parties[parties.length - 1];
        p.name = _partyNames[i];                      // copy calldata -> storage (works per element)
        p.voteCount = 0;
        p.seatsWon = 0;
        // p.candidates is an empty dynamic array by default
    }

    allocation = new uint256[](_partyNames.length);

    // set owner last (uses your Ownable._setOwner)
    _setOwner(_owner);
}


    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint256 partyId = abi.decode(ballotEncoded, (uint256));
        require(partyId < parties.length, "bad party");
        parties[partyId].voteCount += 1;
    }

    function _finalize() internal override {
        if (computed) return;
        computed = true;

        uint n = parties.length;
        uint8 remaining = seats;
        uint256[] memory quotients = new uint256[](n);
        uint256 totalVotes = 0;
        for (uint i = 0; i < n; i++) {
            quotients[i] = parties[i].voteCount;
            totalVotes += parties[i].voteCount;
        }

        // Apply threshold in BPS (if thresholdBps > 0, disqualify parties under threshold)
        bool[] memory disqualified = new bool[](n);
        if (thresholdBps > 0 && totalVotes > 0) {
            for (uint i = 0; i < n; i++) {
                if ((parties[i].voteCount * 10000) < (uint256(thresholdBps) * totalVotes)) {
                    disqualified[i] = true;
                    quotients[i] = 0;
                }
            }
        }

        while (remaining > 0) {
            uint idx = 0;
            uint256 best = 0;
            for (uint i = 0; i < n; i++) {
                if (disqualified[i]) continue;
                if (quotients[i] > best) { best = quotients[i]; idx = i; }
            }
            parties[idx].seatsWon += 1;
            allocation[idx] += 1;
            remaining -= 1;
            quotients[idx] = parties[idx].voteCount / (parties[idx].seatsWon + 1);
        }
        emit Finalized();
    }
}
