// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IRegistry} from "@ens-v2/registry/interfaces/IRegistry.sol";
import {ITextSetter} from "@ens-v2/resolver/interfaces/setters/ITextSetter.sol";
import {LibLabel} from "@ens-v2/utils/LibLabel.sol";

import {FealtyCourt} from "./FealtyCourt.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher} from "./libraries/ByteHasher.sol";
import {Power, Powers} from "./libraries/Powers.sol";
import {VoteSignal} from "./libraries/VoteSignal.sol";

/// @title Throne
/// @notice The rules of one FEALTY season. The Throne is the only holder of the court registry's
///         root roles. The Tyrant exercises three powers through it, and each power is a real ENSv2
///         role. A passed revolution makes the Throne revoke that role together with its admin
///         bit from itself, so nobody (the Tyrant, the Throne, the FEALTY developers) can ever
///         restore it. Eligibility to vote is holding a live vassal name, and every vote carries a
///         World ID proof so that one human gets one ballot.
/// @dev There is deliberately no owner, no pause and no upgrade path.
contract Throne is EIP712 {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    /// @notice Final result of a season.
    enum Outcome {
        Undecided, // season still running, fewer than two powers stripped
        RebelsWin, // at least two powers stripped
        TyrantWins, // season ended with two or more powers intact
        Emancipated // every power stripped and the court reports itself emancipated
    }

    /// @notice A subject of the court.
    struct Vassal {
        string label;
        uint64 joinedAt;
        bool banished;
    }

    /// @notice A revolution ballot.
    struct Ballot {
        Power power;
        bytes32 manifestoKey;
        uint32 pledges;
        uint64 openedAt;
        uint64 deadline;
        uint32 electorate;
        uint32 yes;
        uint32 no;
        bool resolved;
        bool passed;
    }

    /// @notice Everything fixed at deployment.
    struct Config {
        FealtyCourt court;
        IWorldID worldId;
        address tyrant;
        address keeper;
        address attester;
        ITextSetter bannerResolver;
        ITextSetter decreeResolver;
        IRegistry realm;
        string seasonLabel;
        bytes courtDnsSuffix;
        uint256 externalNullifierHash;
        uint64 seasonStart;
        uint64 seasonEnd;
        uint64 powerCooldown;
        uint64 ballotDuration;
        uint64 concedeImmunity;
        uint32 minYesVotes;
    }

    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    /// @notice World ID group for Orb-verified humans (legacy on-chain path).
    uint256 public constant GROUP_ID = 1;
    /// @notice Maximum banner or proclamation length in bytes.
    uint256 public constant MAX_BANNER_BYTES = 140;
    /// @notice Text record key that carries a vassal's banner.
    string public constant BANNER_KEY = "fealty.banner";
    /// @notice Text record key that carries a vassal's join timestamp.
    string public constant JOINED_KEY = "fealty.joined";
    /// @notice EIP-712 type hash of an attested vote.
    bytes32 public constant ATTEST_TYPEHASH =
        keccak256("Attest(address voter,uint256 ballotId,bool support,uint256 nullifierHash,uint256 expiry)");

    ////////////////////////////////////////////////////////////////////////
    // Immutables
    ////////////////////////////////////////////////////////////////////////

    /// @notice The season's court registry.
    FealtyCourt public immutable court;
    /// @notice World ID router, or the zero address when only attested voting is enabled.
    IWorldID public immutable worldId;
    /// @notice The only account allowed to use the powers.
    address public immutable tyrant;
    /// @notice The only account allowed to open ballots. It affects liveness only.
    address public immutable keeper;
    /// @notice Signer of attested votes, or the zero address when attested voting is disabled.
    address public immutable attester;
    /// @notice Resolver shared by every vassal, carrying their banners.
    ITextSetter public immutable bannerResolver;
    /// @notice Resolver a decreed vassal is pointed at, carrying the Tyrant's proclamation.
    ITextSetter public immutable decreeResolver;
    /// @notice World ID external nullifier hash for the voting action.
    uint256 public immutable externalNullifierHash;
    /// @notice Season start timestamp.
    uint64 public immutable seasonStart;
    /// @notice Season end timestamp. Vassal names expire here.
    uint64 public immutable seasonEnd;
    /// @notice Minimum seconds between uses of the same power.
    uint64 public immutable powerCooldown;
    /// @notice Length of a ballot in seconds.
    uint64 public immutable ballotDuration;
    /// @notice Seconds without new ballots after the Tyrant concedes a power.
    uint64 public immutable concedeImmunity;
    /// @notice Minimum yes votes for any revolution to pass.
    uint32 public immutable minYesVotes;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    /// @notice DNS-encoded name of the court, for example `s1.fealty.eth`, including the root byte.
    bytes public courtDnsSuffix;
    /// @notice Vassals by address. A record persists after banishment.
    mapping(address account => Vassal) public vassals;
    /// @notice Number of vassals who joined and have not been banished.
    uint32 public liveVassals;
    /// @notice Last time each power was used.
    mapping(Power power => uint64) public lastUsed;
    /// @notice The active ballot id, or zero.
    uint256 public activeBallotId;
    /// @notice Earliest time a new ballot may open after a concession.
    uint64 public immuneUntil;
    /// @notice The current outcome.
    Outcome public outcome;
    /// @notice Whether `finalize` has run.
    bool public finalized;

    /// @dev Ballots by id. Index zero is a placeholder so that zero means "none".
    Ballot[] private _ballots;
    /// @dev Vote cast by an address in a ballot: 1 yes, -1 no, 0 none.
    mapping(uint256 ballotId => mapping(address voter => int8)) private _voteOf;
    /// @dev Nullifiers used in a ballot.
    mapping(uint256 ballotId => mapping(uint256 nullifier => bool)) private _nullifierUsed;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    /// @notice A vassal joined the court.
    event Joined(address indexed vassal, string label, string banner);
    /// @notice A vassal changed their banner.
    event BannerSet(address indexed vassal, string label, string banner);
    /// @notice A vassal's house (sub-court) was recorded.
    event HouseRegistered(address indexed vassal, string label, address house);
    /// @notice The Tyrant banished a vassal.
    event Banished(address indexed vassal, string label);
    /// @notice The Tyrant decreed over a vassal.
    event Decreed(address indexed vassal, string label, string proclamation);
    /// @notice The Tyrant dissolved a vassal's house.
    event Dissolved(address indexed vassal, string label, address house);
    /// @notice A ballot opened.
    event BallotOpened(
        uint256 indexed ballotId, Power power, bytes32 manifestoKey, uint32 pledges, uint64 deadline, uint32 electorate
    );
    /// @notice A vote was cast.
    event Voted(uint256 indexed ballotId, address indexed voter, bool support, uint256 nullifierHash);
    /// @notice A vote was removed because the voter was banished.
    event VoteRemoved(uint256 indexed ballotId, address indexed voter);
    /// @notice A ballot finished.
    event BallotResolved(uint256 indexed ballotId, bool passed, uint32 yes, uint32 no);
    /// @notice A ballot was cancelled by a concession.
    event BallotCancelled(uint256 indexed ballotId);
    /// @notice A power was permanently stripped. The ballot id is zero for a concession.
    event PowerStripped(Power indexed power, uint256 indexed ballotId);
    /// @notice The Tyrant conceded a power.
    event Conceded(Power indexed power);
    /// @notice The outcome changed.
    event OutcomeChanged(Outcome outcome);
    /// @notice The season was finalized.
    event Finalized(Outcome outcome);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice The caller is not the Tyrant.
    error NotTyrant();
    /// @notice The caller is not the keeper.
    error NotKeeper();
    /// @notice The season is not running.
    error SeasonNotActive();
    /// @notice The season has not ended yet.
    error SeasonNotOver();
    /// @notice The power was stripped and can never be used again.
    error PowerGone(Power power);
    /// @notice The power was used too recently.
    error PowerOnCooldown(Power power, uint64 readyAt);
    /// @notice The address is not a live vassal.
    error NotVassal();
    /// @notice The address already joined this season.
    error AlreadyJoined();
    /// @notice The address was banished this season.
    error BanishedThisSeason();
    /// @notice The label is not 3 to 20 characters of a-z, 0-9 and inner hyphens.
    error InvalidLabel();
    /// @notice The banner or proclamation is too long.
    error BannerTooLong();
    /// @notice The vassal has no house to dissolve.
    error NoHouse();
    /// @notice The court's subregistry for the vassal is not the supplied house.
    error HouseMismatch();
    /// @notice A ballot is already active.
    error BallotAlreadyActive();
    /// @notice The ballot is not the active ballot.
    error BallotNotActive(uint256 ballotId);
    /// @notice The ballot deadline has passed.
    error BallotClosed(uint256 ballotId);
    /// @notice The ballot cannot be resolved yet.
    error BallotStillOpen(uint256 ballotId);
    /// @notice A ballot cannot finish before the season ends.
    error BallotTooLate();
    /// @notice New ballots are blocked after a concession.
    error ImmunePeriod(uint64 until);
    /// @notice There are no vassals to vote.
    error NoElectorate();
    /// @notice The voter joined at or after the ballot opened.
    error JoinedTooLate();
    /// @notice The address already voted in this ballot.
    error AlreadyVoted();
    /// @notice The nullifier was already used in this ballot.
    error NullifierUsed();
    /// @notice On-chain World ID verification is disabled.
    error OnchainModeDisabled();
    /// @notice Attested voting is disabled.
    error AttestedModeDisabled();
    /// @notice The attestation expired.
    error AttestationExpired();
    /// @notice The attestation signature is not from the attester.
    error BadAttestation();
    /// @notice The season was already finalized.
    error AlreadyFinalized();
    /// @notice A ballot must be resolved before the season can be finalized.
    error BallotPending();
    /// @notice The court was not deployed with exactly the roles the Throne requires.
    error GenesisInvariantViolated();
    /// @notice A constructor argument is invalid.
    error InvalidConfig();

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    /// @param cfg The season configuration. The court must already grant the Throne exactly the
    ///        root roles from `Powers.throneRootRoles` and nobody else any of them.
    constructor(Config memory cfg) EIP712("FealtyThrone", "1") {
        if (
            address(cfg.court) == address(0) || cfg.tyrant == address(0) || cfg.keeper == address(0)
                || address(cfg.bannerResolver) == address(0) || address(cfg.decreeResolver) == address(0)
                || cfg.seasonEnd <= cfg.seasonStart || cfg.ballotDuration == 0 || cfg.minYesVotes == 0
                || (address(cfg.worldId) == address(0) && cfg.attester == address(0))
        ) revert InvalidConfig();

        court = cfg.court;
        worldId = cfg.worldId;
        tyrant = cfg.tyrant;
        keeper = cfg.keeper;
        attester = cfg.attester;
        bannerResolver = cfg.bannerResolver;
        decreeResolver = cfg.decreeResolver;
        externalNullifierHash = cfg.externalNullifierHash;
        seasonStart = cfg.seasonStart;
        seasonEnd = cfg.seasonEnd;
        powerCooldown = cfg.powerCooldown;
        ballotDuration = cfg.ballotDuration;
        concedeImmunity = cfg.concedeImmunity;
        minYesVotes = cfg.minYesVotes;
        courtDnsSuffix = cfg.courtDnsSuffix;

        _assertGenesis(cfg.court);
        _ballots.push(); // placeholder so that ballot id zero means "none"

        if (address(cfg.realm) != address(0)) {
            cfg.court.setParent(cfg.realm, cfg.seasonLabel);
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Vassals
    ////////////////////////////////////////////////////////////////////////

    /// @notice Join the court and receive a soulbound `<label>.<court>` name.
    /// @param label Desired name label.
    /// @param banner Text shown on the name's `fealty.banner` record.
    function join(string calldata label, string calldata banner) external {
        _requireSeasonActive();
        Vassal storage v = vassals[msg.sender];
        if (v.banished) revert BanishedThisSeason();
        if (v.joinedAt != 0) revert AlreadyJoined();
        if (bytes(banner).length > MAX_BANNER_BYTES) revert BannerTooLong();
        _validateLabel(label);

        v.label = label;
        v.joinedAt = uint64(block.timestamp);
        ++liveVassals;

        court.register(label, msg.sender, IRegistry(address(0)), address(bannerResolver), Powers.vassalRoles(), seasonEnd);

        bytes memory name = dnsName(label);
        bannerResolver.setText(name, BANNER_KEY, banner);
        bannerResolver.setText(name, JOINED_KEY, Strings.toString(block.timestamp));
        emit Joined(msg.sender, label, banner);
    }

    /// @notice Change your banner. While you are decreed the new text is not shown until you
    ///         restore your own resolver with `court.setResolver`.
    /// @param banner The new banner.
    function setBanner(string calldata banner) external {
        Vassal storage v = _liveVassal(msg.sender);
        if (bytes(banner).length > MAX_BANNER_BYTES) revert BannerTooLong();
        bannerResolver.setText(dnsName(v.label), BANNER_KEY, banner);
        emit BannerSet(msg.sender, v.label, banner);
    }

    /// @notice Record the house (sub-court) a vassal set on their own name, for indexers.
    /// @param house The registry the vassal set with `court.setSubregistry`.
    function registerHouse(IRegistry house) external {
        Vassal storage v = _liveVassal(msg.sender);
        if (address(house) == address(0) || court.getSubregistry(v.label) != house) revert HouseMismatch();
        emit HouseRegistered(msg.sender, v.label, address(house));
    }

    ////////////////////////////////////////////////////////////////////////
    // The Tyrant's powers
    ////////////////////////////////////////////////////////////////////////

    /// @notice BANISH: delete a vassal's name and remove their vote from the active ballot.
    /// @param target The vassal to banish.
    function banish(address target) external {
        _usePower(Power.Banish);
        Vassal storage v = _liveVassal(target);
        v.banished = true;
        --liveVassals;
        court.unregister(LibLabel.id(v.label));
        _dropVote(target);
        emit Banished(target, v.label);
    }

    /// @notice DECREE: overwrite a vassal's record with a proclamation and point their name at the
    ///         decree resolver. The vassal can undo this themselves with `court.setResolver`.
    /// @param target The vassal to decree over.
    /// @param proclamation The text shown on the vassal's name.
    function decree(address target, string calldata proclamation) external {
        _usePower(Power.Decree);
        if (bytes(proclamation).length > MAX_BANNER_BYTES) revert BannerTooLong();
        Vassal storage v = _liveVassal(target);
        decreeResolver.setText(dnsName(v.label), BANNER_KEY, proclamation);
        court.setResolver(LibLabel.id(v.label), address(decreeResolver));
        emit Decreed(target, v.label, proclamation);
    }

    /// @notice DISSOLVE: detach a vassal's house so its sub-names stop resolving.
    /// @param target The vassal whose house to dissolve.
    function dissolve(address target) external {
        _usePower(Power.Dissolve);
        Vassal storage v = _liveVassal(target);
        IRegistry house = court.getSubregistry(v.label);
        if (address(house) == address(0)) revert NoHouse();
        court.setSubregistry(LibLabel.id(v.label), IRegistry(address(0)));
        emit Dissolved(target, v.label, address(house));
    }

    /// @notice Give up a power voluntarily. This cancels any active ballot and blocks new
    ///         ballots for the immunity period.
    /// @param p The power to give up.
    function concede(Power p) external {
        if (msg.sender != tyrant) revert NotTyrant();
        _requireSeasonActive();
        if (!powerAlive(p)) revert PowerGone(p);
        _strip(p, 0);
        emit Conceded(p);
        uint256 id = activeBallotId;
        if (id != 0) {
            _ballots[id].resolved = true;
            activeBallotId = 0;
            emit BallotCancelled(id);
        }
        immuneUntil = uint64(block.timestamp) + concedeImmunity;
        _updateOutcome();
    }

    ////////////////////////////////////////////////////////////////////////
    // Revolution
    ////////////////////////////////////////////////////////////////////////

    /// @notice Open a ballot after the keeper observed a pledge quorum on Arkiv.
    /// @param p The power the revolution targets.
    /// @param manifestoKey Arkiv entity key of the manifesto, for auditing the quorum.
    /// @param pledges Number of valid pledges the keeper counted.
    /// @return id The new ballot id.
    function openBallot(Power p, bytes32 manifestoKey, uint32 pledges) external returns (uint256 id) {
        if (msg.sender != keeper) revert NotKeeper();
        _requireSeasonActive();
        if (activeBallotId != 0) revert BallotAlreadyActive();
        if (!powerAlive(p)) revert PowerGone(p);
        if (block.timestamp < immuneUntil) revert ImmunePeriod(immuneUntil);
        if (block.timestamp + ballotDuration > seasonEnd) revert BallotTooLate();
        if (liveVassals == 0) revert NoElectorate();

        uint64 deadline = uint64(block.timestamp) + ballotDuration;
        _ballots.push(
            Ballot({
                power: p,
                manifestoKey: manifestoKey,
                pledges: pledges,
                openedAt: uint64(block.timestamp),
                deadline: deadline,
                electorate: liveVassals,
                yes: 0,
                no: 0,
                resolved: false,
                passed: false
            })
        );
        id = _ballots.length - 1;
        activeBallotId = id;
        emit BallotOpened(id, p, manifestoKey, pledges, deadline, liveVassals);
    }

    /// @notice Vote with a World ID proof verified on-chain.
    /// @param id The ballot id.
    /// @param support True for yes.
    /// @param root World ID Merkle root.
    /// @param nullifierHash The proof's nullifier hash.
    /// @param proof The unpacked Groth16 proof.
    function vote(uint256 id, bool support, uint256 root, uint256 nullifierHash, uint256[8] calldata proof) external {
        if (address(worldId) == address(0)) revert OnchainModeDisabled();
        _checkVoter(id, msg.sender, nullifierHash);
        worldId.verifyProof(
            root,
            GROUP_ID,
            ByteHasher.hashToField(VoteSignal.encode(msg.sender, id, support)),
            nullifierHash,
            externalNullifierHash,
            proof
        );
        _record(id, msg.sender, support, nullifierHash);
    }

    /// @notice Vote with a proof that a trusted attester verified off-chain.
    /// @param id The ballot id.
    /// @param support True for yes.
    /// @param nullifierHash The proof's nullifier hash.
    /// @param expiry Attestation expiry timestamp.
    /// @param signature The attester's EIP-712 signature.
    function voteAttested(uint256 id, bool support, uint256 nullifierHash, uint256 expiry, bytes calldata signature)
        external
    {
        if (attester == address(0)) revert AttestedModeDisabled();
        if (block.timestamp > expiry) revert AttestationExpired();
        _checkVoter(id, msg.sender, nullifierHash);
        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(ATTEST_TYPEHASH, msg.sender, id, support, nullifierHash, expiry)));
        if (ECDSA.recover(digest, signature) != attester) revert BadAttestation();
        _record(id, msg.sender, support, nullifierHash);
    }

    /// @notice Finish the active ballot. Anyone may call this after the deadline, or earlier once
    ///         a majority of the electorate has voted yes.
    /// @param id The ballot id.
    function resolve(uint256 id) external {
        if (id == 0 || id != activeBallotId) revert BallotNotActive(id);
        Ballot storage b = _ballots[id];
        bool early = b.yes >= minYesVotes && uint256(b.yes) * 2 > b.electorate;
        if (!early && block.timestamp < b.deadline) revert BallotStillOpen(id);

        bool passed = b.yes >= minYesVotes && b.yes > b.no;
        b.resolved = true;
        b.passed = passed;
        activeBallotId = 0;
        emit BallotResolved(id, passed, b.yes, b.no);

        if (passed) {
            if (powerAlive(b.power)) _strip(b.power, id);
            _updateOutcome();
        }
    }

    /// @notice Settle the season after it ends. The Tyrant wins unless two powers were stripped.
    function finalize() external {
        if (block.timestamp < seasonEnd) revert SeasonNotOver();
        if (finalized) revert AlreadyFinalized();
        if (activeBallotId != 0) revert BallotPending();
        finalized = true;
        if (outcome == Outcome.Undecided) {
            outcome = Outcome.TyrantWins;
            emit OutcomeChanged(Outcome.TyrantWins);
        }
        emit Finalized(outcome);
    }

    ////////////////////////////////////////////////////////////////////////
    // Views
    ////////////////////////////////////////////////////////////////////////

    /// @notice Whether the Throne still holds a power. Read from ENSv2, the source of truth.
    /// @param p The power.
    /// @return True while the Throne holds the power's root role.
    function powerAlive(Power p) public view returns (bool) {
        return court.hasRootRoles(Powers.role(p), address(this));
    }

    /// @notice Number of powers the Throne still holds.
    /// @return n Between zero and three.
    function powersRemaining() public view returns (uint256 n) {
        if (powerAlive(Power.Banish)) ++n;
        if (powerAlive(Power.Decree)) ++n;
        if (powerAlive(Power.Dissolve)) ++n;
    }

    /// @notice Seconds until a power can be used again.
    /// @param p The power.
    /// @return Seconds remaining, zero when ready.
    function cooldownRemaining(Power p) external view returns (uint64) {
        uint64 last = lastUsed[p];
        if (last == 0) return 0;
        uint64 readyAt = last + powerCooldown;
        return block.timestamp >= readyAt ? 0 : readyAt - uint64(block.timestamp);
    }

    /// @notice A ballot by id.
    /// @param id The ballot id.
    /// @return The ballot.
    function getBallot(uint256 id) external view returns (Ballot memory) {
        return _ballots[id];
    }

    /// @notice Number of ballots ever opened.
    /// @return The count.
    function ballotCount() external view returns (uint256) {
        return _ballots.length - 1;
    }

    /// @notice Vote an address cast in a ballot.
    /// @param id The ballot id.
    /// @param voter The voter.
    /// @return 1 for yes, -1 for no, 0 for none.
    function voteOf(uint256 id, address voter) external view returns (int8) {
        return _voteOf[id][voter];
    }

    /// @notice Whether an address could vote right now in the given ballot.
    /// @param account The address.
    /// @param id The ballot id.
    /// @return True when the ballot is active and the address is an unvoted, live, early-enough vassal.
    function isEligible(address account, uint256 id) external view returns (bool) {
        if (id == 0 || id != activeBallotId) return false;
        Ballot storage b = _ballots[id];
        Vassal storage v = vassals[account];
        return block.timestamp < b.deadline && v.joinedAt != 0 && !v.banished && v.joinedAt < b.openedAt
            && _voteOf[id][account] == 0 && court.getOwner(LibLabel.id(v.label)) == account;
    }

    /// @notice Whether a vassal's name currently points at the decree resolver.
    /// @param account The vassal.
    /// @return True while decreed.
    function isDecreed(address account) external view returns (bool) {
        Vassal storage v = vassals[account];
        return v.joinedAt != 0 && !v.banished && court.getResolver(v.label) == address(decreeResolver);
    }

    /// @notice DNS-encoded full name of a label in this court.
    /// @param label A label of this court.
    /// @return The DNS-encoded name.
    function dnsName(string memory label) public view returns (bytes memory) {
        return abi.encodePacked(uint8(bytes(label).length), label, courtDnsSuffix);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal
    ////////////////////////////////////////////////////////////////////////

    /// @dev Checks that the court gave the Throne exactly the intended roles and nobody else.
    function _assertGenesis(FealtyCourt c) private view {
        if (!c.hasRootRoles(Powers.throneRootRoles(), address(this)) || c.isEmancipated()) {
            revert GenesisInvariantViolated();
        }
        (uint256 counts,) = c.getAssigneeCount(0, Powers.throneRootRoles());
        for (uint256 i; i < Powers.COUNT; ++i) {
            uint256 r = Powers.role(Power(i));
            if (!_soleHolder(counts, r) || !_soleHolder(counts, r << 128)) revert GenesisInvariantViolated();
        }
    }

    /// @dev True when the nybble of `bit` in `counts` equals one.
    function _soleHolder(uint256 counts, uint256 bit) private pure returns (bool) {
        return (counts & (bit * 0xF)) == bit;
    }

    function _requireSeasonActive() private view {
        if (block.timestamp < seasonStart || block.timestamp >= seasonEnd) revert SeasonNotActive();
    }

    /// @dev Authorizes the Tyrant, checks the power is alive and ready, and records the use.
    function _usePower(Power p) private {
        if (msg.sender != tyrant) revert NotTyrant();
        _requireSeasonActive();
        if (!powerAlive(p)) revert PowerGone(p);
        uint64 last = lastUsed[p];
        if (last != 0 && block.timestamp < last + powerCooldown) revert PowerOnCooldown(p, last + powerCooldown);
        lastUsed[p] = uint64(block.timestamp);
    }

    function _liveVassal(address account) private view returns (Vassal storage v) {
        v = vassals[account];
        if (v.joinedAt == 0 || v.banished) revert NotVassal();
    }

    /// @dev Revokes a power and its admin bit from the Throne. This is irreversible.
    function _strip(Power p, uint256 ballotId) private {
        court.revokeRootRoles(Powers.roleWithAdmin(p), address(this));
        emit PowerStripped(p, ballotId);
    }

    function _updateOutcome() private {
        uint256 stripped = Powers.COUNT - powersRemaining();
        Outcome next = outcome;
        if (stripped == Powers.COUNT && court.isEmancipated()) next = Outcome.Emancipated;
        else if (stripped >= 2 && outcome == Outcome.Undecided) next = Outcome.RebelsWin;
        if (next != outcome) {
            outcome = next;
            emit OutcomeChanged(next);
        }
    }

    /// @dev Removes the vote of a banished vassal from the active ballot. The nullifier stays used.
    function _dropVote(address account) private {
        uint256 id = activeBallotId;
        if (id == 0) return;
        int8 cast = _voteOf[id][account];
        if (cast == 0) return;
        Ballot storage b = _ballots[id];
        if (cast > 0) --b.yes;
        else --b.no;
        _voteOf[id][account] = 0;
        emit VoteRemoved(id, account);
    }

    /// @dev Voting preconditions shared by both voting modes.
    function _checkVoter(uint256 id, address voter, uint256 nullifierHash) private view {
        if (id == 0 || id != activeBallotId) revert BallotNotActive(id);
        Ballot storage b = _ballots[id];
        if (block.timestamp >= b.deadline) revert BallotClosed(id);
        Vassal storage v = vassals[voter];
        if (v.joinedAt == 0 || v.banished || court.getOwner(LibLabel.id(v.label)) != voter) revert NotVassal();
        if (v.joinedAt >= b.openedAt) revert JoinedTooLate();
        if (_voteOf[id][voter] != 0) revert AlreadyVoted();
        if (_nullifierUsed[id][nullifierHash]) revert NullifierUsed();
    }

    function _record(uint256 id, address voter, bool support, uint256 nullifierHash) private {
        _nullifierUsed[id][nullifierHash] = true;
        _voteOf[id][voter] = support ? int8(1) : int8(-1);
        if (support) ++_ballots[id].yes;
        else ++_ballots[id].no;
        emit Voted(id, voter, support, nullifierHash);
    }

    /// @dev Labels are 3 to 20 characters of a-z, 0-9 and hyphens, never starting or ending with one.
    function _validateLabel(string calldata label) private pure {
        bytes calldata b = bytes(label);
        uint256 n = b.length;
        if (n < 3 || n > 20 || b[0] == 0x2d || b[n - 1] == 0x2d) revert InvalidLabel();
        for (uint256 i; i < n; ++i) {
            bytes1 c = b[i];
            bool ok = (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x2d;
            if (!ok) revert InvalidLabel();
        }
    }
}
