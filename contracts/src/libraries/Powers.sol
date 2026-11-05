// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";

/// @notice The three powers of the Tyrant. Each is a real ENSv2 root role on the court registry.
enum Power {
    Banish, // ROLE_UNREGISTER: deletes a vassal's name
    Decree, // ROLE_SET_RESOLVER: overwrites a vassal's record
    Dissolve // ROLE_SET_SUBREGISTRY: destroys a vassal's sub-court
}

/// @title Powers
/// @notice Maps game powers to the ENSv2 role bits that embody them.
library Powers {
    /// @notice Number of powers in the game.
    uint256 internal constant COUNT = 3;

    /// @notice Root roles the Throne must hold to exercise a power, regular role plus its admin bit.
    ///         Holding the admin bit is what makes revocation irreversible when it is the only holder.
    /// @param p The power.
    /// @return The regular role bit of the power.
    function role(Power p) internal pure returns (uint256) {
        if (p == Power.Banish) return RegistryRolesLib.ROLE_UNREGISTER;
        if (p == Power.Decree) return RegistryRolesLib.ROLE_SET_RESOLVER;
        return RegistryRolesLib.ROLE_SET_SUBREGISTRY;
    }

    /// @notice The regular role bit together with its admin counterpart.
    /// @param p The power.
    /// @return The bitmap revoked when the power is stripped.
    function roleWithAdmin(Power p) internal pure returns (uint256) {
        uint256 r = role(p);
        return r | (r << 128);
    }

    /// @notice All three powers with their admin bits.
    /// @return The union bitmap of every power.
    function allWithAdmin() internal pure returns (uint256) {
        return roleWithAdmin(Power.Banish) | roleWithAdmin(Power.Decree) | roleWithAdmin(Power.Dissolve);
    }

    /// @notice Root roles held by the Throne at genesis: registrar and parent control plus every power.
    /// @return The root role bitmap given to the Throne by the court constructor.
    function throneRootRoles() internal pure returns (uint256) {
        return RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_SET_PARENT | allWithAdmin();
    }

    /// @notice Token-level roles every vassal receives on their own name.
    ///         There is no admin bit, no unregister and no transfer right, so names are soulbound.
    /// @return The role bitmap granted to a vassal for their own name.
    function vassalRoles() internal pure returns (uint256) {
        return RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_SUBREGISTRY;
    }
}
