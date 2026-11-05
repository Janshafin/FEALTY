// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";

import {ByteHasher} from "../src/libraries/ByteHasher.sol";
import {Power, Powers} from "../src/libraries/Powers.sol";
import {VoteSignal} from "../src/libraries/VoteSignal.sol";

/// @notice Pins the values the TypeScript packages duplicate. The same literals are asserted in
///         `packages/shared`, so a drift on either side fails a test instead of breaking a vote.
contract ConstantsTest is Test {
    function test_roleBitsMatchTypeScript() public pure {
        assertEq(Powers.role(Power.Banish), 1 << 12);
        assertEq(Powers.role(Power.Decree), 1 << 24);
        assertEq(Powers.role(Power.Dissolve), 1 << 20);
        assertEq(Powers.role(Power.Banish), RegistryRolesLib.ROLE_UNREGISTER);
        assertEq(Powers.role(Power.Decree), RegistryRolesLib.ROLE_SET_RESOLVER);
        assertEq(Powers.role(Power.Dissolve), RegistryRolesLib.ROLE_SET_SUBREGISTRY);
        assertEq(Powers.roleWithAdmin(Power.Banish), RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_UNREGISTER_ADMIN);
    }

    function test_signalHashVectorMatchesTypeScript() public pure {
        bytes memory signal = VoteSignal.encode(0xAbcd000000000000000000000000000000001234, 7, true);
        assertEq(string(signal), "0xabcd000000000000000000000000000000001234:7:1");
        assertEq(ByteHasher.hashToField(signal), 0xe24372edb0efef4755ce4127da8b81d1485db66fabfbc5a510ed512d6f8ffa);
    }
}
