// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {Grant} from "@ens-v2/access-control/interfaces/IEACGrantInitializable.sol";
import {IRegistry} from "@ens-v2/registry/interfaces/IRegistry.sol";
import {PermissionedResolverLib} from "@ens-v2/resolver/libraries/PermissionedResolverLib.sol";
import {IPermissionedResolverInitializable} from "@ens-v2/resolver/interfaces/IPermissionedResolverInitializable.sol";
import {ITextSetter} from "@ens-v2/resolver/interfaces/setters/ITextSetter.sol";
import {ILabelStore} from "@ens-v2/utils/interfaces/ILabelStore.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";

import {Config} from "./Config.s.sol";
import {FealtyCourt} from "../src/FealtyCourt.sol";
import {FealtyRealm} from "../src/FealtyRealm.sol";
import {Throne} from "../src/Throne.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {Powers} from "../src/libraries/Powers.sol";

/// @title DeploySeason
/// @notice Deploys one season: court, two shared resolvers, the Throne, and the season label in the
///         realm. The Throne must hold the court's root roles from its constructor, but the court is
///         deployed first, so the Throne's address is predicted from the creator's nonce. The
///         Throne's constructor refuses to start unless the court granted it exactly the roles
///         it needs, so a wrong prediction fails loudly before anything is usable.
contract DeploySeason is Config {
    /// @notice Everything a season needs from the outside.
    struct Params {
        address creator; // account whose nonce creates the court and the Throne
        FealtyRealm realm;
        ILabelStore labelStore;
        VerifiableFactory factory;
        address resolverImpl;
        string realmLabel;
        string season;
        address tyrant;
        address keeper;
        address attester;
        IWorldID worldId;
        uint256 externalNullifierHash;
        uint64 seasonStart;
        uint64 seasonEnd;
        uint64 powerCooldown;
        uint64 ballotDuration;
        uint64 concedeImmunity;
        uint32 minYesVotes;
    }

    /// @notice The contracts a season consists of.
    struct Deployed {
        FealtyCourt court;
        ITextSetter bannerResolver;
        ITextSetter decreeResolver;
        Throne throne;
    }

    /// @notice How long the season label outlives the season in the realm.
    uint64 internal constant LABEL_GRACE = 30 days;

    /// @notice Deploys a season. Plain contract calls only, so tests can run the same code the
    ///         script runs. The creator must hold `ROLE_REGISTRAR` on the realm.
    function deploy(Params memory p) public returns (Deployed memory d) {
        address predicted = vm.computeCreateAddress(p.creator, vm.getNonce(p.creator) + _nonceOffset());

        d.court = new FealtyCourt(p.labelStore, predicted, Powers.throneRootRoles());
        d.bannerResolver = _resolver(p, predicted, 1);
        d.decreeResolver = _resolver(p, predicted, 2);

        d.throne = new Throne(
            Throne.Config({
                court: d.court,
                worldId: p.worldId,
                tyrant: p.tyrant,
                keeper: p.keeper,
                attester: p.attester,
                bannerResolver: d.bannerResolver,
                decreeResolver: d.decreeResolver,
                realm: IRegistry(address(p.realm)),
                seasonLabel: p.season,
                courtDnsSuffix: dnsEncode3(p.season, p.realmLabel, "eth"),
                externalNullifierHash: p.externalNullifierHash,
                seasonStart: p.seasonStart,
                seasonEnd: p.seasonEnd,
                powerCooldown: p.powerCooldown,
                ballotDuration: p.ballotDuration,
                concedeImmunity: p.concedeImmunity,
                minYesVotes: p.minYesVotes
            })
        );
        require(address(d.throne) == predicted, "Throne address prediction failed");

        // Owner holds no roles on the season label: the court is attached for good.
        p.realm.register(p.season, p.creator, d.court, address(0), 0, p.seasonEnd + LABEL_GRACE);
    }

    /// @dev Nonces the creator spends before the Throne. A broadcast sends one transaction each for
    ///      the court and the two resolver proxies, so the Throne is the creator's fourth. Test
    ///      contexts that call from a contract instead of an EOA count differently and override this.
    ///      A wrong value cannot go unnoticed: the Throne's constructor reverts unless the court
    ///      granted its roles to the address it actually landed on.
    function _nonceOffset() internal view virtual returns (uint256) {
        return 3;
    }

    /// @dev Deploys a verifiable proxy of the shared PermissionedResolver where only the Throne may
    ///      set text. Nobody gets an upgrade role, so the proxy can never be replaced.
    function _resolver(Params memory p, address throneAddr, uint256 salt) internal returns (ITextSetter) {
        Grant[] memory grants = new Grant[](1);
        grants[0] = Grant({account: throneAddr, roleBitmap: PermissionedResolverLib.ROLE_SET_TEXT});
        return ITextSetter(
            p.factory.deployProxy(
                p.resolverImpl,
                salt,
                abi.encodeCall(IPermissionedResolverInitializable.initialize, (grants, new bytes[](0)))
            )
        );
    }

    /// @notice Broadcasts a season deployment using the environment (see `.env.example`).
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address deployer = vm.addr(pk);
        string memory mode = vm.envString("WORLD_MODE");
        bool onchain = keccak256(bytes(mode)) == keccak256("onchain");
        require(onchain || keccak256(bytes(mode)) == keccak256("attested"), "WORLD_MODE must be onchain or attested");

        Params memory p = _paramsFromEnv(deployer, onchain);

        vm.startBroadcast(pk);
        Deployed memory d = deploy(p);
        vm.stopBroadcast();

        _write(p, d, onchain ? "onchain" : "attested");
        console.log("Court: ", address(d.court));
        console.log("Throne:", address(d.throne));
        console.log("Name:  ", string.concat(p.season, ".", p.realmLabel, ".eth"));
    }

    /// @dev Builds the parameters from the environment, one field at a time to keep the stack shallow.
    function _paramsFromEnv(address deployer, bool onchain) internal view returns (Params memory p) {
        string memory realmState = vm.readFile(realmFile());
        p.creator = deployer;
        p.realm = FealtyRealm(vm.parseJsonAddress(realmState, ".realm"));
        p.realmLabel = vm.parseJsonString(realmState, ".label");
        p.labelStore = ILabelStore(ensAddress("LabelStore"));
        p.factory = VerifiableFactory(ensAddress("VerifiableFactory"));
        p.resolverImpl = ensAddress("PermissionedResolverImpl");
        p.season = vm.envString("SEASON");
        p.tyrant = vm.addr(vm.envUint("TYRANT_PK"));
        p.keeper = vm.addr(vm.envUint("KEEPER_PK"));
        p.attester = onchain ? address(0) : vm.addr(vm.envUint("ATTESTER_PK"));
        p.worldId = onchain ? IWorldID(vm.envOr("WORLD_ROUTER", SEPOLIA_WORLD_ROUTER)) : IWorldID(address(0));
        p.externalNullifierHash = vm.envUint("WORLD_EXTERNAL_NULLIFIER");
        p.seasonStart = uint64(vm.envOr("SEASON_START", block.timestamp));
        p.seasonEnd = p.seasonStart + uint64(vm.envOr("SEASON_DURATION_S", uint256(1800)));
        p.powerCooldown = uint64(vm.envOr("POWER_COOLDOWN_S", uint256(45)));
        p.ballotDuration = uint64(vm.envOr("BALLOT_DURATION_S", uint256(120)));
        p.concedeImmunity = uint64(vm.envOr("CONCEDE_IMMUNITY_S", uint256(60)));
        p.minYesVotes = uint32(vm.envOr("MIN_YES_VOTES", uint256(1)));
    }

    /// @notice Renders the deployment record the TypeScript packages load (`DeploymentSchema`).
    function render(Params memory p, Deployed memory d, string memory mode) public view returns (string memory out) {
        out = string.concat("{", _kvUint("chainId", block.chainid), ',"season":"', p.season);
        out = string.concat(out, '","realmLabel":"', p.realmLabel, '",', _kvUint("deployBlock", block.number));
        out = string.concat(out, ',"addresses":', _addressesJson(p, d));
        out = string.concat(out, ',"config":', _configJson(p, mode));
        out = string.concat(
            out, ',"throneAbiHash":"', vm.toString(keccak256(bytes(vm.readFile("out/Throne.sol/Throne.json")))), '"}'
        );
    }

    function _addressesJson(Params memory p, Deployed memory d) private view returns (string memory s) {
        s = string.concat("{", _kv("labelStore", address(p.labelStore)), ",", _kv("factory", address(p.factory)));
        s = string.concat(s, ",", _kv("resolverImpl", p.resolverImpl), ",", _kv("realm", address(p.realm)));
        s = string.concat(s, ",", _kv("court", address(d.court)), ",", _kv("throne", address(d.throne)));
        s = string.concat(
            s, ",", _kv("bannerResolver", address(d.bannerResolver)), ",", _kv("decreeResolver", address(d.decreeResolver))
        );
        s = string.concat(s, ",", _kv("worldId", address(p.worldId)), ",", _kv("ethRegistry", ensAddress("ETHRegistry")));
        s = string.concat(s, ",", _kv("universalResolver", ensAddress("UniversalResolverV2")), "}");
    }

    function _configJson(Params memory p, string memory mode) private pure returns (string memory s) {
        s = string.concat("{", _kv("tyrant", p.tyrant), ",", _kv("keeper", p.keeper), ",", _kv("attester", p.attester));
        s = string.concat(s, ',"worldMode":"', mode, '","externalNullifierHash":"', vm.toString(p.externalNullifierHash), '"');
        s = string.concat(s, ",", _kvUint("seasonStart", p.seasonStart), ",", _kvUint("seasonEnd", p.seasonEnd));
        s = string.concat(s, ",", _kvUint("powerCooldown", p.powerCooldown), ",", _kvUint("ballotDuration", p.ballotDuration));
        s = string.concat(s, ",", _kvUint("concedeImmunity", p.concedeImmunity), ",", _kvUint("minYesVotes", p.minYesVotes), "}");
    }

    function _kv(string memory k, address v) private pure returns (string memory) {
        return string.concat('"', k, '":"', vm.toString(v), '"');
    }

    function _kvUint(string memory k, uint256 v) private pure returns (string memory) {
        return string.concat('"', k, '":', vm.toString(v));
    }

    function _write(Params memory p, Deployed memory d, string memory mode) internal {
        vm.createDir(deploymentsDir(), true);
        vm.writeFile(seasonFile(p.season), render(p, d, mode));
    }
}
