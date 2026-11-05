// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PermissionedRegistry} from "@ens-v2/registry/PermissionedRegistry.sol";
import {ILabelStore} from "@ens-v2/utils/interfaces/ILabelStore.sol";

/// @title FealtyCourt
/// @notice A royal court in FEALTY: an unmodified ENSv2 `PermissionedRegistry`.
///         Every vassal is a real ENSv2 subname (`<vassal>.<court>.fealty.eth`) and every
///         power the ruler holds is a real Enhanced Access Control root role.
///
///         Deliberately NOT upgradeable and NOT overriding any role logic: the political
///         guarantees of the game are exactly the guarantees of ENSv2's own access control.
///         In particular, once the Throne revokes a power together with its admin bit,
///         nobody (not the Throne, not the tyrant, not the FEALTY developers) can restore it.
contract FealtyCourt is PermissionedRegistry {
    constructor(ILabelStore labelStore, address throne, uint256 rootRoles)
        PermissionedRegistry(labelStore, throne, rootRoles)
    {}
}
