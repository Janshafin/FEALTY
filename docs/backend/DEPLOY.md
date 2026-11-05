# Deploying FEALTY to Sepolia

Everything is read from `.env` (copy `.env.example`) and from the pinned ENSv2 deployment set. No address is
hard-coded. Run every command from `contracts/`.

## 0. One-time setup

```bash
git submodule update --init contracts/lib/contracts-v2
git -C contracts/lib/contracts-v2 submodule update --init --depth 1 \
  contracts/lib/forge-std contracts/lib/openzeppelin-contracts contracts/lib/openzeppelin-contracts-upgradeable \
  contracts/lib/openzeppelin-contracts-v4 contracts/lib/solady contracts/lib/verifiable-factory contracts/lib/ens-contracts
forge build
```

Fund these with Sepolia ETH (about 0.2 each is plenty): `DEPLOYER_PK` (also pays the NPC funding, so give it ~0.3),
`TYRANT_PK`, `KEEPER_PK`, `FAUCET_PK`. Use four different keys.

## 1. Dry run against a fork (no broadcast)

```bash
forge script script/DeployRealm.s.sol --sig "commit()"   --rpc-url $SEPOLIA_RPC_URL
```

Forge simulates the whole thing and prints what would happen. Nothing is sent without `--broadcast`.

## 2. Register the realm name (two steps)

`<REALM_LABEL>.eth` is bought with the registrar's commit/reveal flow, paid in MockUSDC that the script mints.

```bash
forge script script/DeployRealm.s.sol --sig "commit()"   --rpc-url $SEPOLIA_RPC_URL --broadcast
# the script prints MIN_COMMITMENT_AGE in seconds: wait that long
forge script script/DeployRealm.s.sol --sig "register()" --rpc-url $SEPOLIA_RPC_URL --broadcast
```

If the script says the label is taken, change `REALM_LABEL` and start again. State is saved to
`deployments/11155111/realm.json` (commit it; it holds no secret that matters on a testnet).

## 3. Deploy a season

Set `WORLD_MODE` and `WORLD_EXTERNAL_NULLIFIER` from the World spike result (`research/proof.md` S2).

```bash
forge script script/DeploySeason.s.sol --rpc-url $SEPOLIA_RPC_URL            # simulate first
forge script script/DeploySeason.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

This deploys the court, two resolver proxies, the Throne, and attaches the court to `<SEASON>.<REALM_LABEL>.eth`.
It writes `deployments/11155111/<SEASON>.json`, which the TypeScript packages load.

The Throne address is predicted from the deployer's nonce (court, then two proxies, then the Throne = +3).
If that count were wrong, the Throne's constructor reverts during simulation and nothing is broadcast.

## 4. Seed NPC vassals (demo map)

```bash
forge script script/SeedCourt.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

Edit `scripts/seed/npcs.json` first: those labels and banners are placeholders.

## 5. Check it worked

```bash
cast call <throne> "powersRemaining()(uint256)" --rpc-url $SEPOLIA_RPC_URL     # 3
cast call <court>  "isEmancipated()(bool)"      --rpc-url $SEPOLIA_RPC_URL     # false
npx tsx scripts/spikes/s1-resolve.ts <label>.<season>.<realm>.eth              # banner text via UniversalResolverV2 (script added in task T1)
```

Record the transaction hashes in `research/proof.md`.

## 6. Irreversible: lock the realm (optional, human decision)

After this nobody can point `<realm>.eth` at a different registry. Do it only when you are sure.

```bash
CONFIRM_IRREVERSIBLE_LOCK=yes forge script script/LockRealm.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

## New season

Change `SEASON` (for example `s2`) and run step 3 again; the realm and its name are reused.
