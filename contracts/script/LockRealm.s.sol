// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {IPermissionedRegistry} from "@ens-v2/registry/interfaces/IPermissionedRegistry.sol";
import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";
import {LibLabel} from "@ens-v2/utils/LibLabel.sol";

import {Config} from "./Config.s.sol";

/// @title LockRealm
/// @notice IRREVERSIBLE. Revokes the deployer's right to change the realm name's subregistry (and the
///         right to grant it back). After this nobody, including the FEALTY developers, can point
///         `<realm>.eth` at a different registry, so a season's court can never be swapped out.
///         It refuses to run unless `CONFIRM_IRREVERSIBLE_LOCK=yes`.
contract LockRealm is Config {
    function run() external {
        require(
            keccak256(bytes(vm.envOr("CONFIRM_IRREVERSIBLE_LOCK", string("")))) == keccak256("yes"),
            "set CONFIRM_IRREVERSIBLE_LOCK=yes to confirm this cannot be undone"
        );
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address deployer = vm.addr(pk);
        IPermissionedRegistry eth = IPermissionedRegistry(ensAddress("ETHRegistry"));
        string memory label = vm.parseJsonString(vm.readFile(realmFile()), ".label");
        uint256 id = LibLabel.id(label);

        vm.startBroadcast(pk);
        eth.revokeRoles(id, RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN, deployer);
        vm.stopBroadcast();

        console.log("Locked. Realm registry for", label, "can never change.");
    }
}
