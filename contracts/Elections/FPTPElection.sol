// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ElectionBase.sol";

contract FPTPElection is ElectionBase {
    string[] public candidates; // metadata labels
    uint8[] public tallies;   // votes per candidate
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
        tallies = new uint8[](_cands.length);

        // set owner last
        _setOwner(_owner);
    }

    function _recordBallot(bytes memory ballotEncoded) internal override {
        uint8[] memory pref = abi.decode(ballotEncoded, (uint8[]));
        uint8 choice = pref[0];
        //require(choice < candidates.length, "bad cand");
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
