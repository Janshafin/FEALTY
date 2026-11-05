// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "@ens-v2/registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";

import {Base} from "./Base.t.sol";
import {Throne} from "../src/Throne.sol";
import {Power, Powers} from "../src/libraries/Powers.sol";

/// @notice The headline claim of FEALTY: once a revolution strips a power, nobody can ever restore it.
contract IrreversibilityTest is Base {
    function setUp() public override {
        super.setUp();
        _joinAll();
    }

    function _powers() internal pure returns (Power[3] memory p) {
        p = [Power.Banish, Power.Decree, Power.Dissolve];
    }

    function _soleHolderCount(uint256 bit) internal view returns (uint256) {
        (uint256 counts,) = court.getAssigneeCount(0, bit);
        return (counts / bit) & 0xF;
    }

    // ── the role is gone from ENS itself ───────────────────────────────

    function test_strippedPower_leavesNoHolderAnywhere() public {
        Power[3] memory ps = _powers();
        for (uint256 i; i < 3; ++i) {
            Power p = ps[i];
            uint256 role = Powers.role(p);
            assertEq(_soleHolderCount(role), 1, "held before");
            assertEq(_soleHolderCount(role << 128), 1, "admin held before");

            _strip(p);

            assertFalse(court.hasRootRoles(role, address(throne)));
            assertFalse(court.hasRootRoles(role << 128, address(throne)));
            assertEq(_soleHolderCount(role), 0, "no assignee left");
            assertEq(_soleHolderCount(role << 128), 0, "no admin left");
            assertFalse(throne.powerAlive(p));
        }
    }

    function test_strippedPower_tyrantAndThroneCannotUseIt() public {
        _strip(Power.Banish);
        vm.expectRevert(abi.encodeWithSelector(Throne.PowerGone.selector, Power.Banish));
        vm.prank(tyrant);
        throne.banish(alice);

        // Even the Throne calling the court directly is refused by ENSv2 itself.
        vm.expectRevert();
        vm.prank(address(throne));
        court.unregister(_id("alice"));
    }

    // ── nobody can grant it back ───────────────────────────────────────

    function test_noOneCanRegrant_namedCallers() public {
        address[6] memory callers = [address(throne), tyrant, keeper, alice, address(this), address(court)];
        Power[3] memory ps = _powers();
        for (uint256 i; i < 3; ++i) {
            _strip(ps[i]);
            uint256 role = Powers.role(ps[i]);
            for (uint256 c; c < callers.length; ++c) {
                _assertCannotRegrant(callers[c], role, callers[c]);
                _assertCannotRegrant(callers[c], role | (role << 128), alice);
            }
        }
    }

    function testFuzz_noOneCanRegrant(address caller, address to, uint8 which, bool withAdmin) public {
        Power p = Power(which % 3);
        _strip(p);
        uint256 role = Powers.role(p);
        _assertCannotRegrant(caller, withAdmin ? role | (role << 128) : role, to);
        assertFalse(court.hasRootRoles(role, to));
    }

    function test_noOneCanRegrant_throughTokenRoles() public {
        _strip(Power.Banish);
        uint256 id = _id("alice");
        // A vassal cannot escalate to UNREGISTER on their own token, strip or no strip.
        vm.expectRevert();
        vm.prank(alice);
        court.grantRoles(id, RegistryRolesLib.ROLE_UNREGISTER, alice);
        vm.expectRevert();
        vm.prank(address(throne));
        court.grantRoles(id, RegistryRolesLib.ROLE_UNREGISTER, address(throne));
    }

    function test_revokingAgainIsHarmless() public {
        _strip(Power.Decree);
        // The Throne no longer has the admin bit, so even a second revocation is refused.
        vm.expectRevert();
        vm.prank(address(throne));
        court.revokeRootRoles(Powers.roleWithAdmin(Power.Decree), address(throne));
    }

    // ── other powers and the rest of the court are untouched ───────────

    function test_strippingOnePowerLeavesOthersAndRegistrarIntact() public {
        _strip(Power.Decree);
        assertTrue(throne.powerAlive(Power.Banish));
        assertTrue(throne.powerAlive(Power.Dissolve));
        assertTrue(court.hasRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(throne)));
        assertFalse(court.isEmancipated());
        _join(dave, "dave"); // joining still works
    }

    // ── emancipation ───────────────────────────────────────────────────

    function test_allThreeStripped_courtIsEmancipated_vassalsKeepTheirOwnRoles() public {
        Power[3] memory ps = _powers();
        for (uint256 i; i < 3; ++i) {
            assertFalse(court.isEmancipated());
            _strip(ps[i]);
        }
        assertTrue(court.isEmancipated());
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.Emancipated));

        // A vassal still rules their own name: this is what ENS emancipation means.
        vm.prank(alice);
        court.setResolver(_id("alice"), address(decreeResolver));
        vm.prank(alice);
        court.setSubregistry(_id("alice"), IRegistry(makeAddr("house")));

        // And the Tyrant can do nothing to them.
        vm.expectRevert(abi.encodeWithSelector(Throne.PowerGone.selector, Power.Decree));
        vm.prank(tyrant);
        throne.decree(alice, "x");
        vm.expectRevert(abi.encodeWithSelector(Throne.PowerGone.selector, Power.Dissolve));
        vm.prank(tyrant);
        throne.dissolve(alice);
    }

    function test_emancipation_cannotBeUndoneByRegistering() public {
        for (uint256 i; i < 3; ++i) {
            _strip(_powers()[i]);
        }
        // Registering new vassals grants only the constant vassal roles on the new token.
        _join(dave, "dave");
        assertEq(court.roles(_id("dave"), dave), Powers.vassalRoles());
        assertTrue(court.isEmancipated());
    }

    // ── helpers ────────────────────────────────────────────────────────

    function _assertCannotRegrant(address caller, uint256 bitmap, address to) internal {
        vm.expectRevert();
        vm.prank(caller);
        court.grantRootRoles(bitmap, to);
    }
}
