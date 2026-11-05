// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "@ens-v2/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens-v2/registry/interfaces/IPermissionedRegistry.sol";
import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";

import {Base} from "./Base.t.sol";
import {FealtyCourt} from "../src/FealtyCourt.sol";
import {Throne} from "../src/Throne.sol";
import {Power, Powers} from "../src/libraries/Powers.sol";

contract ThroneTest is Base {
    // ── genesis ────────────────────────────────────────────────────────

    function test_genesis_throneHoldsExactlyItsRoles() public view {
        assertTrue(court.hasRootRoles(Powers.throneRootRoles(), address(throne)));
        assertFalse(court.isEmancipated());
        assertEq(throne.powersRemaining(), 3);
        (IRegistry parent, string memory label) = court.getParent();
        assertEq(address(parent), address(realm));
        assertEq(label, "s1");
    }

    function test_genesis_revertsIfCourtGaveThroneNothing() public {
        FealtyCourt other = new FealtyCourt(labelStore, makeAddr("stranger"), Powers.throneRootRoles());
        Throne.Config memory c = _cfg();
        c.court = other;
        vm.expectRevert(Throne.GenesisInvariantViolated.selector);
        new Throne(c);
    }

    function test_genesis_revertsIfAnotherAccountAlsoHoldsAPower() public {
        // The test contract is the court's root account, then also grants the predicted Throne
        // the same roles, so two accounts hold every power. The Throne must refuse to start.
        FealtyCourt other = new FealtyCourt(
            labelStore,
            address(this),
            Powers.throneRootRoles() | RegistryRolesLib.ROLE_REGISTRAR_ADMIN | RegistryRolesLib.ROLE_SET_PARENT_ADMIN
        );
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        other.grantRootRoles(Powers.throneRootRoles(), predicted);
        Throne.Config memory c = _cfg();
        c.court = other;
        vm.expectRevert(Throne.GenesisInvariantViolated.selector);
        new Throne(c);
    }

    function test_constructor_rejectsBadConfig() public {
        Throne.Config memory c = _cfg();
        c.tyrant = address(0);
        vm.expectRevert(Throne.InvalidConfig.selector);
        new Throne(c);
    }

    // ── join ───────────────────────────────────────────────────────────

    function test_join_registersNameAndWritesBanner() public {
        _join(alice, "alice");
        assertEq(court.getOwner(_id("alice")), alice);
        assertEq(court.getResolver("alice"), address(bannerResolver));
        assertEq(_text(address(bannerResolver), "alice", "fealty.banner"), "banner of alice");
        assertEq(_text(address(bannerResolver), "alice", "fealty.joined"), "1000000");
        assertEq(throne.liveVassals(), 1);
        assertEq(court.getExpiry(_id("alice")), seasonEnd);
    }

    function test_join_emitsEvent() public {
        vm.expectEmit(true, false, false, true, address(throne));
        emit Throne.Joined(alice, "alice", "hi");
        vm.prank(alice);
        throne.join("alice", "hi");
    }

    function test_join_vassalGetsOnlyOwnNameRoles() public {
        _join(alice, "alice");
        uint256 r = court.roles(_id("alice"), alice);
        assertEq(r, Powers.vassalRoles());
        assertEq(r & RegistryRolesLib.ROLE_UNREGISTER, 0);
        assertEq(r & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN, 0);
    }

    function test_join_revertsOnDuplicateAndBadInput() public {
        _join(alice, "alice");
        vm.expectRevert(Throne.AlreadyJoined.selector);
        vm.prank(alice);
        throne.join("alice2", "x");

        string[7] memory bad = ["ab", "this-label-is-way-too-long", "-abc", "abc-", "ABC", "a_b", "sp ace"];
        for (uint256 i; i < bad.length; ++i) {
            vm.expectRevert(Throne.InvalidLabel.selector);
            vm.prank(bob);
            throne.join(bad[i], "x");
        }

        vm.expectRevert(Throne.BannerTooLong.selector);
        vm.prank(bob);
        throne.join("bobby", new string(141));
    }

    function test_join_labelTakenReverts() public {
        _join(alice, "alice");
        vm.expectRevert();
        vm.prank(bob);
        throne.join("alice", "x");
    }

    function test_join_outsideSeasonReverts() public {
        vm.warp(seasonEnd);
        vm.expectRevert(Throne.SeasonNotActive.selector);
        vm.prank(alice);
        throne.join("alice", "x");
    }

    function test_names_areSoulbound_beforeAndAfterEmancipation() public {
        _join(alice, "alice");
        uint256 tokenId = _tokenId("alice");

        // ENSv2 refuses safe transfers outright until the registry is emancipated
        vm.expectRevert(IPermissionedRegistry.TransferUnsafeUntilRegistryIsEmancipated.selector);
        vm.prank(alice);
        court.safeTransferFrom(alice, bob, tokenId, 1, "");

        // the unsafe path checks the token's transfer right, which vassals never get
        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.TransferDisallowed.selector, tokenId, alice));
        vm.prank(alice);
        court.unsafeTransfer(bob, tokenId, "");

        // even after every power is gone and the court is emancipated, the name stays soulbound
        vm.startPrank(tyrant);
        throne.concede(Power.Banish);
        throne.concede(Power.Decree);
        throne.concede(Power.Dissolve);
        vm.stopPrank();
        assertTrue(court.isEmancipated());
        tokenId = _tokenId("alice");
        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.TransferDisallowed.selector, tokenId, alice));
        vm.prank(alice);
        court.safeTransferFrom(alice, bob, tokenId, 1, "");
    }

    function test_setBanner() public {
        _join(alice, "alice");
        vm.prank(alice);
        throne.setBanner("new banner");
        assertEq(_text(address(bannerResolver), "alice", "fealty.banner"), "new banner");

        vm.expectRevert(Throne.NotVassal.selector);
        vm.prank(bob);
        throne.setBanner("x");

        vm.expectRevert(Throne.BannerTooLong.selector);
        vm.prank(alice);
        throne.setBanner(string(new bytes(141)));
    }

    // ── BANISH ─────────────────────────────────────────────────────────

    function test_banish_deletesNameAndBlocksRejoin() public {
        _joinAll();
        vm.prank(tyrant);
        throne.banish(alice);

        assertEq(court.getOwner(_id("alice")), address(0));
        assertEq(court.getResolver("alice"), address(0), "name no longer resolves");
        assertEq(uint8(court.getStatus(_id("alice"))), uint8(IPermissionedRegistry.Status.AVAILABLE));
        assertEq(throne.liveVassals(), 2);

        vm.expectRevert(Throne.BanishedThisSeason.selector);
        vm.prank(alice);
        throne.join("alice", "again");

        vm.expectRevert(Throne.NotVassal.selector);
        vm.prank(alice);
        throne.setBanner("x");
    }

    function test_banish_onlyTyrant() public {
        _joinAll();
        vm.expectRevert(Throne.NotTyrant.selector);
        vm.prank(alice);
        throne.banish(bob);
    }

    function test_banish_nonVassalReverts() public {
        vm.expectRevert(Throne.NotVassal.selector);
        vm.prank(tyrant);
        throne.banish(dave);
    }

    function test_banish_cooldown() public {
        _joinAll();
        vm.prank(tyrant);
        throne.banish(alice);
        assertEq(throne.cooldownRemaining(Power.Banish), COOLDOWN);

        vm.expectRevert(abi.encodeWithSelector(Throne.PowerOnCooldown.selector, Power.Banish, uint64(block.timestamp) + COOLDOWN));
        vm.prank(tyrant);
        throne.banish(bob);

        vm.warp(block.timestamp + COOLDOWN);
        assertEq(throne.cooldownRemaining(Power.Banish), 0);
        vm.prank(tyrant);
        throne.banish(bob);
    }

    function test_banish_removesActiveVote() public {
        _joinAll();
        vm.warp(block.timestamp + 1);
        uint256 id = _openBallot(Power.Decree);
        _vote(alice, id, true, 11);
        _vote(bob, id, false, 12);
        assertEq(throne.getBallot(id).yes, 1);

        vm.expectEmit(true, true, false, false, address(throne));
        emit Throne.VoteRemoved(id, alice);
        vm.prank(tyrant);
        throne.banish(alice);

        assertEq(throne.getBallot(id).yes, 0);
        assertEq(throne.voteOf(id, alice), 0);
        assertEq(throne.getBallot(id).no, 1);
    }

    function test_banish_removesActiveNoVote() public {
        _joinAll();
        vm.warp(block.timestamp + 1);
        uint256 id = _openBallot(Power.Decree);
        _vote(bob, id, false, 12);
        vm.prank(tyrant);
        throne.banish(bob);
        assertEq(throne.getBallot(id).no, 0);
    }

    // ── DECREE ─────────────────────────────────────────────────────────

    function test_decree_overwritesRecordAndVassalCanRestore() public {
        _join(alice, "alice");
        vm.prank(tyrant);
        throne.decree(alice, "ALICE IS A TRAITOR");

        assertEq(court.getResolver("alice"), address(decreeResolver));
        assertTrue(throne.isDecreed(alice));
        assertEq(_text(court.getResolver("alice"), "alice", "fealty.banner"), "ALICE IS A TRAITOR");

        // the vassal can undo it with their own token role, no Throne involved
        vm.prank(alice);
        court.setResolver(_id("alice"), address(bannerResolver));
        assertFalse(throne.isDecreed(alice));
        assertEq(_text(court.getResolver("alice"), "alice", "fealty.banner"), "banner of alice");
    }

    function test_decree_guards() public {
        _join(alice, "alice");
        vm.expectRevert(Throne.NotTyrant.selector);
        vm.prank(alice);
        throne.decree(alice, "x");

        vm.expectRevert(Throne.BannerTooLong.selector);
        vm.prank(tyrant);
        throne.decree(alice, string(new bytes(141)));

        vm.expectRevert(Throne.NotVassal.selector);
        vm.prank(tyrant);
        throne.decree(bob, "x");
    }

    // ── DISSOLVE ───────────────────────────────────────────────────────

    function test_dissolve_detachesHouse() public {
        _join(alice, "alice");
        IRegistry house = IRegistry(makeAddr("house"));
        vm.prank(alice);
        court.setSubregistry(_id("alice"), house);

        vm.prank(alice);
        throne.registerHouse(house);

        vm.prank(tyrant);
        throne.dissolve(alice);
        assertEq(address(court.getSubregistry("alice")), address(0));
    }

    function test_dissolve_withoutHouseReverts() public {
        _join(alice, "alice");
        vm.expectRevert(Throne.NoHouse.selector);
        vm.prank(tyrant);
        throne.dissolve(alice);
    }

    function test_registerHouse_mustMatchEns() public {
        _join(alice, "alice");
        vm.expectRevert(Throne.HouseMismatch.selector);
        vm.prank(alice);
        throne.registerHouse(IRegistry(makeAddr("fake")));

        vm.expectRevert(Throne.HouseMismatch.selector);
        vm.prank(alice);
        throne.registerHouse(IRegistry(address(0)));
    }

    function test_vassalCanDetachOwnHouseAnytime() public {
        _join(alice, "alice");
        vm.prank(alice);
        court.setSubregistry(_id("alice"), IRegistry(makeAddr("house")));
        vm.prank(alice);
        court.setSubregistry(_id("alice"), IRegistry(address(0)));
        assertEq(address(court.getSubregistry("alice")), address(0));
    }

    // ── tyrant powers vs season ────────────────────────────────────────

    function test_powers_revertOutsideSeason() public {
        _join(alice, "alice");
        vm.warp(seasonEnd);
        vm.expectRevert(Throne.SeasonNotActive.selector);
        vm.prank(tyrant);
        throne.banish(alice);
    }

    function test_powers_independentCooldowns() public {
        _joinAll();
        vm.startPrank(tyrant);
        throne.banish(alice);
        throne.decree(bob, "x"); // different power, no cooldown shared
        vm.stopPrank();
    }

    // ── concede ────────────────────────────────────────────────────────

    function test_concede_stripsAndCancelsBallotAndBlocksNewOnes() public {
        _joinAll();
        vm.warp(block.timestamp + 1);
        uint256 id = _openBallot(Power.Banish);

        vm.expectEmit(true, true, false, false, address(throne));
        emit Throne.PowerStripped(Power.Dissolve, 0);
        vm.prank(tyrant);
        throne.concede(Power.Dissolve);

        assertFalse(throne.powerAlive(Power.Dissolve));
        assertEq(throne.activeBallotId(), 0);
        assertTrue(throne.getBallot(id).resolved);
        assertFalse(throne.getBallot(id).passed);

        vm.expectRevert(abi.encodeWithSelector(Throne.ImmunePeriod.selector, uint64(block.timestamp) + IMMUNITY));
        vm.prank(keeper);
        throne.openBallot(Power.Banish, bytes32(0), 3);

        vm.warp(block.timestamp + IMMUNITY);
        _openBallot(Power.Banish);
    }

    function test_concede_guards() public {
        vm.expectRevert(Throne.NotTyrant.selector);
        throne.concede(Power.Banish);

        vm.prank(tyrant);
        throne.concede(Power.Banish);
        vm.expectRevert(abi.encodeWithSelector(Throne.PowerGone.selector, Power.Banish));
        vm.prank(tyrant);
        throne.concede(Power.Banish);
    }

    function test_concede_twoPowersIsRebelWin_threeIsEmancipated() public {
        vm.startPrank(tyrant);
        throne.concede(Power.Banish);
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.Undecided));
        throne.concede(Power.Decree);
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.RebelsWin));
        throne.concede(Power.Dissolve);
        vm.stopPrank();
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.Emancipated));
        assertTrue(court.isEmancipated());
    }

    // ── ballots (keeper side) ──────────────────────────────────────────

    function test_openBallot_guards() public {
        vm.expectRevert(Throne.NotKeeper.selector);
        throne.openBallot(Power.Banish, bytes32(0), 3);

        vm.expectRevert(Throne.NoElectorate.selector);
        vm.prank(keeper);
        throne.openBallot(Power.Banish, bytes32(0), 3);

        _joinAll();
        _openBallot(Power.Banish);
        vm.expectRevert(Throne.BallotAlreadyActive.selector);
        vm.prank(keeper);
        throne.openBallot(Power.Decree, bytes32(0), 3);
    }

    function test_openBallot_mustFitInSeason() public {
        _joinAll();
        vm.warp(seasonEnd - BALLOT_LEN + 1);
        vm.expectRevert(Throne.BallotTooLate.selector);
        vm.prank(keeper);
        throne.openBallot(Power.Banish, bytes32(0), 3);
    }

    function test_openBallot_strippedPowerReverts() public {
        vm.prank(tyrant);
        throne.concede(Power.Banish);
        _joinAll();
        vm.warp(block.timestamp + IMMUNITY);
        vm.expectRevert(abi.encodeWithSelector(Throne.PowerGone.selector, Power.Banish));
        vm.prank(keeper);
        throne.openBallot(Power.Banish, bytes32(0), 3);
    }

    function test_openBallot_recordsManifestoAndElectorate() public {
        _joinAll();
        uint256 id = _openBallot(Power.Dissolve);
        Throne.Ballot memory b = throne.getBallot(id);
        assertEq(uint8(b.power), uint8(Power.Dissolve));
        assertEq(b.manifestoKey, keccak256("manifesto"));
        assertEq(b.pledges, 3);
        assertEq(b.electorate, 3);
        assertEq(b.deadline, block.timestamp + BALLOT_LEN);
        assertEq(throne.ballotCount(), 1);
    }

    // ── finalize ───────────────────────────────────────────────────────

    function test_finalize_tyrantWinsWhenFewerThanTwoStripped() public {
        vm.expectRevert(Throne.SeasonNotOver.selector);
        throne.finalize();

        vm.prank(tyrant);
        throne.concede(Power.Banish); // only one stripped
        vm.warp(seasonEnd);
        throne.finalize();
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.TyrantWins));
        assertTrue(throne.finalized());

        vm.expectRevert(Throne.AlreadyFinalized.selector);
        throne.finalize();
    }

    function test_finalize_keepsRebelsWin() public {
        vm.startPrank(tyrant);
        throne.concede(Power.Banish);
        throne.concede(Power.Decree);
        vm.stopPrank();
        vm.warp(seasonEnd);
        throne.finalize();
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.RebelsWin));
    }

    function test_finalize_blockedWhileBallotPending() public {
        _joinAll();
        uint256 id = _openBallot(Power.Banish);
        vm.warp(seasonEnd);
        vm.expectRevert(Throne.BallotPending.selector);
        throne.finalize();
        throne.resolve(id);
        throne.finalize();
    }

    // ── helpers ────────────────────────────────────────────────────────

    function _tokenId(string memory label) internal view returns (uint256) {
        return court.getTokenId(_id(label));
    }

    function _cfg() internal view returns (Throne.Config memory c) {
        c = Throne.Config({
            court: court,
            worldId: world,
            tyrant: tyrant,
            keeper: keeper,
            attester: attester,
            bannerResolver: bannerResolver,
            decreeResolver: decreeResolver,
            realm: realm,
            seasonLabel: "s1",
            courtDnsSuffix: SUFFIX,
            externalNullifierHash: EXT_NULL,
            seasonStart: seasonStart,
            seasonEnd: seasonEnd,
            powerCooldown: COOLDOWN,
            ballotDuration: BALLOT_LEN,
            concedeImmunity: IMMUNITY,
            minYesVotes: 1
        });
    }
}
