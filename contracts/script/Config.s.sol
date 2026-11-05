// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";

/// @title Config
/// @notice Shared helpers for the deployment scripts. Nothing is hard-coded except the public
///         World ID router, whose address is documented at docs.world.org/world-id/id/on-chain.
///         ENSv2 core addresses are read from the pinned `contracts-v2` Sepolia deployment set.
abstract contract Config is Script {
    /// @notice World ID v3 router on Ethereum Sepolia.
    address internal constant SEPOLIA_WORLD_ROUTER = 0x469449f251692E0779667583026b5A1E99512157;

    /// @notice Reads the address of an ENSv2 core contract from the pinned deployment set.
    /// @param name Contract name as it appears in `deployments/sepolia/<name>.json`.
    function ensAddress(string memory name) internal view returns (address) {
        string memory path =
            string.concat(vm.projectRoot(), "/lib/contracts-v2/contracts/deployments/sepolia/", name, ".json");
        return vm.parseJsonAddress(vm.readFile(path), ".address");
    }

    /// @notice Directory season deployment files are written to, shared with the TypeScript packages.
    function deploymentsDir() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid));
    }

    /// @notice Path of the season deployment file.
    function seasonFile(string memory season) internal view returns (string memory) {
        return string.concat(deploymentsDir(), "/", season, ".json");
    }

    /// @notice Path of the realm state file written by `DeployRealm`.
    function realmFile() internal view returns (string memory) {
        return string.concat(deploymentsDir(), "/realm.json");
    }

    /// @notice DNS-encodes a name made of three labels, for example `s1.fealty.eth`.
    function dnsEncode3(string memory a, string memory b, string memory c) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(bytes(a).length), a, uint8(bytes(b).length), b, uint8(bytes(c).length), c, uint8(0));
    }

    /// @notice Reads an optional unsigned integer from the environment.
    function envOr(string memory key, uint256 fallbackValue) internal view returns (uint256) {
        return vm.envOr(key, fallbackValue);
    }
}
