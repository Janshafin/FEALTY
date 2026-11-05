// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PermissionedRegistry} from "@ens-v2/registry/PermissionedRegistry.sol";
import {ILabelStore} from "@ens-v2/utils/interfaces/ILabelStore.sol";

/// @title FealtyRealm
/// @notice The registry behind `<realm>.eth`. Each season is a label in this registry whose
///         subregistry is that season's court. Unmodified ENSv2 `PermissionedRegistry`.
contract FealtyRealm is PermissionedRegistry {
    /// @param labelStore The shared ENSv2 label database.
    /// @param rootAccount Account granted the root roles.
    /// @param rootRoles Role bitmap granted to `rootAccount`.
    constructor(ILabelStore labelStore, address rootAccount, uint256 rootRoles)
        PermissionedRegistry(labelStore, rootAccount, rootRoles)
    {}
}
