// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {Grant} from "@ens-v2/access-control/interfaces/IEACGrantInitializable.sol";
import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";
import {PermissionedResolver} from "@ens-v2/resolver/PermissionedResolver.sol";
import {PermissionedResolverLib} from "@ens-v2/resolver/libraries/PermissionedResolverLib.sol";
import {IPermissionedResolverInitializable} from "@ens-v2/resolver/interfaces/IPermissionedResolverInitializable.sol";
import {ITextSetter} from "@ens-v2/resolver/interfaces/setters/ITextSetter.sol";
import {IContractNamer} from "@ens-v2/reverse-registrar/interfaces/IContractNamer.sol";
import {LabelStore} from "@ens-v2/utils/LabelStore.sol";
import {LibLabel} from "@ens-v2/utils/LibLabel.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";

import {FealtyCourt} from "../src/FealtyCourt.sol";
import {FealtyRealm} from "../src/FealtyRealm.sol";
import {Throne} from "../src/Throne.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {Power, Powers} from "../src/libraries/Powers.sol";

/// @notice World ID router stand-in. It can be told to fail, and to require exact arguments.
contract MockWorldID is IWorldID {
    struct Expectation {
        bool set;
        uint256 root;
        uint256 signalHash;
        uint256 nullifierHash;
        uint256 externalNullifierHash;
    }

    bool public shouldFail;
    Expectation public expected;

    error InvalidProof();
    error UnexpectedArguments();

    function setShouldFail(bool f) external {
        shouldFail = f;
    }

    function expect(uint256 root, uint256 signalHash, uint256 nullifierHash, uint256 ext) external {
        expected = Expectation(true, root, signalHash, nullifierHash, ext);
    }

    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 ext,
        uint256[8] calldata
    ) external view override {
        if (shouldFail) revert InvalidProof();
        if (groupId != 1) revert UnexpectedArguments();
        Expectation memory e = expected;
        if (
            e.set
                && (e.root != root || e.signalHash != signalHash || e.nullifierHash != nullifierHash
                    || e.externalNullifierHash != ext)
        ) revert UnexpectedArguments();
    }
}

/// @notice A local ENSv2 stack plus one season, shared by every Throne test.
abstract contract Base is Test {
    uint64 internal constant SEASON_LEN = 1800;
    uint64 internal constant COOLDOWN = 45;
    uint64 internal constant BALLOT_LEN = 120;
    uint64 internal constant IMMUNITY = 60;
    uint256 internal constant EXT_NULL = 0xE17;

    address internal tyrant = makeAddr("tyrant");
    address internal keeper = makeAddr("keeper");
    uint256 internal attesterPk = 0xA77E57;
    address internal attester;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    LabelStore internal labelStore;
    VerifiableFactory internal factory;
    FealtyCourt internal court;
    FealtyRealm internal realm;
    ITextSetter internal bannerResolver;
    ITextSetter internal decreeResolver;
    MockWorldID internal world;
    Throne internal throne;
    uint64 internal seasonStart;
    uint64 internal seasonEnd;

    bytes internal constant SUFFIX = abi.encodePacked(uint8(2), "s1", uint8(6), "fealty", uint8(3), "eth", uint8(0));

    function setUp() public virtual {
        vm.warp(1_000_000);
        attester = vm.addr(attesterPk);
        seasonStart = uint64(block.timestamp);
        seasonEnd = seasonStart + SEASON_LEN;
        world = new MockWorldID();
        _deploy(address(world), attester);
    }

    /// @dev Deploys the full stack. The Throne address is predicted so the court can grant it roles.
    function _deploy(address worldId, address attester_) internal {
        labelStore = new LabelStore(IContractNamer(address(0)));
        factory = new VerifiableFactory();
        address resolverImpl = address(new PermissionedResolver(makeAddr("namer")));
        realm = new FealtyRealm(labelStore, address(this), RegistryRolesLib.ROLE_REGISTRAR);

        // court + two resolver proxies (each deployProxy bumps the nonce) precede the Throne
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        court = new FealtyCourt(labelStore, predicted, Powers.throneRootRoles());
        bannerResolver = _proxy(resolverImpl, predicted, 1);
        decreeResolver = _proxy(resolverImpl, predicted, 2);

        throne = new Throne(
            Throne.Config({
                court: court,
                worldId: IWorldID(worldId),
                tyrant: tyrant,
                keeper: keeper,
                attester: attester_,
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
                minYesVotes: _minYes()
            })
        );
        assertEq(address(throne), predicted, "throne address prediction");
    }

    /// @dev Minimum yes votes for a revolution; tests override this.
    function _minYes() internal pure virtual returns (uint32) {
        return 1;
    }

    function _proxy(address impl, address throneAddr, uint256 salt) internal returns (ITextSetter) {
        Grant[] memory grants = new Grant[](1);
        grants[0] = Grant({account: throneAddr, roleBitmap: PermissionedResolverLib.ROLE_SET_TEXT});
        address p = factory.deployProxy(
            impl, salt, abi.encodeCall(IPermissionedResolverInitializable.initialize, (grants, new bytes[](0)))
        );
        return ITextSetter(p);
    }

    function _join(address who, string memory label) internal {
        vm.prank(who);
        throne.join(label, string.concat("banner of ", label));
    }

    function _joinAll() internal {
        _join(alice, "alice");
        _join(bob, "bob");
        _join(carol, "carol");
        vm.warp(block.timestamp + 1); // ballots opened later than the joins, so these vassals may vote
    }

    function _id(string memory label) internal pure returns (uint256) {
        return LibLabel.id(label);
    }

    /// @dev Reads a text record the way an ENS client would: through the resolver's `resolve`.
    function _text(address resolver, string memory label, string memory key) internal view returns (string memory) {
        bytes memory name = throne.dnsName(label);
        bytes memory data = abi.encodeCall(ITextResolver.text, (bytes32(0), key));
        bytes memory out = PermissionedResolver(resolver).resolve(name, data);
        return abi.decode(out, (string));
    }

    function _openBallot(Power p) internal returns (uint256 id) {
        vm.prank(keeper);
        id = throne.openBallot(p, keccak256("manifesto"), 3);
    }

    function _vote(address who, uint256 id, bool support, uint256 nullifier) internal {
        uint256[8] memory proof;
        vm.prank(who);
        throne.vote(id, support, 1, nullifier, proof);
    }

    /// @dev Opens a ballot, gets one yes vote and resolves early so the power is stripped.
    function _strip(Power p) internal {
        uint256 id = _openBallot(p);
        // joined before the ballot, so eligible
        _vote(alice, id, true, uint256(keccak256(abi.encode("n-alice", id))));
        _vote(bob, id, true, uint256(keccak256(abi.encode("n-bob", id))));
        throne.resolve(id);
    }
}
