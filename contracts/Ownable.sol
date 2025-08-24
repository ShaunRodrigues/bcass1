/* 
pragma solidity ^0.8.20;

abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == owner, "Ownable: caller is not the owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Ownable with an internal setter for proxy initialization.
abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @dev Constructor runs on implementation deployment; clones won't execute this.
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    /// @notice Normal external ownership transfer (requires current owner).
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @dev Internal setter used by initialize functions on clones. Emits event.
    ///      This bypasses the onlyOwner check because initialize must set owner on a fresh clone.
    function _setOwner(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
