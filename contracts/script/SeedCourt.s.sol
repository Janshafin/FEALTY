// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";

import {Config} from "./Config.s.sol";
import {Throne} from "../src/Throne.sol";

/// @title SeedCourt
/// @notice Gives the realm a living map for the demo: NPC vassals derived from `NPC_MNEMONIC`, each
///         funded by the deployer and joined with a label and banner from `scripts/seed/npcs.json`.
///         NPCs can pledge on Arkiv but have no World ID, so they can never decide a ballot.
contract SeedCourt is Config {
    function run() external {
        string memory season = vm.envString("SEASON");
        Throne throne = Throne(vm.parseJsonAddress(vm.readFile(seasonFile(season)), ".addresses.throne"));
        string memory roster = vm.readFile(string.concat(vm.projectRoot(), "/../scripts/seed/npcs.json"));
        string[] memory labels = vm.parseJsonStringArray(roster, ".labels");
        string[] memory banners = vm.parseJsonStringArray(roster, ".banners");
        require(labels.length == banners.length, "labels and banners differ in length");

        uint256 deployerPk = vm.envUint("DEPLOYER_PK");
        uint256 fundEach = vm.envOr("NPC_FUNDING_WEI", uint256(0.01 ether));
        string memory mnemonic = vm.envString("NPC_MNEMONIC");

        uint256[] memory keys = new uint256[](labels.length);
        address[] memory npcs = new address[](labels.length);
        vm.startBroadcast(deployerPk);
        for (uint256 i; i < labels.length; ++i) {
            keys[i] = vm.deriveKey(mnemonic, uint32(i));
            npcs[i] = vm.addr(keys[i]);
            (bool ok,) = npcs[i].call{value: fundEach}("");
            require(ok, "funding failed");
        }
        vm.stopBroadcast();

        for (uint256 i; i < labels.length; ++i) {
            vm.startBroadcast(keys[i]);
            throne.join(labels[i], banners[i]);
            vm.stopBroadcast();
            console.log(labels[i], npcs[i]);
        }

        // Record who the NPCs are so the API can mark them.
        string memory out = "[";
        for (uint256 i; i < npcs.length; ++i) {
            out = string.concat(out, i == 0 ? "" : ",", '"', vm.toString(npcs[i]), '"');
        }
        vm.writeFile(string.concat(deploymentsDir(), "/", season, ".npcs.json"), string.concat(out, "]"));
    }
}
