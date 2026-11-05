// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";
import {PermissionedResolver} from "@ens-v2/resolver/PermissionedResolver.sol";
import {IContractNamer} from "@ens-v2/reverse-registrar/interfaces/IContractNamer.sol";
import {ILabelStore} from "@ens-v2/utils/interfaces/ILabelStore.sol";
import {LabelStore} from "@ens-v2/utils/LabelStore.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";

import {DeploySeason} from "../script/DeploySeason.s.sol";
import {FealtyRealm} from "../src/FealtyRealm.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {Power, Powers} from "../src/libraries/Powers.sol";

/// @dev A contract creating via `new` and calling the factory spends one nonce for the court only.
contract ContractCreatorDeploySeason is DeploySeason {
    function _nonceOffset() internal pure override returns (uint256) {
        return 1;
    }

    /// @dev In production the creator is an EOA; a contract must accept the season label token.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}

/// @notice Runs the exact deployment code the script broadcasts, on a local ENSv2 stack.
contract DeploySeasonTest is Test {
    DeploySeason internal script;
    DeploySeason.Params internal p;

    function setUp() public {
        vm.warp(2_000_000);
        script = new ContractCreatorDeploySeason();
        LabelStore labelStore = new LabelStore(IContractNamer(address(0)));
        FealtyRealm realm = new FealtyRealm(
            ILabelStore(address(labelStore)), address(script), RegistryRolesLib.ROLE_REGISTRAR
        );
        p.creator = address(script);
        p.realm = realm;
        p.labelStore = ILabelStore(address(labelStore));
        p.factory = new VerifiableFactory();
        p.resolverImpl = address(new PermissionedResolver(makeAddr("namer")));
        p.realmLabel = "fealty";
        p.season = "s1";
        p.tyrant = makeAddr("tyrant");
        p.keeper = makeAddr("keeper");
        p.worldId = IWorldID(makeAddr("router"));
        p.externalNullifierHash = 12345;
        p.seasonStart = uint64(block.timestamp);
        p.seasonEnd = uint64(block.timestamp) + 1800;
        p.powerCooldown = 45;
        p.ballotDuration = 120;
        p.concedeImmunity = 60;
        p.minYesVotes = 1;
    }

    function test_deploy_wiresTheSeasonAndPredictsTheThrone() public {
        DeploySeason.Deployed memory d = script.deploy(p);

        assertTrue(d.court.hasRootRoles(Powers.throneRootRoles(), address(d.throne)));
        assertFalse(d.court.isEmancipated());
        assertEq(d.throne.powersRemaining(), 3);
        assertEq(d.throne.tyrant(), p.tyrant);
        assertEq(d.throne.keeper(), p.keeper);
        assertEq(d.throne.externalNullifierHash(), 12345);
        assertEq(d.throne.seasonEnd(), p.seasonEnd);
        assertEq(d.throne.courtDnsSuffix(), abi.encodePacked(uint8(2), "s1", uint8(6), "fealty", uint8(3), "eth", uint8(0)));
    }

    function test_deploy_attachesCourtToTheRealmForGood() public {
        DeploySeason.Deployed memory d = script.deploy(p);
        assertEq(address(p.realm.getSubregistry("s1")), address(d.court));
        // the season label's owner holds no roles on it, so the court can never be swapped
        uint256 id = uint256(keccak256("s1"));
        assertEq(p.realm.roles(id, address(script)), 0);
        (, string memory label) = d.court.getParent();
        assertEq(label, "s1");
    }

    function test_deploy_resolversAcceptOnlyTheThrone() public {
        DeploySeason.Deployed memory d = script.deploy(p);
        vm.expectRevert();
        d.bannerResolver.setText(abi.encodePacked(uint8(1), "x", uint8(0)), "k", "v");
        vm.expectRevert();
        vm.prank(p.tyrant);
        d.decreeResolver.setText(abi.encodePacked(uint8(1), "x", uint8(0)), "k", "v");
    }

    function test_deploy_seasonIsPlayableEndToEnd() public {
        DeploySeason.Deployed memory d = script.deploy(p);
        address alice = makeAddr("alice");
        vm.prank(alice);
        d.throne.join("alice", "hello");
        assertEq(d.court.getOwner(uint256(keccak256("alice"))), alice);
    }

    function test_render_producesTheJsonTheTypeScriptLoaderExpects() public {
        DeploySeason.Deployed memory d = script.deploy(p);
        string memory json = script.render(p, d, "onchain");
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid);
        assertEq(vm.parseJsonString(json, ".season"), "s1");
        assertEq(vm.parseJsonString(json, ".realmLabel"), "fealty");
        assertEq(vm.parseJsonAddress(json, ".addresses.throne"), address(d.throne));
        assertEq(vm.parseJsonAddress(json, ".addresses.court"), address(d.court));
        assertEq(vm.parseJsonAddress(json, ".addresses.bannerResolver"), address(d.bannerResolver));
        assertEq(vm.parseJsonAddress(json, ".config.tyrant"), p.tyrant);
        assertEq(vm.parseJsonString(json, ".config.worldMode"), "onchain");
        assertEq(vm.parseJsonString(json, ".config.externalNullifierHash"), "12345");
        assertEq(vm.parseJsonUint(json, ".config.minYesVotes"), 1);
    }
}
