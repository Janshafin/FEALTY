# FEALTY: backend plan

Scope: everything except game graphics and UI. That covers the contracts, deployment, the ENS wiring, World ID, Arkiv, the off-chain server (keeper, Tyrant bot, chronicle, faucet, World signing), the read API, the E2E proof, and the sponsor documents.

The game design comes from [`docs/planning/PLAN.md`](../planning/PLAN.md), which is the approved FEALTY direction. [`docs/planning/final.md`](../planning/final.md) ("Hungry Warlord", 0G) is an **earlier, superseded** direction. Ignore it.

The executable prompts for the Sonnet model are in [`SONNET_PROMPTS.md`](SONNET_PROMPTS.md). This file is the spec those prompts point to. If the two disagree, this file wins.

---

## 0. Constraints that shape every decision

| Constraint | Consequence |
|---|---|
| Deadline **Sat Nov 7, 09:00 IST**. No late submissions | The backend must reach feature freeze with time left for UI. Section 9 lists what to cut first. |
| ETHGlobal requires steady git history and an AI disclosure. Humans must make meaningful contributions | Sonnet **proposes** each commit and a human reviews it, then commits. Prompts and plans are committed in `docs/`. Section 10 lists the decisions humans own. |
| ENS requires ENSv2 on Sepolia, no hard-coded values, and a live demo | Every address comes from `deployments/*.json` or `.env`. The ENSv2 core addresses come from the pinned `contracts-v2` deployment set. |
| Arkiv requires SDK writes to Rabdi, user-facing reads, and `/arkiv/*` documents | Manifestos, Pledges, and Chronicle are real Rabdi entities. The keeper and the read API query them. |
| World requires IDKit, onchain or server verification, failure paths, and a debrief | The vote proof is verified **onchain** by `Throne` (Mode A). Mode B is a server-attested fallback. |
| The `contracts-v2` repo's `AGENTS.md` says never to edit anything under `contracts/lib/` | All fixes live in our code. |

---

## 1. Verified facts this plan relies on (checked 2026-11-06)

**ENSv2.** Pinned library: `contracts/lib/contracts-v2` at commit `07e55a05…`. The Sepolia set was deployed 2026-10-01 and is listed in `contracts/lib/contracts-v2/contracts/docs/addresses/sepolia.md`.

| Contract | Sepolia address |
|---|---|
| ETHRegistry | `0xd4ebcbbdf463c9c45784603db0ddd499bc44a8b4` |
| ETHRegistrar (commit/reveal, pays in ERC20) | `0xf633e7fc17e2bbe0d0965d18ec1821dcb754a3d3` |
| MockUSDC (public `mint`) | `0x240b0316df57887dbbe58b586508b19e633a14aa` |
| LabelStore (`setLabel` is permissionless) | `0xed8246ff02203a4d4cb262bd78beaa7408a57cae` |
| PermissionedResolverImpl | `0x115eb53f0c60696633855f90b138178fb40b2b2c` |
| UserRegistryImpl | `0x9bd8a88719068d09ecee662f36c0e3856708366a` |
| VerifiableFactory (`deployProxy(impl, salt, initData)`) | `0xda70306c98e97ece36f997a21368e53298572991` |
| UniversalResolverV2 proxy | `0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe` |
| UniversalHelper | `0xd453e5bdb62cc3bea84341b1e306319c8ffd7dfe` |

These semantics come from reading the source, and the design depends on them:
- **Root roles apply to every name.** `_effectiveRoles = roles[ROOT] | roles[resource]`.
- **Granting or revoking role X needs X's admin bit** (`X << 128`). If the Throne revokes both `X` and `X_ADMIN` from itself and is the only holder, **no account can ever grant X again**. This is the irreversibility guarantee.
- **`_register` grants the new owner's `roleBitmap` without an admin check.** The registrar can therefore give token-level roles to *the name it is registering*. That cannot touch other vassals' tokens, but it means the Throne's vassal role bitmap must be a constant in code.
- **`unregister` burns the token, bumps both versions, and sets `expiry = now`.** The name stops resolving right away.
- **`setResolver` and `setSubregistry` need the role on root or on the token.**
- **`isEmancipated()`** is true exactly when no account holds any root role in `UNEMANCIPATED_ROLE_BITMAP` (SET_SUBREGISTRY, SET_RESOLVER, UNREGISTER, their admins, CAN_TRANSFER_ADMIN, UPGRADE, UPGRADE_ADMIN). If the Throne holds only the three powers from that set, **stripping all three makes ENSv2 itself report the court as emancipated.** This is the "total victory" moment.
- **Tokens regenerate**: the tokenId changes whenever roles change. Always address names by **label-derived `anyId`** (`LibLabel.id(label)`), never by a cached tokenId.
- **`ETHRegistrar.register` grants the `.eth` owner** SET_SUBREGISTRY(+admin), SET_RESOLVER(+admin), and CAN_TRANSFER_ADMIN. Registration is commit/reveal and is paid in MockUSDC, which anyone can mint.
- **`PermissionedResolver.setText` is permissioned per text *key*, not per name.** A shared resolver therefore cannot give each vassal sole control of their own record. The Throne writes banners for vassals instead (section 3.4).
- **Our contracts use `pragma solidity 0.8.25`**, the exact pin ENSv2 uses, with `evm_version = cancun` and no via-IR.

**World ID.**
- The legacy (v3) router on Ethereum Sepolia is `0x469449f251692e0779667583026b5a1e99512157`. Its signature is `verifyProof(root, groupId=1, signalHash, nullifierHash, externalNullifierHash, uint256[8] proof)`, a view that reverts on failure.
- IDKit 4.x (`@worldcoin/idkit`, `@worldcoin/idkit-core`):
  - A request needs a backend-signed `rp_context` from `signRequest({signingKeyHex, action})` in `@worldcoin/idkit-core/signing`.
  - Legacy proofs are requested with `allow_legacy_proofs: true` and `preset: orbLegacy({ signal })`.
  - The response has `responses[i].{signal_hash, proof (abi-encoded), merkle_root, nullifier}`.
  - The server-side check is `POST https://developer.world.org/api/v4/verify/{rp_id}`.
- **Not verified yet:** whether staging/simulator legacy proofs pass the Sepolia router, and how the v3 external nullifier is derived for a v4 (rp_id) app. Spike S2 settles both.

**Arkiv (Rabdi testnet).**

| Item | Value |
|---|---|
| Chain id | `7794095` |
| RPC | `https://rpc.rabdi.db-chain.testnet.arkiv.network` |
| Explorer | `https://rabdi.explorer.arkiv.network` |
| Faucet and access keys | `hub.arkiv.network` |
| Gas token | tGLM |
| Block time | 2 s |

- Clients:
  - `createPublicClient` / `createWalletClient` from `@arkiv-network/sdk` (viem-based)
  - `rabdi({ accessKey })` from `@arkiv-network/sdk/chains`
- Schemas: `defineSchema(name, cols)` from `@arkiv-network/sdk/schema`. Column types are `str() addr() i32() dec() bool() bytes() key()`, with `.indexed() .optional() .default()`.
- Writes:
  - `walletClient.createEntity(Schema, values, { expiration: ExpirationTime.fromSeconds(n) })` returns `{ entityKey, txHash, expiresAt }`.
  - `executeBatch({creates, patches, extensions, ownershipChanges, deletes})` is atomic.
  - `extendEntity` is owner-only.
- Reads:
  - `publicClient.select().from(Schema).where(and(eq(..), gt(..))).ownedBy(addr).fetch()`. You can filter on `$expiresAt`.
  - `publicClient.watchEntityEvents({ onEntityCreated, onEntityPatched, onEntityDeleted, ... })`.
- Limits and behavior:
  - **No event fires on expiry.**
  - `fromSeconds` must be a multiple of 2.
  - The maximum lifetime is about 182.5 days.
- Docs: https://docs.arkiv.network.

---

## 2. System architecture

```
                       ┌──────────────── Ethereum Sepolia (ENSv2) ────────────────┐
 ETHRegistry ── fealty.eth ──subregistry──▶ FealtyRealm (PermissionedRegistry)     │
                                                │  "s1" ──subregistry──▶ FealtyCourt (season 1)
                                                │                         │ names: alice.s1.fealty.eth …
                                                │                         │ root roles held ONLY by Throne
   WorldIDRouter v3 ◀── verifyProof ── Throne (season 1) ──revokeRootRoles──┘
                                         │  ├─ bannerResolver (PermissionedResolver proxy)
                                         │  └─ decreeResolver (PermissionedResolver proxy)
                       └──────────────────┼───────────────────────────────────────────┘
          openBallot (keeper only)        │ events
                                          ▼
 ┌──────────────── services/server (Node 22+, TypeScript, one process) ──────────────┐
 │ keeper     : Arkiv pledge quorum ─▶ Throne.openBallot ; resolve expired ballots   │
 │ tyrant     : scripted Tyrant bot, uses powers through Throne (tyrant key)         │
 │ chronicle  : mirrors Throne events ─▶ Arkiv Chronicle entities                    │
 │ http API   : /world/rp-context, /world/attest (Mode B), /faucet, /realm, /stream  │
 └───────────────────────────────────────────────────────────────────────────────────┘
                       ┌──────────────── Arkiv Rabdi ────────────────┐
                       │ Manifesto (TTL ≈ campaign) — owned by rebel │
                       │ Pledge    (TTL = manifesto) — owned by vassal│
                       │ Chronicle (TTL = season+7d) — owned by keeper│
                       └──────────────────────────────────────────────┘
```

**Trust model** (this goes verbatim into the README):
- **ENS is the authority.** Powers *are* EAC roles, so their loss is provable on Sepolia and cannot be undone by anyone, including the FEALTY team. That holds because the Throne holds the only admin bits and has no upgrade or owner path. Once the realm lock (section 3.6) is applied, the team also cannot re-point `s1.fealty.eth` to a different court.
- **World → ENS is trustless (Mode A).** The vote proof is verified on the same chain, inside the same transaction path that strips the role.
- **Arkiv → ENS is trusted for liveness only.** The keeper decides *when* a ballot opens, based on an Arkiv quorum anyone can audit, because the ballot records the manifesto's entity key. It cannot cast votes. A ballot also needs `minYesVotes` from World-verified humans.
- **Mode B** (used only if spike S2 fails) adds a trusted attester. This is disclosed.

---

## 3. Contracts (Foundry, `contracts/`)

### 3.1 Files
```
contracts/
  foundry.toml                 # add solc = "0.8.25", fs_permissions for deployments/, sepolia rpc
  src/FealtyCourt.sol          # EXISTS — unmodified PermissionedRegistry; keep as is
  src/FealtyRealm.sol          # unmodified PermissionedRegistry for "<season>.fealty.eth" labels
  src/Throne.sol               # the game rules + only root-role holder of the court
  src/libraries/Powers.sol     # Power enum ↔ role bit mapping, constants
  src/libraries/ByteHasher.sol # hashToField (World)
  src/interfaces/IWorldID.sol  # EXISTS
  script/Config.s.sol          # reads env + pinned ENSv2 sepolia addresses
  script/DeployRealm.s.sol     # register fealty.eth (commit/reveal) + deploy realm + link
  script/DeploySeason.s.sol    # court + resolvers + Throne (address prediction) + realm label
  script/LockRealm.s.sol       # irreversible: revoke our SET_SUBREGISTRY(+admin) on fealty.eth
  script/SeedCourt.s.sol       # NPC vassals for a living map (demo)
  test/Throne.t.sol            # unit (local ENSv2 stack: LabelStore + court + resolver impl)
  test/Irreversibility.t.sol   # the core claim, incl. fuzz on who can re-grant
  test/WorldVote.t.sol         # mock IWorldID; nullifier/eligibility rules
  test/fork/SepoliaFork.t.sol  # real ENSv2 + real WorldIDRouter on a Sepolia fork
deployments/<chainId>/<season>.json   # written by scripts, read by server (no hard-coding)
```

### 3.2 Roles
`Powers.sol`:

| Power | id | Role bit | Effect |
|---|---|---|---|
| BANISH | 0 | `ROLE_UNREGISTER` | `court.unregister(id)`: the name stops resolving |
| DECREE | 1 | `ROLE_SET_RESOLVER` | Points the vassal's name at `decreeResolver`, which holds the Tyrant's proclamation |
| DISSOLVE | 2 | `ROLE_SET_SUBREGISTRY` | `court.setSubregistry(id, 0)`: the vassal's house (sub-names) vanishes |

- **Throne root roles:** `ROLE_REGISTRAR | ROLE_SET_PARENT | Σ(power | power_ADMIN)`. Never grant `REGISTRAR_ADMIN`, `CAN_TRANSFER_ADMIN`, `UPGRADE*`, `SET_URI*` or `RENEW*`. Nobody else holds any root role.
- **Vassal token roles** (a constant): `ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY`. There is no admin bit, no `UNREGISTER`, and no `CAN_TRANSFER_ADMIN`, so names are **soulbound**.
  - Vassals rule their own banner and house.
  - The Tyrant's root powers override them.
  - Once a power is stripped, the vassal's own token role is the only authority left. This is emancipation in exactly ENSv2's sense.

### 3.3 Genesis (no circular deployment)
`Throne` cannot `new FealtyCourt` because the runtime size would pass 24 KB. The deploy script does this instead:
1. Predict `throneAddr = vm.computeCreateAddress(deployer, nonce + 3)`. Use the exact offset that matches the script's transaction order, and assert it.
2. Deploy `FealtyCourt(labelStore, throneAddr, THRONE_ROOT_ROLES)`.
3. Deploy the `bannerResolver` and `decreeResolver` proxies with `VerifiableFactory.deployProxy(PermissionedResolverImpl, salt, initialize([Grant(throneAddr, ROLE_SET_TEXT)], []))`.
   - Grant **no** `ROLE_UPGRADE` to anyone.
   - Grant no `ROLE_SET_TEXT_ADMIN`.
4. Deploy `Throne(cfg)`. `require(address(this) == predicted)` is implicit.
   - The constructor **asserts** that the court gives Throne exactly `THRONE_ROOT_ROLES`.
   - It asserts each of those roles has **exactly one** assignee (`getAssigneeCount(0, bit)`).
   - It asserts `court.isEmancipated() == false`.
   - This makes the genesis check verifiable onchain.
5. Call `court.setParent(realm, "s1")` through the Throne, in the constructor or a one-shot `init()`. This keeps ENSv2 canonical-name lookups correct.

### 3.4 `Throne` specification

```solidity
contract Throne {
  // ── immutables (constructor Config) ─────────────────────────────
  FealtyCourt court; IWorldID worldId; address tyrant; address keeper;
  address attester;            // 0 ⇒ Mode A (onchain World verification) only
  IPermissionedResolver bannerResolver; IPermissionedResolver decreeResolver;
  uint256 externalNullifierHash;  // precomputed off-chain, verified in spike S2
  uint64 seasonStart; uint64 seasonEnd;
  uint64 powerCooldown;        // per power, seconds
  uint64 ballotDuration;       // seconds
  uint64 manifestoGrace;       // keeper may open ballots only until seasonEnd - ballotDuration
  uint32 minYesVotes;          // absolute floor of World-verified yes votes
  bytes  courtDnsSuffix;       // DNS-encoded "s1.fealty.eth" (storage, set in constructor)

  // ── state ───────────────────────────────────────────────────────
  struct Vassal { string label; uint64 joinedAt; bool banished; address house; }
  mapping(address => Vassal) vassals;  mapping(bytes32 labelHash => address) byLabel;
  uint32 liveVassals;
  mapping(Power => uint64) lastUsed;
  struct Ballot { Power power; bytes32 manifestoKey; uint32 pledges; uint64 openedAt;
                  uint64 deadline; uint32 electorate /* liveVassals at open */;
                  uint32 yes; uint32 no; bool resolved; bool passed; }
  Ballot[] ballots;  uint256 activeBallotId (0 = none; ids start at 1)
  mapping(uint256 ballotId => mapping(uint256 nullifier => bool)) nullifierUsed;
  mapping(uint256 ballotId => mapping(address => int8)) voteOf; // 0 none, 1 yes, -1 no
  Outcome outcome; // Undecided | RebelsWin | TyrantWins | Emancipated
}
```

**Vassal actions:**
- `join(string label, string banner)`
  - Season must be active.
  - The caller must not already be a vassal and must not be banished this season (`BanishedThisSeason`).
  - Label: 3–20 chars of `[a-z0-9-]`, not starting or ending with `-`. Check with a cheap byte loop.
  - Calls `court.register(label, msg.sender, IRegistry(0), bannerResolver, VASSAL_ROLES, seasonEnd)`.
  - Writes `bannerResolver.setText(dnsName(label), "fealty.banner", banner)` and `"fealty.joined"`.
  - Emits `Joined`.
- `setBanner(string)`: vassal only. Rewrites the banner text in `bannerResolver`.
  - If the vassal is currently decreed, the new text is invisible until they restore the resolver themselves with `court.setResolver(id, bannerResolver)`, a direct ENSv2 call using their token role.
- Houses (P1): the vassal deploys a `UserRegistry` proxy via `VerifiableFactory` from the client or server helper, then calls `court.setSubregistry`. `Throne.registerHouse(house)` records it for the game indexer. The Throne trusts nothing about it.

**Tyrant actions** (all `onlyTyrant`, season active, per-power cooldown, `powerAlive(p)`; otherwise revert `PowerStripped(p)`):
- `banish(address v)`:
  - `court.unregister(id)`, then mark the vassal `banished` and do `liveVassals--`.
  - **If `v` voted in the active ballot, remove that vote.** This is the "banish the ringleaders" counterplay.
  - Emits `Banished`.
- `decree(address v, string proclamation)`: `decreeResolver.setText(dnsName, "fealty.banner", proclamation)`, then `court.setResolver(id, decreeResolver)`. Emits `Decreed`.
- `dissolve(address v)`: `court.setSubregistry(id, IRegistry(address(0)))`, then clear `house`. Emits `Dissolved`.
- `concede(Power p)` (P1): voluntarily strips `p`. It cancels the active ballot and blocks new ballots for `concedeImmunity` seconds.

**Politics:**
- `openBallot(Power p, bytes32 manifestoKey, uint32 pledges)`, `onlyKeeper`:
  - `p` must be alive, there must be no active ballot, and `block.timestamp + ballotDuration <= seasonEnd`.
  - Emits `BallotOpened(id, p, manifestoKey, pledges, deadline)`.
- `vote(uint256 id, bool support, uint256 root, uint256 nullifierHash, uint256[8] calldata proof)` (Mode A):
  - Requires a live vassal: `court.getOwner(LibLabel.id(label)) == msg.sender`, not banished, and `joinedAt < ballot.openedAt` (this blocks rejoin-to-vote sybils).
  - The ballot must be active and not past its deadline. The voter must not have voted, and the nullifier must not be used for this ballot.
  - Calls `worldId.verifyProof(root, 1, hashToField(signalBytes(msg.sender, id, support)), nullifierHash, externalNullifierHash, proof)`.
  - The `signalBytes` encoding is **fixed by spike S2** to match IDKit's `signal_hash`. Default candidate: the UTF-8 bytes of `"<0xaddress lowercase>:<id>:<1|0>"`.
  - Emits `Voted(id, voter, support, nullifierHash)`.
- `voteAttested(...)` (Mode B, only if `attester != 0`): the same rules, but the proof is replaced by an EIP-712 signature from `attester` over `(voter, id, support, nullifierHash, expiry)`.
- `resolve(uint256 id)`: anyone may call it after the deadline, **or early** once `yes >= minYesVotes && yes > electorate / 2`.
  - The ballot passes if `yes >= minYesVotes && yes > no`.
  - On pass, call `court.revokeRootRoles(bit | bit << 128, address(this))` and emit `PowerStripped(p, id)`.
  - Recompute `outcome`: `stripped >= 2` gives RebelsWin, and **all 3 stripped while `court.isEmancipated()`** gives Emancipated.
- `finalize()`: anyone may call it after `seasonEnd`. The Tyrant wins if 2 or more powers remain.

**Views** (the server and UI read these, so no logic is duplicated):
- `powerAlive(p)`, which returns `court.hasRootRoles(bit, address(this))`. This makes ENS the source of truth, not a boolean we store.
- `powersRemaining()`, `getVassal(addr)`, `getBallot(id)`, `activeBallot()`, `cooldownRemaining(p)`, `isEligible(addr, id)`, and `dnsName(label)`.

**Errors and events:** use custom errors throughout. Every state change emits an event that carries enough data for the Chronicle mirror without extra reads.

**Non-goals:** no owner, no pause, no upgrade, no `receive`. The Tyrant is a fixed address because the bot is the demo Tyrant.

### 3.5 Tests (must pass before deploy)

**`Irreversibility.t.sol`** (the headline claim):
- Strip each power, then check:
  - The Tyrant action reverts.
  - `grantRootRoles(bit, x)` reverts for the Throne, the deployer, and a fuzzed `x` caller.
  - `hasRootRoles` is false and `getAssigneeCount` is 0.
- Stripping all three makes `isEmancipated()` true.
- A vassal can still use their own token role after the power is stripped.

**`Throne.t.sol`:**
- join: label rules, duplicates, re-join after banish blocked.
- Soulbound names: `safeTransferFrom` reverts.
- Banish: the name stops resolving and vote removal works.
- Decree: the resolver changes and the vassal can restore it.
- Dissolve.
- Cooldowns, season bounds, and `onlyTyrant` / `onlyKeeper`.

**`WorldVote.t.sol`** (uses a mock router):
- Double vote by the same nullifier reverts. So does voting from a second wallet with the same nullifier.
- A vassal who joined after the ballot opened is ineligible. So is a banished vassal.
- Early resolve, the deadline path, the `minYesVotes` floor, and the outcome transitions.

**`SepoliaFork.t.sol`** (`--fork-url $SEPOLIA_RPC_URL`):
- Deploy the season against the **real** LabelStore, factory, and resolver impl.
- Register, unregister, and strip.
- Check that `UniversalResolverV2` resolves `alice.s1.fealty.eth` text through the real ETHRegistry **if** the realm already exists on Sepolia.
- `vm.skip` otherwise.

**Gas:** `forge snapshot` for join, vote, and resolve. Keep join under 400k gas.

### 3.6 Realm and season deployment (Sepolia)

**`DeployRealm.s.sol`** (run once):
1. Mint MockUSDC and approve the registrar.
2. `commit(makeCommitment(REALM_LABEL, deployer, secret, realm, 0, 1y, 0))`. Wait at least the minimum commitment age; the script runs in two invocations because of `--broadcast` timing. Then `register(...)`.
   - The `FealtyRealm` is deployed first with `rootRoles = ROLE_REGISTRAR` only. It has **no** SET_SUBREGISTRY, UNREGISTER, or admins.
   - A realm label's subregistry is set once at registration and can never change.

**`DeploySeason.s.sol <season>`:** runs section 3.3, then `realm.register(season, throne, court, 0, 0, seasonEnd + 30d)`, then writes `deployments/11155111/<season>.json` (all addresses, block numbers, config values, and the ABI hash).

**`LockRealm.s.sol`** (P1, irreversible, done only after a human signs off): `ETHRegistry.revokeRoles(fealtyId, SET_SUBREGISTRY|ADMIN, deployer)`. After this, nobody (including us) can swap the realm, so a season's court can never be replaced.

**`SeedCourt.s.sol`:** 6–10 NPC vassals from `NPC_MNEMONIC`, with banners. NPCs can pledge on Arkiv but **cannot vote** because they have no World ID. That limit is the point. The README says so.

---

## 4. Arkiv layer (`packages/shared/src/arkiv/`)

**Schemas.** Names are versioned, and every one is `.indexed()` where it is filtered on:

| Schema | Owner (signer) | Columns | Expiration |
|---|---|---|---|
| `fealty.v1.manifesto` | the rebel vassal | `season str!`, `court addr!`, `power i32!`, `author addr!`, `title str`, `text str`, `authorName str` | `MANIFESTO_TTL_S` (default 180 s; even number) |
| `fealty.v1.pledge` | the pledging vassal | `season str!`, `manifesto key!`, `power i32!`, `pledger addr!` | `ExpirationTime.atBlock(manifesto.expiresAt)`, so it dies with its manifesto |
| `fealty.v1.chronicle` | the keeper wallet | `season str!`, `kind str!`, `actor addr!`, `target addr`, `power i32`, `ballot i32`, `txHash str`, `text str` | `seasonEnd + 7d` (cap at `MAX_LIFETIME`) |

(`!` = indexed)

**Validity rules.** The keeper applies these and the UI shows them:
- A pledge counts only if:
  - Its Arkiv **owner** equals `pledger`. This blocks forged pledges.
  - The owner is a **live vassal** of this season's court, checked on Sepolia.
  - The owner is **not currently decreed**, meaning their resolver is `bannerResolver`.
  - Each owner is counted once per manifesto.
  - The manifesto is not expired and its author is still a live vassal.
- Momentum = valid pledges ÷ `QUORUM_PLEDGES`.
- Chronicle reads always add `.ownedBy(KEEPER_ADDRESS)`, so spoofed entries are ignored.

**Why Arkiv** (one line per criterion for `/arkiv/why-arkiv.md`):
- TTL equals the campaign window, so there is no cleanup.
- Only the owner can delete, so the Tyrant and the operators cannot censor organizing.
- Any client can read the realm's politics with a single query.

**Required documents** at repo root `/arkiv/`:
- `schema.md`
- `friction.md`, kept live during the build; record every rough edge immediately
- `reach.md`
- `why-arkiv.md`
- `usage.md` (writer wallet addresses plus a runnable query snippet)
- `README` section

---

## 5. Server (`services/server/`, TypeScript, Node ≥ 22)

One process, with modules started by flags. It can be deployed to Railway or Fly as a single service.

| Module | Responsibility | Details |
|---|---|---|
| `config.ts` | Loads `.env` and `deployments/11155111/<SEASON>.json` | Validates with zod and fails fast. **No addresses in code.** |
| `chain.ts` | viem clients | Sepolia public and wallet clients for the keeper, tyrant, and faucet keys. Typed ABIs come from `packages/shared`. |
| `arkiv.ts` | Arkiv public and wallet clients (keeper key) | Retry with backoff on rate limits. |
| `keeper.ts` | Loop every `KEEPER_INTERVAL_MS` (4000) | 1. Query live manifestos for the season. 2. Count valid pledges. 3. If any manifesto reaches quorum, there is no active ballot, and its power is alive, call `openBallot(power, manifestoKey, pledges)`. On a tie, take the oldest. 4. If the active ballot is past its deadline, or eligible for early resolve, call `resolve`. 5. After `seasonEnd`, call `finalize`. It must be **idempotent** and survive restarts by reading state from the chain, not from memory. |
| `tyrant.ts` | Scripted Tyrant | Deterministic policy (section 5.1), rate-limited, `TYRANT_ENABLED` flag, decision log. Each decision is written to the Chronicle with a taunt. |
| `chronicle.ts` | Mirrors Throne events to Arkiv | `watchContractEvent` plus a backfill from the deployment block. Each event becomes a `chronicle` entity, batched with `executeBatch` every 2 s. Dedupe key = `txHash:logIndex`. |
| `world.ts` | World ID | `POST /world/rp-context {action}` returns `signRequest`. `POST /world/attest` (Mode B only) verifies via `developer.world.org/api/v4/verify/{rp_id}`, checks the action and signal, then signs EIP-712. |
| `faucet.ts` | Onboarding | `POST /faucet {address}` drips `FAUCET_SEPOLIA_WEI` (0.003 ETH) and `FAUCET_TGLM` once per address. A per-IP limit and a global daily cap are stored in a SQLite/JSON file. |
| `realm.ts` | Read model | `GET /realm` returns a full snapshot: season, powers (from `powerAlive`), cooldowns, vassals (labels, banners resolved **through UniversalResolverV2**, decreed flag, house), ballot, manifestos with momentum, last 50 chronicle entries, and outcome. `GET /stream` is SSE that pushes diffs on every block or Arkiv event. A cache TTL of 2 s protects the RPCs. |
| `index.ts` | Hono HTTP server | CORS for the frontend origin, `/health`, structured JSON logs. |

### 5.1 Tyrant bot policy (v1, deterministic; humans tune the numbers)
Each tick, take the first rule that applies whose power is alive and off cooldown:
1. A ballot is active and someone voted yes → **BANISH** the earliest yes voter. Taunt: "Traitors lose their names."
2. A manifesto's momentum is at least `TYRANT_PANIC` (0.6) → **BANISH** its author. If BANISH is gone, **DECREE** the author.
3. A manifesto's momentum is at least 0.3 → **DECREE** the top pledger.
4. A vassal has a house → **DISSOLVE** it.
5. Otherwise, with probability `TYRANT_IDLE_TAUNT`, write a taunt to the Chronicle and do nothing else.

Difficulty: `TYRANT_REACTION_MS` delays every action. This is the main tuning knob, so a single judge can still win.

### 5.2 Shared package (`packages/shared/`)
- `abis/`: generated from `contracts/out` by `scripts/gen-abis.ts`, as `as const` TS exports.
- `deployments.ts`: a typed loader.
- `arkiv/schemas.ts`: the three schemas above.
- `powers.ts`: ids, names, and role bits. A unit test checks these against `RegistryRolesLib`.
- `world.ts`: the signal string builder, matching `Throne`'s `signalBytes`.
- `types.ts`: the `RealmSnapshot` contract shared with the UI later.

**Workspace:** npm workspaces (bun and pnpm aren't installed). Packages: `packages/shared`, `services/server`, `scripts`. Use TypeScript 5, `tsx` for running, and `vitest` for tests.

---

## 6. Configuration (`.env.example`; every value is read and none is hard-coded)
```
SEPOLIA_RPC_URL=            DEPLOYER_PK=        TYRANT_PK=       KEEPER_PK=      FAUCET_PK=
NPC_MNEMONIC=               REALM_LABEL=fealty  SEASON=s1
SEASON_DURATION_S=1800      POWER_COOLDOWN_S=45 BALLOT_DURATION_S=120  MIN_YES_VOTES=1
QUORUM_PLEDGES=3            MANIFESTO_TTL_S=180
WORLD_MODE=onchain|attested WORLD_APP_ID=  WORLD_RP_ID=  WORLD_RP_SIGNING_KEY=  WORLD_ACTION=fealty-vote
WORLD_ENV=staging           ATTESTER_PK=   (Mode B only)
ARKIV_ACCESS_KEY=           ARKIV_RPC_URL=https://rpc.rabdi.db-chain.testnet.arkiv.network
TYRANT_ENABLED=true TYRANT_REACTION_MS=8000 TYRANT_PANIC=0.6 TYRANT_IDLE_TAUNT=0.2
FAUCET_SEPOLIA_WEI=3000000000000000  FAUCET_TGLM=0.5  FRONTEND_ORIGIN=http://localhost:5173
```
**Demo profile:** `MIN_YES_VOTES=1`, `QUORUM_PLEDGES=3` (NPCs can make up 2 of the 3), `BALLOT_DURATION_S=120`, `TYRANT_REACTION_MS=15000`.

**Credentials only the humans can provide:**
1. A funded Sepolia key (plus a separate tyrant, keeper, and faucet key, each with about 0.2 ETH)
2. A World Developer Portal **staging** app (`app_id`, `rp_id`, signing key) with action `fealty-vote`
3. An Arkiv access key and tGLM for the keeper, faucet, and NPC keys
4. A Sepolia RPC URL (Alchemy or Infura)

---

## 7. Milestones, gates, and order

The hour counts are working-hours estimates. **"Gate" means stop, have a human check the result, then continue.**

| # | Milestone | Est. | Done when |
|---|---|---|---|
| M0 | Repo hygiene: pin `contracts-v2` as a git submodule at `07e55a05`, add `.gitignore`, npm workspaces, `.env.example`, foundry `solc=0.8.25`, `forge build` green | 0.5 h | `forge build` passes from a clean clone |
| M1 | **Spikes S1 (ENS fork), S2 (World proof on Sepolia), S3 (Arkiv TTL)**, all logged in `research/proof.md` with tx hashes | 2 h | **GATE A:** S2 decides between Mode A and Mode B, and the signal encoding |
| M2 | `Throne` + `Powers` + `ByteHasher` + full test suite | 3 h | `forge test` green, coverage of Throne ≥ 90% lines |
| M3 | Deploy scripts; deploy realm + season s1 on Sepolia; seed NPCs; resolve a vassal's banner via UniversalResolverV2 with viem | 1.5 h | **GATE B:** links on Sepolia Etherscan + ENS read works |
| M4 | `packages/shared` (ABIs, deployments, schemas, powers, signal) | 1 h | `vitest` green; ABI gen script works |
| M5 | Server skeleton + config + `/health` + `/world/rp-context` + `/faucet` + chronicle mirror | 1.5 h | Chronicle entities visible on the Rabdi explorer |
| M6 | Keeper (quorum → openBallot, resolve, finalize) | 1.5 h | Integration test against a local anvil fork + real Rabdi |
| M7 | Tyrant bot | 1 h | Bot banishes the yes voter in a scripted scenario |
| M8 | `/realm` snapshot + `/stream` SSE | 1 h | Snapshot JSON matches the `RealmSnapshot` type; SSE pushes on events |
| M9 | `scripts/e2e.ts`: the full live loop on Sepolia + Rabdi (join ×2 → manifesto → pledges → ballot → World vote(s) → power stripped → second power → RebelsWin), every hash logged to `research/proof.md` | 1.5 h | **GATE C:** a human watches the run end to end |
| M10 | Sponsor documents: `/arkiv/*`, `WORLD_DEBRIEF.md`, README backend section + trust model + diagram, `AI_DISCLOSURE.md` | 1 h | The checklist in section 8 is all ticked |

**Feature freeze for the backend is the end of M9.** The UI then builds only against `/realm`, `/stream`, the contract ABIs, and the Arkiv SDK.

---

## 8. Sponsor proof checklist (judges check these)
- [ ] **ENS:**
  - Sepolia tx links for: join, banish (unregister), decree (setResolver), dissolve, PowerStripped (revokeRootRoles), and `isEmancipated()` true.
  - Names resolve via UniversalResolverV2.
  - Every address comes from `deployments/*.json`.
  - Contracts verified on Etherscan (`forge verify-contract`).
- [ ] **Arkiv:**
  - Rabdi writes come from 3 kinds of owners (rebel, vassal, keeper).
  - User-facing reads in `/realm`.
  - Expiry shown live (the manifesto vanishes).
  - `/arkiv/{schema,friction,reach,why-arkiv,usage}.md`, writer wallet addresses, a runnable query, an OSS LICENSE, and the AI disclosure.
- [ ] **World:**
  - IDKit staging proof verified onchain (or attested), with the tx hash.
  - Cancel and failure paths shown.
  - A double vote rejected (tx or `eth_call` revert reason).
  - `WORLD_DEBRIEF.md` covers the trust event, the minimum credential (Orb legacy, uniqueness only), and the simulator disclosure.
- [ ] **ETHGlobal:**
  - `docs/` holds the plans and prompts.
  - `AI_DISCLOSURE.md` exists.
  - Commit history is steady.

---

## 9. Risks and fallbacks (cut in this order when late)

| Risk | Detection | Fallback |
|---|---|---|
| Staging legacy proofs don't verify on the Sepolia router, or the external nullifier is unknown | S2 | **Mode B**: server verifies via the v4 API, then `voteAttested`. Disclosed in the debrief. |
| `fealty.eth` is taken on Sepolia v2 | M3 | `REALM_LABEL` from env (e.g. `fealtyrealm`) |
| The commitment age forces a wait in DeployRealm | M3 | Split into `--sig commit()` and `--sig register()` runs |
| Arkiv public RPC rate limits | M5 | Access key required; keeper backoff; snapshot cache |
| Sepolia slow or flaky during the demo | M9 | Pre-staged season `s1-demo` with NPCs; video backup; `BALLOT_DURATION_S` raised |
| Throne over 24 KB | M2 | Move label validation and dnsName into a library; `optimizer_runs=200`; never via-IR (ENS rule) |
| Time | any | Cut in order: houses/DISSOLVE-by-house → concede → LockRealm → SSE (poll `/realm`) → faucet tGLM (pre-fund) → Etherscan verification. **Never cut:** the irreversibility test, the World vote, the Arkiv quorum. |

---

## 10. Decisions the humans own (the ETHGlobal "meaningful contribution" rule)
- All numbers in the demo profile: cooldowns, quorum, TTL, ballot length, Tyrant reaction time.
- The Tyrant's personality and taunt lines (`services/server/src/tyrant/lines.ts`).
- Realm and season names, plus NPC names and banners.
- Whether to run `LockRealm` (it is irreversible).
- Reviewing every Sonnet task diff before committing. Running gates A, B, and C.
- Playtesting with the bot and recording the demo.

## 11. Explicitly out of scope for this phase
PixiJS/React UI, art, sound, embedded-wallet UX, and mobile layout. The UI will consume only: `GET /realm`, `GET /stream`, `POST /faucet`, `POST /world/rp-context`, `POST /world/attest`, the Throne ABI (`join`, `setBanner`, `vote`), `court.setResolver` (restore banner), and Arkiv writes for the manifesto and pledge.
