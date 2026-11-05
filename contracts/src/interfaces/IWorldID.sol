// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @notice World ID v3 (legacy) router interface, as deployed on Ethereum Sepolia at
///         0x469449f251692e0779667583026b5a1e99512157 (docs.world.org/world-id/id/on-chain).
interface IWorldID {
    /// @dev Reverts if the proof is invalid.
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external view;
}
