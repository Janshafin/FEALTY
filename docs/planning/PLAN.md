# FEALTY: final architecture, eligibility, risks, first test, build order

## Context
You approved the FEALTY direction (real, blockchain-enforced political power) and asked for:
- three cohesive sponsor integrations (ENS, Arkiv, World IDKit);
- a defensible difference from **ENSv2 Kingdom**;
- immediate execution after the plan.

**Hard constraints from ETHGlobal rules** (https://ethglobal.com/events/mumbai/info/details, verified):
- **Deadline: Sat Nov 7, 09:00 IST**, no late submissions.
- Up to **3 partner prizes**. All of one partner's tracks count as one slot.
- Classic track means everything is built during the event. Steady git history required.
- **AI may assist but must not build the whole project.** Disclose AI use, and commit specs, prompts, and planning files. *You and your teammate must make meaningful contributions:* owning game design decisions, art direction, playtesting, the demo, and reviewing and editing code.
- Video: 2–4 min, real voice.

## Competitor comparison (VERIFIED)
**ENSv2 Kingdom** (ETHOnline 2026, Apache-2.0, https://github.com/vinhyenvodoi98/ENSv2_Village)
- What it does:
  - Claim a .eth → a 3D castle grows.
  - ETH tips → cosmetic attacks.
  - Found a registry → subnames shown as villages.
  - Feed of role changes.
- What it does not have: political mechanics, contested power, revocation used as a game action, consequences of expiry, voting, sybil resistance, or a second sponsor.

**Others:** ens-slots (Harberger subnames, not a game); Forge World, P2P Games, TreasureHunt, BitBrawlers, Ubisoft (ENS as identity only).

**What FEALTY uniquely adds:**
- Power is contested.
- A **human-verified revolution permanently removes a specific EAC role from the ruler**.
- Banishment is a real `unregister`.
- Rebellion organizing is uncensorable and expires.
- We reuse **no** code from ENSv2 Kingdom.

## Gameplay (one match ≈ 3–5 min, goal clear in 30 s)
**"The Tyrant holds 3 crowns of power. Strip 2 before the season ends, or the Tyrant wins."**

**The three powers** are real ENSv2 roles in the court registry, held by the `Throne` and exercised by the Tyrant:
1. 🗡 **BANISH** = `ROLE_UNREGISTER`. Deletes a vassal's name, which then stops resolving.
2. 📜 **DECREE** = `ROLE_SET_RESOLVER`. Overwrites a vassal's banner/records.
3. 🏰 **DISSOLVE** = `ROLE_SET_SUBREGISTRY`. Destroys a vassal's sub-court.

**Loop:**
1. **Join:** a vassal receives `name.court.fealty.eth`.
2. **Tyranny:** the Tyrant uses powers. Each use has a cooldown, and the decree is visible.
3. **Organize (Arkiv):** a rebel posts a Manifesto targeting one power. It expires in about 90 s. Vassals pledge (owner-signed entities). The map shows live momentum from Arkiv queries.
4. **Ratify (World + ENS on Sepolia):**
   - Once pledges reach a quorum, the ballot opens.
   - **One verified human, one vote**, via a World ID proof verified **onchain** by `Throne` with a nullifier per revolution.
   - If a majority votes yes before the Manifesto expires, `Throne` revokes that role *and its admin bit* from itself. **The power is gone forever**, and you can check this on the ENS Explorer.
5. **Counterplay:**
   - The Tyrant can **banish ringleaders**, which removes their ballot eligibility because ballot eligibility = holding a live name.
   - Or **concede** a lesser power to calm the court.
   - Rebels choose which power to target first and when to strike.

**Win/lose:** rebels win when 2 of 3 powers are stripped. The Tyrant wins if 2 or more remain at season end.

**For the demo,** the Tyrant is a scripted bot so a single judge can play.

## What breaks without each sponsor
| Sponsor | Role | If removed |
|---|---|---|
| **ENS (Sepolia)** | Authority itself. Names = membership, roles = powers, unregister = banishment, irreversible role revocation = victory | Power becomes a database row the operator could restore. No portable titles, no provable loss of power |
| **Arkiv (Rabdi)** | Shared, expiring, uncensorable political organizing. Manifestos and pledges are wallet-owned entities with TTL = campaign window; live queries drive the map and the ballot quorum | The operator (or a Tyrant-aligned server) could censor rebellions. Campaigns would need manual cleanup. Other clients couldn't read or build on the realm's politics |
| **World IDKit** | One human, one ballot on the irreversible action | Free sponsored wallets would let one person mint 100 votes and capture any revolution, or defend the Tyrant |

## Cross-chain trust (stated honestly)
- **World → ENS is trustless:** the ballot proof is verified onchain on **Ethereum Sepolia WorldIDRouter v3 `0x469449f2…12157`** inside `Throne`, the same chain as ENSv2, so the role revocation needs no relayer. *Pending test 2 below.*
- **Arkiv → ENS is NOT trustless:**
  - Opening a ballot needs Arkiv quorum, which a keeper reads and posts to `Throne.openBallot()`. The keeper is trusted for *liveness only*: it can delay but not fake votes.
  - Votes themselves are World-verified onchain.
  - No atomic cross-chain claim is made.

## Eligibility matrix (verified requirements → our proof)
| Track | Requirements | Our live proof |
|---|---|---|
| **ENS Best Use of ENSv2** ($3k/$2k/$1k/$1k) | ENSv2 on Sepolia/mainnet; features central; functional, no hard-coded values; live demo; open source | Custom `FealtyCourt is PermissionedRegistry`; EAC roles as powers; `unregister`; irreversible role revocation; Permissioned Resolver records; addresses from config; Sepolia tx links |
| **Arkiv Build from scratch** ($3k/$1k; 25% each: friction, reach, why Arkiv, usage) | Writes via SDK to Rabdi; a user-facing feature reads from Arkiv; README with writer wallet addresses + a runnable query; `/arkiv/schema.md`, `/arkiv/friction.md`, one file per criterion; OSS license; AI disclosure | Manifesto/Pledge/Chronicle entities with TTL; live queries drive the map and quorum; all `/arkiv/*` files |
| **World Best Use of IDKit** (2×$1.25k) | IDKit in the app; at least one credential verified server-side or onchain; trust event explained; minimum credential justified; success + failure/cancel paths; debrief | Orb (legacy) proof of human, verified onchain, nullifier per revolution. Demo shows a cancelled proof and a double vote rejected. `WORLD_DEBRIEF.md`. **Simulator use disclosed** |

## Top risks
1. ENSv2 Sepolia: we need a `.eth` name and the ability to attach a custom `PermissionedRegistry` subregistry. The deployment set may change (we pin it).
2. Whether simulator (staging) legacy proofs verify on the Sepolia v3 router. **Fallback:** verify via `developer.world.org/api/v4/verify` on our backend, then a backend-signed attestation to `Throne`. That adds a trust assumption, which we disclose.
3. Credentials only you can provide:
   - A Sepolia-ETH funded key
   - A World Developer Portal staging app (`app_id`, `rp_id`, `signing_key`)
   - An Arkiv access key and tGLM from hub.arkiv.network
4. The time limit: about 22 hours remain.

## First executable tests (hours 0–2)
1. Install Foundry. Clone `ensdomains/contracts-v2` (pinned commit). Compile `FealtyCourt is PermissionedRegistry`.
   - On a Sepolia fork: grant ROOT roles to `Throne` → register a vassal → `unregister` works → revoke `ROLE_UNREGISTER` + its admin → `unregister` reverts → re-grant attempt reverts. **This is the irreversibility proof.**
2. Fork test, then live: `Throne.vote()` verifies one simulator proof against the Sepolia WorldIDRouter. A double vote reverts on the nullifier.
3. An Arkiv SDK script writes a Manifesto with TTL, queries it, and watches it expire.

All three results, with tx hashes, go in `research/proof.md` before UI work.

## Build order after the tests pass
1. **(2–10h)** Contracts (`FealtyCourt`, `Throne`) + Foundry tests; Sepolia deploy script; seed the court; ENS read layer via Universal Resolver v2.
2. **(10–16h)** Arkiv layer (schema, writes, live queries, keeper); IDKit widget + rp-signing endpoint; vote flow; tests.
3. **(16–20h)** Game UI: React + PixiJS illuminated-manuscript art direction (parchment, ink, gilded crowns; no purple gradients). Tyrant bot; crown-shatter moment; onboarding with an embedded wallet + gas relayer.
4. **(20–24h)** Deploy (Vercel + small server); README, diagram, `/arkiv/*`, `WORLD_DEBRIEF.md`, `research/*.md`, `DEMO.md`, `STATUS.md`, AI disclosure; per-sponsor judge simulations; video.

**Repo:** `~/Downloads/ethglobal-mumbai/fealty/` with git from the first commit.

## Verification
- `forge test` passes: powers, banishment, irreversible revocation, one-human-one-vote, quorum gating.
- E2E script on Sepolia + Rabdi: manifesto → pledges → ballot → World votes → role revoked. All hashes logged.
- A judge on a fresh phone can join and vote within about 60 s.
