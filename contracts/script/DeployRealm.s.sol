// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRegistry} from "@ens-v2/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens-v2/registry/interfaces/IPermissionedRegistry.sol";
import {RegistryRolesLib} from "@ens-v2/registry/libraries/RegistryRolesLib.sol";
import {ILabelStore} from "@ens-v2/utils/interfaces/ILabelStore.sol";
import {IETHRegistrar} from "@ens-v2/registrar/interfaces/IETHRegistrar.sol";
import {ETHRegistrar} from "@ens-v2/registrar/ETHRegistrar.sol";

import {Config} from "./Config.s.sol";
import {FealtyRealm} from "../src/FealtyRealm.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @title DeployRealm
/// @notice Registers `<REALM_LABEL>.eth` on ENSv2 and deploys the realm registry behind it.
///         Registration is commit/reveal, so it runs in two steps separated by the registrar's
///         minimum commitment age:
///
///           forge script script/DeployRealm.s.sol --sig "commit()" --rpc-url sepolia --broadcast
///           (wait for the age to pass; the script prints it)
///           forge script script/DeployRealm.s.sol --sig "register()" --rpc-url sepolia --broadcast
contract DeployRealm is Config {
    uint64 internal constant DURATION = 365 days;

    /// @notice Step 1: deploy the realm registry and record the commitment.
    function commit() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address deployer = vm.addr(pk);
        string memory label = vm.envString("REALM_LABEL");
        ETHRegistrar registrar = ETHRegistrar(ensAddress("ETHRegistrar"));
        require(registrar.isAvailable(label), "REALM_LABEL is taken on this ENSv2 deployment; choose another");

        vm.startBroadcast(pk);
        FealtyRealm realm = new FealtyRealm(
            ILabelStore(ensAddress("LabelStore")),
            deployer,
            RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_SET_PARENT
        );
        bytes32 secret = keccak256(abi.encode("fealty-realm", deployer, label));
        registrar.commit(registrar.makeCommitment(label, deployer, secret, IRegistry(address(realm)), address(0), DURATION, bytes32(0)));
        vm.stopBroadcast();

        vm.createDir(deploymentsDir(), true);
        string memory o = "realm";
        vm.serializeAddress(o, "realm", address(realm));
        vm.serializeString(o, "label", label);
        vm.serializeUint(o, "committedAt", block.timestamp);
        vm.writeJson(vm.serializeBytes32(o, "secret", secret), realmFile());

        console.log("Realm registry:", address(realm));
        console.log("Wait at least (seconds):", uint256(registrar.MIN_COMMITMENT_AGE()));
        console.log("Then run: --sig 'register()'");
    }

    /// @notice Step 2: pay for the name and register it with the realm as its subregistry.
    function register() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address deployer = vm.addr(pk);
        string memory state = vm.readFile(realmFile());
        FealtyRealm realm = FealtyRealm(vm.parseJsonAddress(state, ".realm"));
        string memory label = vm.parseJsonString(state, ".label");
        bytes32 secret = vm.parseJsonBytes32(state, ".secret");
        ETHRegistrar registrar = ETHRegistrar(ensAddress("ETHRegistrar"));
        IERC20 usdc = IERC20(ensAddress("MockUSDC"));
        require(
            block.timestamp >= registrar.commitmentAt(registrar.makeCommitment(label, deployer, secret, IRegistry(address(realm)), address(0), DURATION, bytes32(0)))
                + registrar.MIN_COMMITMENT_AGE(),
            "commitment is too young; wait longer"
        );

        (uint256 base, uint256 premium) = registrar.getRegisterPrice(label, DURATION, usdc);
        vm.startBroadcast(pk);
        IMintable(address(usdc)).mint(deployer, base + premium);
        usdc.approve(address(registrar), base + premium);
        registrar.register(label, deployer, secret, IRegistry(address(realm)), address(0), DURATION, usdc, bytes32(0));
        realm.setParent(IRegistry(ensAddress("ETHRegistry")), label);
        vm.stopBroadcast();

        console.log("Registered:", string.concat(label, ".eth"));
        console.log("Realm registry:", address(realm));
    }
}
