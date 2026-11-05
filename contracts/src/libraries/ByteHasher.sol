// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title ByteHasher
/// @notice World ID `hashToField`: hash arbitrary bytes into the field used by World ID proofs.
library ByteHasher {
    /// @param value The bytes to hash.
    /// @return The keccak256 of `value` shifted right by 8 bits so it fits the snark field.
    function hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }
}
