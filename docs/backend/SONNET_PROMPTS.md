# FEALTY backend: Sonnet prompts

These are the prompts the Sonnet model runs to build the FEALTY backend. They are committed to the repo as part of the ETHGlobal AI disclosure.

**How to run them**
1. Start a fresh Sonnet session in the repo root: `~/Downloads/ethglobal-mumbai/fealty`.
2. Paste **Part A (Global rules)** once at the start of every session.
3. Then paste **one task** from Part B. Run the tasks in order. Never run two at once.
4. When Sonnet finishes, it stops and prints a report. A human reviews the diff, runs the acceptance commands, and commits.
5. Tasks marked **GATE** need a human decision before the next task starts.

The spec for every task is [`docs/backend/BACKEND_PLAN.md`](BACKEND_PLAN.md). Section references below such as "§3.4" point to that file.

---

## Part A: Global rules (paste first, every session)

```text
You are implementing the backend of FEALTY, an ETHGlobal Mumbai 2026 hackathon game.
The submission deadline is Sat Nov 7 2026, 09:00 IST. Favor working, tested, simple code over clever code.

SOURCE OF TRUTH
- docs/backend/BACKEND_PLAN.md is the spec. Read the sections the task names before writing code.
  If the spec is ambiguous or wrong, STOP and ask; do not invent game rules.
- docs/planning/PLAN.md is the approved game design. docs/planning/final.md is an OLD, superseded idea: ignore it.
- research/proof.md holds verified spike results (signal encoding, World mode, tx hashes). When it
  disagrees with the plan, the proof file wins.

HARD RULES
1. Never edit anything under contracts/lib/ (upstream ENSv2 code; see its AGENTS.md). Fix things on our side.
2. Solidity: pragma solidity 0.8.25 exactly, evm_version cancun, NO via-IR. If you hit "stack too deep", refactor.
   NatSpec on every contract, function, event and error. Custom errors, not revert strings.
   Import ENSv2 via remappings (@ens-v2/..., @openzeppelin/...) and reuse its constants
   (RegistryRolesLib, PermissionedResolverLib, LibLabel). Never hard-code role bit values.
3. No hard-coded addresses, keys or chain values in app code. Everything comes from .env (validated with zod)
   or deployments/<chainId>/<season>.json. ENSv2 core Sepolia addresses may be read from
   contracts/lib/contracts-v2/contracts/deployments/sepolia/*.json or listed once in script/Config.s.sol
   with a comment citing that file.
4. Never print, log or commit secrets. .env is gitignored; update .env.example whenever you add a variable.
5. Do NOT git commit. At the end, list changed files and propose ONE conventional-commit message.
   A human reviews and commits.
6. Tests are part of every task. Do not mark a task done until the acceptance commands pass; paste their real output
   (trimmed). If something fails and you cannot fix it, say so plainly. Never weaken or delete a test to make it pass.
7. Forge tests: run from contracts/. When asserting events use vm.expectEmit + emit, or vm.recordLogs with explicit
   checks. Put vm.expectRevert BEFORE vm.prank.
8. TypeScript: Node >= 22, ESM, strict mode, npm workspaces (bun/pnpm are not installed), viem for EVM,
   @arkiv-network/sdk for Arkiv, zod for config, vitest for tests, tsx to run. No `any` in exported types.
9. Arkiv API (verified at docs.arkiv.network): rabdi({accessKey}) from "@arkiv-network/sdk/chains";
   createPublicClient/createWalletClient/ExpirationTime from "@arkiv-network/sdk"; defineSchema + column types
   (str, addr, i32, dec, bool, bytes, key) with .indexed()/.optional()/.default() from "@arkiv-network/sdk/schema";
   filters (eq, gt, gte, lt, lte, and, or, between, exists) from "@arkiv-network/sdk/query";
   walletClient.createEntity(Schema, values, { expiration }), walletClient.executeBatch({creates, patches, ...}),
   publicClient.select().from(Schema).where(...).ownedBy(addr).fetch(), publicClient.watchEntityEvents({...}).
   Expiration in seconds must be a multiple of 2. There is NO event when an entity expires.
   If the installed SDK version differs from this, read node_modules types, adapt, and record the difference
   in arkiv/friction.md.
10. Scope discipline: do exactly the task. No UI, no PixiJS, no React. Do not add dependencies the task doesn't need.
11. When an external fact can't be verified (API shape, address, behavior), write a minimal script that checks it
   against the live network and record the result in research/proof.md. Do not guess.

REPORT FORMAT (end every task with this)
## Done
- what was built (bullets)
## Verification
- commands run + trimmed real output
## Deviations from the spec
- each one + why (or "none")
## Open questions / risks for the human
## Proposed commit
<type(scope): message>
```

---

## Part B: Tasks

### T0: Repo hygiene (M0)

```text
TASK T0 — repo hygiene. Read BACKEND_PLAN.md §0, §3.1, §5.2, §6.

1. contracts/lib/contracts-v2 is currently a plain clone. Convert it to a git submodule pinned at commit
   07e55a056f5b6a9c90119f501bdd05714e67dddd (URL https://github.com/ensdomains/contracts-v2.git) WITHOUT losing the
   nested submodules under contracts/lib/contracts-v2/contracts/lib (they are required by our remappings).
   If converting is risky, stop and describe the exact commands for the human instead.
2. Root .gitignore: node_modules, .env, contracts/out, contracts/cache, contracts/broadcast/*/31337, *.log,
   services/server/data/.
3. contracts/foundry.toml: add solc = "0.8.25"; fs_permissions read-write for "../deployments"; keep existing remappings.
4. npm workspaces root package.json with workspaces ["packages/*", "services/*", "scripts"], scripts:
   "build", "test", "lint" (tsc --noEmit). Create empty packages/shared, services/server, scripts with package.json
   + tsconfig (strict, ESM, NodeNext).
5. .env.example exactly as BACKEND_PLAN.md §6 (with comments explaining each variable).
6. Root LICENSE (MIT, copyright "FEALTY team").

Acceptance:
- cd contracts && forge build   (FealtyCourt compiles)
- npm install && npm run lint   (succeeds on empty packages)
- git status shows no secrets and no build output
```

### T1: Spike S1, ENS irreversibility and realm resolution on a Sepolia fork (M1)

```text
TASK T1 — spike S1. Read BACKEND_PLAN.md §1 (ENSv2 facts), §3.2, §3.3.

Write contracts/test/fork/S1_Irreversibility.t.sol (it becomes part of the suite later). On a Sepolia fork
(vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"))) using the REAL LabelStore, VerifiableFactory and
PermissionedResolverImpl addresses:
 a. Deploy FealtyCourt with rootAccount = a test "throne" address holding
    ROLE_REGISTRAR | ROLE_SET_PARENT | (UNREGISTER, SET_RESOLVER, SET_SUBREGISTRY each with its _ADMIN).
 b. Deploy a PermissionedResolver proxy via VerifiableFactory.deployProxy with initialize([Grant(throne, ROLE_SET_TEXT)], [])
    — no upgrade roles. setText on a DNS-encoded name and read it back.
 c. Register "alice" to a vassal with token roles ROLE_SET_RESOLVER|ROLE_SET_SUBREGISTRY, resolver = that proxy.
 d. throne: unregister works (status AVAILABLE). Re-register "bob".
 e. throne revokes ROLE_UNREGISTER|ROLE_UNREGISTER_ADMIN from itself → unregister(bob) reverts;
    grantRootRoles(ROLE_UNREGISTER, x) reverts for throne, deployer and a fuzzed address; getAssigneeCount is 0.
 f. Strip the other two powers → court.isEmancipated() == true. bob can still setResolver on his own name.
 g. safeTransferFrom of bob's token reverts (soulbound because no CAN_TRANSFER_ADMIN).
 h. Measure gas of register / unregister / revokeRootRoles and log it.

Also write scripts/spikes/s1-resolve.ts (viem) that, given a name, calls getEnsText through the ENSv2
UniversalResolverV2 proxy on Sepolia (address from the ENSv2 deployments json) to prove our read path works
with an existing ENSv2 Sepolia name (find any registered one via ETHRegistry events if needed).

Record results (pass/fail, gas, any surprises) in research/proof.md under "S1".

Acceptance: cd contracts && forge test --match-path test/fork/S1_Irreversibility.t.sol -vv (green);
npx tsx scripts/spikes/s1-resolve.ts <name> prints a text/addr record.
```

### T2: Spike S2, World ID proof onchain (M1; **GATE A**)

```text
TASK T2 — spike S2 (decides World Mode A vs Mode B). Read BACKEND_PLAN.md §1 (World), §3.4 vote(), §2 trust model.

Goal: prove whether a World ID SIMULATOR (staging) legacy proof from IDKit 4.x verifies on the Ethereum Sepolia
WorldIDRouter v3 (0x469449f251692e0779667583026b5a1e99512157, groupId 1), and pin the exact signal and
external-nullifier encodings.

Build a throwaway harness in scripts/spikes/world/ (NOT the game UI):
 1. A tiny Node server: POST /rp-context → signRequest({ signingKeyHex: WORLD_RP_SIGNING_KEY, action: WORLD_ACTION })
    from "@worldcoin/idkit-core/signing".
 2. A single static HTML page (vite or plain ESM) using @worldcoin/idkit (latest 4.x) with
    allow_legacy_proofs, preset orbLegacy({ signal }), environment "staging", where
    signal = "<voter address lowercase>:<ballotId>:<1|0>". It prints the full JSON response.
    The human completes the proof with the World ID simulator (https://simulator.worldcoin.org).
 3. scripts/spikes/world/check.ts takes that JSON and:
    a. decodes responses[0].proof (abi-encoded) into uint256[8];
    b. computes candidate signalHash values in TS (hashToField(utf8 bytes) = uint256(keccak256(bytes)) >> 8, and
       the abi.encodePacked(address,uint256,bool) variant) and reports which equals responses[0].signal_hash;
    c. computes candidate externalNullifierHash values (v3 convention:
       hashToField(abi.encodePacked(hashToField(abi.encodePacked(app_id)), action)); also try rp_id in place of app_id)
       and eth_calls router.verifyProof(root, 1, signalHash, nullifier, extNull, proof) for each until one passes;
    d. prints the winning encodings, or all revert reasons.
 4. Also call POST https://developer.world.org/api/v4/verify/{rp_id} with the unmodified payload and record the result
    (this is the Mode B path).

Write research/proof.md "S2" with: IDKit versions, request config, raw response (redact nothing secret-free), winning
signal encoding, winning externalNullifierHash formula + value, router eth_call result, v4 API result, and a
one-line RECOMMENDATION: "WORLD_MODE=onchain" or "WORLD_MODE=attested".

STOP after this task. GATE A: the human confirms the mode before T3.
```

### T3: Spike S3, Arkiv TTL and queries (M1)

```text
TASK T3 — spike S3. Read BACKEND_PLAN.md §1 (Arkiv), §4.

In packages/shared/src/arkiv/schemas.ts define the three schemas exactly as §4 (names fealty.v1.manifesto,
fealty.v1.pledge, fealty.v1.chronicle). Then scripts/spikes/s3-arkiv.ts (Rabdi, ARKIV_ACCESS_KEY, two wallets A and B):
 1. A creates a manifesto with expiration 60s; print entityKey, txHash, expiresAt, explorer link.
 2. B creates a pledge referencing it with ExpirationTime.atBlock(manifesto expiresAt).
 3. Query pledges by manifesto key + .ownedBy(B); confirm owner field equals B.
 4. Try to have A delete B's pledge → must fail; record error.
 5. watchEntityEvents logs both creations.
 6. Poll every 4s until both are gone from queries; record actual expiry delay vs requested.
 7. executeBatch with 3 chronicle creates; record gas/tx.
Record everything in research/proof.md "S3" and start arkiv/friction.md with every rough edge you hit
(docs mismatches, versions, rate limits, error messages) — dated, one bullet each.

Acceptance: npx tsx scripts/spikes/s3-arkiv.ts runs end to end; proof.md S3 filled.
```

### T4: Throne contract and full test suite (M2)

```text
TASK T4 — implement contracts. Read BACKEND_PLAN.md §3 entirely and research/proof.md S1+S2 (use S2's signal
and external-nullifier encodings and WORLD_MODE).

Create: src/libraries/Powers.sol, src/libraries/ByteHasher.sol, src/FealtyRealm.sol (unmodified
PermissionedRegistry subclass, like FealtyCourt), src/Throne.sol per §3.4 (both vote() and voteAttested();
voteAttested only works when attester != address(0)). Leave src/FealtyCourt.sol unchanged.

Key requirements (do not skip any):
- Constructor genesis asserts (§3.3 step 4).
- Names always addressed by LibLabel.id(label), never a cached tokenId.
- VASSAL_ROLES and THRONE_ROOT_ROLES are constants built from RegistryRolesLib.
- powerAlive(p) reads court.hasRootRoles — never a stored bool.
- banish removes the target's vote from the active ballot.
- vote eligibility: live owner on the court, not banished, joinedAt < ballot.openedAt, one vote per address,
  one per nullifier per ballot.
- resolve: deadline path + early path; strip via court.revokeRootRoles(bit | bit << 128, address(this));
  outcome transitions incl. Emancipated when court.isEmancipated().
- finalize after seasonEnd.
- Events carry all data the chronicle needs (actor, target, power, ballotId, label).

Tests: test/Throne.t.sol, test/Irreversibility.t.sol (incl. fuzz), test/WorldVote.t.sol (MockWorldID that checks
it received the expected signalHash/externalNullifierHash), plus move S1 into test/fork/SepoliaFork.t.sol
(skips cleanly when SEPOLIA_RPC_URL is unset). Cover every custom error at least once.

Acceptance (from contracts/):
- forge build --sizes   (Throne runtime < 24576 bytes; paste the line)
- forge test -vv        (all green; paste the summary)
- forge coverage --report summary  (Throne.sol ≥ 90% lines)
- forge snapshot        (commit .gas-snapshot; join < 400k gas)
```

### T5: Deploy scripts and Sepolia deployment (M3; **GATE B**)

```text
TASK T5 — deployment. Read BACKEND_PLAN.md §3.3, §3.6, §6.

Write script/Config.s.sol, DeployRealm.s.sol (split into commit() and register() entrypoints because of the
commitment age; read min commitment age from the registrar), DeploySeason.s.sol (address prediction with an
assertion; writes deployments/11155111/<SEASON>.json with every address, deploy block, all config values,
and keccak of the Throne ABI), SeedCourt.s.sol (NPC vassals from NPC_MNEMONIC; labels/banners from
scripts/seed/npcs.json — create that file with 8 placeholder entries the humans will rewrite), and
LockRealm.s.sol (guarded: requires env CONFIRM_IRREVERSIBLE_LOCK=yes; DO NOT RUN IT).

Then write a step-by-step runbook in docs/backend/DEPLOY.md (exact commands, expected outputs, how to verify on
Etherscan with forge verify-contract). Run the scripts on a local anvil Sepolia fork first and paste output.

Do NOT broadcast to Sepolia yourself. STOP and hand the runbook to the human.
GATE B: the human broadcasts on Sepolia, then verifies a vassal name resolves via UniversalResolverV2
(scripts/spikes/s1-resolve.ts alice.s1.<realm>.eth) and records tx hashes in research/proof.md.
```

### T6: Shared package (M4)

```text
TASK T6 — packages/shared. Read BACKEND_PLAN.md §4, §5.2.

- scripts/gen-abis.ts: reads contracts/out/{Throne,FealtyCourt,FealtyRealm}.sol/*.json and
  the ENSv2 PermissionedResolver + UniversalResolver ABIs, writes packages/shared/src/abis/*.ts as `as const`.
- deployments.ts: loadDeployment(chainId, season) with a zod schema matching what DeploySeason writes.
- powers.ts: Power enum, names, role bits (test asserts they equal the Solidity constants by reading the ABI
  or a forge-generated JSON — do not duplicate magic numbers unchecked).
- world.ts: buildVoteSignal(voter, ballotId, support) and computeSignalHash() — must equal the S2-verified encoding;
  test with the vector recorded in research/proof.md S2.
- arkiv/schemas.ts (from T3) + arkiv/validity.ts: pure function countValidPledges(pledges, vassalState) implementing
  §4 validity rules (owner == pledger, live, not decreed, dedupe, manifesto author live). Unit-test every rule.
- types.ts: RealmSnapshot (season, outcome, powers[3]{alive, cooldownRemaining}, vassals[], activeBallot,
  manifestos[] with momentum, chronicle[], updatedAtBlock). Document each field (the UI will depend on it).

Acceptance: npm run build && npm test -w packages/shared (green).
```

### T7: Server skeleton, World endpoints, faucet, chronicle mirror (M5)

```text
TASK T7 — services/server part 1. Read BACKEND_PLAN.md §5 (rows config, chain, arkiv, chronicle, world, faucet, index).

- Hono server, zod-validated config (fail fast listing missing vars), pino JSON logs, CORS for FRONTEND_ORIGIN.
- Module flags: --keeper --tyrant --chronicle --api (all on by default).
- /health returns versions, season, block numbers for Sepolia and Rabdi.
- POST /world/rp-context {action} — only allows action === WORLD_ACTION.
- POST /world/attest — only when WORLD_MODE=attested: verify via developer.world.org v4 API, check action and
  signal_hash == computeSignalHash(voter, ballotId, support), check voter is eligible via Throne.isEligible, then
  sign EIP-712 exactly as Throne.voteAttested expects (domain + types shared from packages/shared). Unit test the
  signature against a forge-produced vector.
- POST /faucet {address}: one drip per address, per-IP limit, global daily cap, persisted in services/server/data/.
  Sends Sepolia ETH and tGLM. Returns tx hashes. Never drips to contracts.
- chronicle.ts: backfill Throne events from deploy block, then watch; map each to a chronicle entity; dedupe by
  txHash:logIndex (persisted); flush via executeBatch every 2s; survive restarts.

Acceptance: npm test -w services/server (mocked chain/Arkiv); then run against Sepolia+Rabdi for 2 minutes and
paste the chronicle entity keys + Rabdi explorer links of events produced by SeedCourt.
```

### T8: Keeper (M6)

```text
TASK T8 — keeper. Read BACKEND_PLAN.md §2 trust model, §3.4 openBallot/resolve/finalize, §4 validity, §5 keeper row.

- Each tick: load chain state (vassals via Throne events/views, decreed = court.getResolver(label) != bannerResolver),
  query live manifestos + pledges for the season from Arkiv, countValidPledges, then openBallot / resolve / finalize
  per §5. Idempotent: derive everything from chain + Arkiv, never from in-memory flags. Simulate (eth_call) before
  sending; on revert, log the decoded custom error and continue.
- Concurrency: a single in-flight tx per key, nonce managed by viem; ticks never overlap.
- Write a chronicle entry "ballot-opened" with the manifesto key so anyone can audit the quorum.

Tests: unit tests with fakes for every branch (quorum reached, power dead, ballot already active, deadline passed,
early resolve, season over). Integration: scripts/integration/keeper.ts runs against an anvil Sepolia fork with
the season deployed and real Rabdi entities created by 3 throwaway wallets; asserts BallotOpened fires.

Acceptance: tests green + integration output pasted.
```

### T9: Tyrant bot (M7)

```text
TASK T9 — Tyrant bot. Read BACKEND_PLAN.md §5.1.

- tyrant/policy.ts: PURE function decide(snapshot, now, config) → Action | null implementing the 5 rules in order.
  Exhaustive unit tests, one per rule plus "power stripped falls through" and "cooldown respected".
- tyrant/lines.ts: taunt lines keyed by rule — write 3 PLACEHOLDER lines per rule marked "// HUMANS: rewrite".
- tyrant/index.ts: loop with TYRANT_REACTION_MS delay before acting, simulate then send via TYRANT_PK, chronicle the
  decision + taunt, log a decision trace (inputs → rule → action → tx).
- TYRANT_ENABLED=false disables it completely.

Acceptance: tests green; integration scenario on anvil fork: a vassal votes yes → bot banishes them within
REACTION + 2 blocks → their vote is removed (paste the event log).
```

### T10: Read API and live stream (M8)

```text
TASK T10 — /realm and /stream. Read BACKEND_PLAN.md §5 realm row and packages/shared types.ts.

- GET /realm returns a RealmSnapshot. Banners must be read THROUGH ENS: UniversalResolverV2 text("fealty.banner")
  for each vassal name (batch with multicall / resolve batching; cache 2s). Decreed vassals therefore show the
  Tyrant's proclamation automatically — do not special-case it.
- GET /stream: Server-Sent Events; emits {type:"snapshot"} on connect, then {type:"patch", ...} when a new Sepolia
  block contains Throne events or an Arkiv manifesto/pledge event arrives (watchEntityEvents), plus a heartbeat every
  15s. Because Arkiv has no expiry event, recompute manifesto lists every 4s and emit when one disappears.
- Snapshot computation is shared with the keeper/tyrant (one module), not duplicated.

Acceptance: contract test that the JSON validates against a zod mirror of RealmSnapshot; curl -N /stream output
pasted showing a patch after a join on the fork.
```

### T11: Live end-to-end proof (M9; **GATE C**)

```text
TASK T11 — scripts/e2e.ts on LIVE Sepolia + Rabdi (the human runs the broadcast steps; you build and dry-run).

Scenario (each step logs tx hash / entity key + explorer link, appended to research/proof.md "E2E <timestamp>"):
 1. Two fresh human wallets H1, H2 from the faucet endpoint; NPC wallets from NPC_MNEMONIC.
 2. H1, H2 join with banners; resolve their banners via UniversalResolverV2.
 3. H1 posts a manifesto against DECREE; H2 + two NPCs pledge.
 4. Keeper opens the ballot (wait for BallotOpened).
 5. H1 and H2 vote yes with World proofs. The script pauses and prints the IDKit URL / asks the human to paste
    the simulator proof JSON for each (no fake proofs on live networks).
 6. Show a rejected double vote (same nullifier from H1 again) — capture the revert reason via eth_call.
 7. Resolve → PowerStripped(DECREE). Verify: court.hasRootRoles(ROLE_SET_RESOLVER, throne) == false and a direct
    grantRootRoles attempt reverts.
 8. Repeat for DISSOLVE → outcome RebelsWin.
 9. (Optional) BANISH → isEmancipated() == true.
 10. Print a final summary table.
Run it with TYRANT_ENABLED=false first, then once with the bot on to observe counterplay.

Dry-run on the anvil fork with a MockWorldID-deployed variant (WORLD_MODE=mock only allowed when chainId == 31337).
GATE C: the human runs it live and keeps the output.
```

### T12: Sponsor documents (M10)

```text
TASK T12 — documentation for judges. Read BACKEND_PLAN.md §2, §4, §8 and research/proof.md.

Write, concisely and only with facts proven in research/proof.md (link every tx/entity):
- README.md (root): what FEALTY is (3 lines), architecture diagram (from §2), trust model verbatim, how to run
  (server + contracts), deployed addresses table generated from deployments json, sponsor sections, AI disclosure link.
- arkiv/schema.md, arkiv/friction.md (finalize from the live log), arkiv/reach.md, arkiv/why-arkiv.md, arkiv/usage.md
  (writer wallet addresses for rebel/vassal/keeper roles + a copy-paste runnable query script).
- WORLD_DEBRIEF.md: trust event (the irreversible role revocation), why Orb-legacy uniqueness is the minimum
  sufficient credential, onchain vs attested mode actually used, nullifier scope (per ballot), success + cancel +
  double-vote paths with evidence, simulator disclosure, friction notes.
- AI_DISCLOSURE.md: which parts Sonnet/Claude wrote, which the humans designed/decided/reviewed (leave a section
  "HUMANS: fill in" listing §10 decisions), and that docs/backend/*.md are the prompts/specs used.
Do not claim anything not in proof.md. Mark unproven items as "not demonstrated".
```

---

## Part C: Rules for the human reviewer
- Before committing each task, run its acceptance commands yourself. Read every Solidity diff line by line, because Throne holds the irreversible power.
- If Sonnet reports a deviation, you decide. Update `BACKEND_PLAN.md` first, then re-prompt.
- Keep commits small and frequent, at least one per task. That gives ETHGlobal the steady history it requires.
- If a task overruns its estimate by more than 50%, apply the cut list in §9 of the plan instead of pushing on.
