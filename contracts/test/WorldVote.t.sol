// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {Base, MockWorldID} from "./Base.t.sol";
import {Throne} from "../src/Throne.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {ByteHasher} from "../src/libraries/ByteHasher.sol";
import {Power} from "../src/libraries/Powers.sol";
import {VoteSignal} from "../src/libraries/VoteSignal.sol";

contract WorldVoteTest is Base {
    uint256 internal constant ROOT = 0xABCDEF;

    // ── the proof is verified with exactly the right arguments ─────────

    function test_vote_passesExactArgumentsToWorldId() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        uint256 signalHash = ByteHasher.hashToField(VoteSignal.encode(alice, id, true));
        world.expect(ROOT, signalHash, 777, EXT_NULL);

        uint256[8] memory proof;
        vm.expectEmit(true, true, false, true, address(throne));
        emit Throne.Voted(id, alice, true, 777);
        vm.prank(alice);
        throne.vote(id, true, ROOT, 777, proof);
        assertEq(throne.voteOf(id, alice), 1);
        assertEq(throne.getBallot(id).yes, 1);
    }

    function test_vote_signalBindsVoterBallotAndChoice() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        // A proof generated for a "no" cannot be replayed as a "yes".
        uint256 noSignal = ByteHasher.hashToField(VoteSignal.encode(alice, id, false));
        world.expect(ROOT, noSignal, 777, EXT_NULL);

        uint256[8] memory proof;
        vm.expectRevert(MockWorldID.UnexpectedArguments.selector);
        vm.prank(alice);
        throne.vote(id, true, ROOT, 777, proof);

        // And a proof generated for alice cannot be used by bob.
        uint256 aliceSignal = ByteHasher.hashToField(VoteSignal.encode(alice, id, true));
        world.expect(ROOT, aliceSignal, 777, EXT_NULL);
        vm.expectRevert(MockWorldID.UnexpectedArguments.selector);
        vm.prank(bob);
        throne.vote(id, true, ROOT, 777, proof);
    }

    function test_signal_format() public pure {
        bytes memory sig = VoteSignal.encode(address(0xAbcd000000000000000000000000000000001234), 7, true);
        assertEq(string(sig), "0xabcd000000000000000000000000000000001234:7:1");
        assertEq(string(VoteSignal.encode(address(1), 12, false)), "0x0000000000000000000000000000000000000001:12:0");
    }

    function test_vote_invalidProofReverts() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        world.setShouldFail(true);
        vm.expectRevert(MockWorldID.InvalidProof.selector);
        _vote(alice, id, true, 1);
        assertEq(throne.voteOf(id, alice), 0);
        assertEq(throne.getBallot(id).yes, 0);
    }

    // ── one human, one vote ────────────────────────────────────────────

    function test_vote_sameAddressTwiceReverts() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        _vote(alice, id, true, 1);
        vm.expectRevert(Throne.AlreadyVoted.selector);
        _vote(alice, id, false, 2);
    }

    function test_vote_sameNullifierFromSecondWalletReverts() public {
        // One human controlling two vassal wallets produces the same nullifier twice.
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        _vote(alice, id, true, 99);
        vm.expectRevert(Throne.NullifierUsed.selector);
        _vote(bob, id, true, 99);
        assertEq(throne.getBallot(id).yes, 1);
    }

    function test_vote_nullifierIsScopedPerBallot() public {
        _joinAll();
        uint256 id1 = _openBallot(Power.Decree);
        _vote(alice, id1, false, 5);
        vm.warp(block.timestamp + BALLOT_LEN);
        throne.resolve(id1); // fails: no yes votes

        // The same human (same nullifier) may vote again in a later ballot.
        uint256 id2 = _openBallot(Power.Banish);
        _vote(alice, id2, false, 5);
        assertEq(throne.voteOf(id2, alice), -1);
    }

    // ── who may vote ───────────────────────────────────────────────────

    function test_vote_nonVassalReverts() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        vm.expectRevert(Throne.NotVassal.selector);
        _vote(dave, id, true, 1);
    }

    function test_vote_joinedAfterBallotOpenedReverts() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        vm.warp(block.timestamp + 1);
        _join(dave, "dave");
        vm.expectRevert(Throne.JoinedTooLate.selector);
        _vote(dave, id, true, 1);
    }

    function test_vote_joinedInSameSecondAsBallotReverts() public {
        _join(alice, "alice");
        _join(bob, "bob");
        uint256 id = _openBallot(Power.Decree); // same timestamp as the joins
        vm.expectRevert(Throne.JoinedTooLate.selector);
        _vote(alice, id, true, 1);
    }

    function test_vote_banishedVassalCannotVote() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        vm.prank(tyrant);
        throne.banish(alice);
        vm.expectRevert(Throne.NotVassal.selector);
        _vote(alice, id, true, 1);
    }

    function test_vote_rejoiningAfterBanishCannotCircumventVoteBan() public {
        _joinAll();
        vm.prank(tyrant);
        throne.banish(alice);
        vm.expectRevert(Throne.BanishedThisSeason.selector);
        _join(alice, "alice2");
    }

    function test_vote_ballotWindow() public {
        _joinAll();
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotNotActive.selector, 0));
        _vote(alice, 0, true, 1);
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotNotActive.selector, 1));
        _vote(alice, 1, true, 1);

        uint256 id = _openBallot(Power.Decree);
        vm.warp(block.timestamp + BALLOT_LEN);
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotClosed.selector, id));
        _vote(alice, id, true, 1);
    }

    function test_isEligible() public {
        _joinAll();
        assertFalse(throne.isEligible(alice, 1));
        uint256 id = _openBallot(Power.Decree);
        assertTrue(throne.isEligible(alice, id));
        assertFalse(throne.isEligible(dave, id));
        _vote(alice, id, true, 1);
        assertFalse(throne.isEligible(alice, id), "already voted");
        vm.warp(block.timestamp + BALLOT_LEN);
        assertFalse(throne.isEligible(bob, id), "closed");
    }

    // ── resolving ──────────────────────────────────────────────────────

    function test_resolve_beforeDeadlineWithoutMajorityReverts() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        _vote(alice, id, true, 1); // 1 of 3 is not a majority
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotStillOpen.selector, id));
        throne.resolve(id);
    }

    function test_resolve_earlyOnMajorityStripsPower() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        _vote(alice, id, true, 1);
        _vote(bob, id, true, 2);
        vm.expectEmit(true, true, false, false, address(throne));
        emit Throne.PowerStripped(Power.Decree, id);
        throne.resolve(id);

        assertFalse(throne.powerAlive(Power.Decree));
        assertEq(throne.powersRemaining(), 2);
        assertEq(throne.activeBallotId(), 0);
        assertTrue(throne.getBallot(id).passed);
        assertTrue(throne.getBallot(id).resolved);

        vm.expectRevert(abi.encodeWithSelector(Throne.PowerGone.selector, Power.Decree));
        vm.prank(tyrant);
        throne.decree(carol, "x");
    }

    function test_resolve_atDeadlinePassesWithPlurality() public {
        _joinAll();
        uint256 id = _openBallot(Power.Dissolve);
        _vote(alice, id, true, 1);
        _vote(bob, id, false, 2);
        _vote(carol, id, true, 3);
        // 2 yes of 3 triggered early eligibility; resolve either way
        throne.resolve(id);
        assertFalse(throne.powerAlive(Power.Dissolve));
    }

    function test_resolve_tieFails() public {
        _joinAll();
        uint256 id = _openBallot(Power.Banish);
        _vote(alice, id, true, 1);
        _vote(bob, id, false, 2);
        vm.warp(block.timestamp + BALLOT_LEN);
        throne.resolve(id);
        assertTrue(throne.powerAlive(Power.Banish));
        assertFalse(throne.getBallot(id).passed);
        assertTrue(throne.getBallot(id).resolved);
        assertEq(throne.activeBallotId(), 0);
    }

    function test_resolve_noVotesFails() public {
        _joinAll();
        uint256 id = _openBallot(Power.Banish);
        vm.warp(block.timestamp + BALLOT_LEN);
        throne.resolve(id);
        assertTrue(throne.powerAlive(Power.Banish));
    }

    function test_resolve_unknownOrFinishedBallotReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotNotActive.selector, 0));
        throne.resolve(0);
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotNotActive.selector, 5));
        throne.resolve(5);

        _joinAll();
        uint256 id = _openBallot(Power.Banish);
        vm.warp(block.timestamp + BALLOT_LEN);
        throne.resolve(id);
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotNotActive.selector, id));
        throne.resolve(id);
    }

    function test_banishingRingleaderBeforeResolveFlipsTheResult() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        _vote(alice, id, true, 1);
        _vote(bob, id, true, 2);
        // The Tyrant banishes a yes voter before anyone resolves: the majority is gone.
        vm.prank(tyrant);
        throne.banish(alice);
        vm.expectRevert(abi.encodeWithSelector(Throne.BallotStillOpen.selector, id));
        throne.resolve(id);
        vm.warp(block.timestamp + BALLOT_LEN);
        throne.resolve(id); // 1 yes, 0 no, min 1: still passes at deadline
        assertFalse(throne.powerAlive(Power.Decree));
    }

    // ── outcomes ───────────────────────────────────────────────────────

    function test_outcome_twoStrippedIsRebelsWin_threeIsEmancipated() public {
        _joinAll();
        _strip(Power.Decree);
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.Undecided));
        _strip(Power.Dissolve);
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.RebelsWin));
        assertFalse(court.isEmancipated());
        _strip(Power.Banish);
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.Emancipated));
        assertTrue(court.isEmancipated());
        assertEq(throne.powersRemaining(), 0);
    }

    function test_outcome_failedBallotsDoNotChangeOutcome() public {
        _joinAll();
        uint256 id = _openBallot(Power.Banish);
        vm.warp(block.timestamp + BALLOT_LEN);
        throne.resolve(id);
        assertEq(uint8(throne.outcome()), uint8(Throne.Outcome.Undecided));
    }

    // ── attested mode (fallback) ───────────────────────────────────────

    function test_attested_validSignatureCounts() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        uint256 expiry = block.timestamp + 60;
        bytes memory sig = _attest(alice, id, true, 42, expiry, attesterPk);
        vm.prank(alice);
        throne.voteAttested(id, true, 42, expiry, sig);
        assertEq(throne.getBallot(id).yes, 1);
        assertEq(throne.voteOf(id, alice), 1);
    }

    function test_attested_rejectsBadSignerWrongVoterExpiredAndReplay() public {
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        uint256 expiry = block.timestamp + 60;

        bytes memory forged = _attest(alice, id, true, 42, expiry, 0xBAD);
        vm.expectRevert(Throne.BadAttestation.selector);
        vm.prank(alice);
        throne.voteAttested(id, true, 42, expiry, forged);

        bytes memory forAlice = _attest(alice, id, true, 42, expiry, attesterPk);
        vm.expectRevert(Throne.BadAttestation.selector);
        vm.prank(bob);
        throne.voteAttested(id, true, 42, expiry, forAlice);

        vm.expectRevert(Throne.BadAttestation.selector); // flipping the choice invalidates it
        vm.prank(alice);
        throne.voteAttested(id, false, 42, expiry, forAlice);

        vm.prank(alice);
        throne.voteAttested(id, true, 42, expiry, forAlice);
        vm.expectRevert(Throne.AlreadyVoted.selector);
        vm.prank(alice);
        throne.voteAttested(id, true, 42, expiry, forAlice);

        bytes memory forBob = _attest(bob, id, true, 42, expiry, attesterPk); // same nullifier
        vm.expectRevert(Throne.NullifierUsed.selector);
        vm.prank(bob);
        throne.voteAttested(id, true, 42, expiry, forBob);

        bytes memory old = _attest(carol, id, true, 43, expiry, attesterPk);
        vm.warp(expiry + 1);
        vm.expectRevert(Throne.AttestationExpired.selector);
        vm.prank(carol);
        throne.voteAttested(id, true, 43, expiry, old);
    }

    function test_modes_canBeDisabled() public {
        // attested-only deployment: on-chain vote is disabled
        _deploy(address(0), attester);
        _joinAll();
        uint256 id = _openBallot(Power.Decree);
        uint256[8] memory proof;
        vm.expectRevert(Throne.OnchainModeDisabled.selector);
        vm.prank(alice);
        throne.vote(id, true, 1, 1, proof);

        // on-chain-only deployment: attested vote is disabled
        _deploy(address(world), address(0));
        _joinAll();
        id = _openBallot(Power.Decree);
        vm.expectRevert(Throne.AttestedModeDisabled.selector);
        vm.prank(alice);
        throne.voteAttested(id, true, 1, block.timestamp + 1, "");
    }

    function test_constructor_requiresAtLeastOneMode() public {
        Throne.Config memory c = Throne.Config({
            court: court,
            worldId: IWorldID(address(0)),
            tyrant: tyrant,
            keeper: keeper,
            attester: address(0),
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
        vm.expectRevert(Throne.InvalidConfig.selector);
        new Throne(c);
    }

    // ── helpers ────────────────────────────────────────────────────────

    function _attest(address voter, uint256 id, bool support, uint256 nullifier, uint256 expiry, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(throne.ATTEST_TYPEHASH(), voter, id, support, nullifier, expiry));
        (, string memory name, string memory version, uint256 chainId, address verifying,,) = throne.eip712Domain();
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifying
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, MessageHashUtils.toTypedDataHash(domain, structHash));
        return abi.encodePacked(r, s, v);
    }
}
