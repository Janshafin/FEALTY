# FINAL: Hungry Warlord

**One sentence:** "It's Clash of Clans, but the enemy base is designed by an AI that pays for its own brain out of your raid fees. Drain its treasury and it literally gets dumber."

Status: survived validation, with **one open risk** (see "Couldn't verify"). No project code yet; waiting for your approval.

---

## 1. The problem (evidence in research/problems.md)
1. **0G is explicitly asking for this.**
   - "Agents That Pay for Themselves" wants agents that earn, pay for their own inference, and "adapt when funds run low (cheaper models, slower pace, or pausing)".
   - "Private Computer" wants AI that *is* the product, which people "come back to tomorrow".
   - Source: https://ethglobal.com/events/mumbai/prizes
   - Agents still can't pay for their own compute without a human and a credit card: https://dev.to/gpubridge/the-inference-market-is-consolidating-agent-payments-are-still-nobodys-problem-23ac
2. **People will pay to beat an AI that guards money, but every version so far is a chat box.**
   - Freysa: 482 paid attempts, $47k pot. https://www.theblock.co/post/328747/human-player-outwits-freysa-ai-agent-in-47000-crypto-challenge
   - TORI: same format, Groq-backed, no adaptation. https://hackquest.io/projects/Tori
   - Neither has strategy, visuals, or a reason to replay.
3. **Players can't trust an opponent that holds a stake.** With money on the line, a house that controls the AI can rig difficulty. 0G Router signs every response in a TEE, and anyone can verify the signature on chain. https://docs.0g.ai/developer-hub/building-on-0g/compute-network/router/features/verifiable-execution
4. **Onchain strategy games died of bolted-on token economies** (Sky Strife discontinued, Proof of Play winding down). In our game the economy *is* the game: fees feed both the pot and the boss's brain.

## 2. Why nobody has solved it
- **AI-guards-a-pot games (Freysa, TORI):** prompt-injection chat. No game, no self-funding, no verifiable adaptation.
- **AI battle games (Warriors AI-rena, 0G Cannes 2025; AI Arena):** AI vs AI, or AI trained by the player. None has a persistent, self-funded adversary that redesigns itself from real raids.
- **LLM tower-defense research (TowerMind, AAAI 2026):** shows raw LLMs plan poorly (https://arxiv.org/pdf/2601.05899). Our fix: the LLM *proposes* layouts and a deterministic simulator *tests* them against real past raids, so the learning is real and checkable.
- **Searches with no hits** for "AI boss pays for its own inference" or an LLM-designed raid base that adapts per raid: GitHub, ETHGlobal showcase, HackQuest, and web (2026-11-05). Closest: TORI, Secret.Quest (Brussels; riddles + World ID), Agent Werewolf (0G social deduction).

## 3. What we build, and why the chain is essential
**Core loop (about 60 seconds per raid):**
1. You see the Warlord's fortress: 16×16 grid, walls, 4 tower types, a Core.
2. Drop troops from a 3-card hand (Knight, Archer, Ram) along the map edge, Clash-Royale style, with an energy bar.
3. Watch the real-time battle (deterministic sim) and earn 0–3 stars.
4. Destroy the Core and you take the pot.
5. After each "epoch" (every N raids), the Warlord studies all replays, rebuilds its fortress, and taunts you in voice.

**Economy:**
- Raid fee: 70% to the **pot**, 30% to the **Warlord's brain budget**.
- The Warlord's agent wallet tops up its own 0G compute balance on chain.
- Its intelligence tier is a public function of its on-chain balance:

| Tier | Balance | Model | Behaviour |
|---|---|---|---|
| 👑 Genius | high | GLM-5.2 / large model | 3 layout candidates, sim-tested, voice taunt + new war-banner image |
| 🦊 Cunning | mid | Qwen3.7-Flash | 2 candidates |
| 🐺 Feral | low | cheapest / Laya (free) | 1 candidate, no voice |
| 💀 Starving | ~0 | none (safe stop) | Reuses its last layout and says it's starving. This is the moment to strike. |

Players face a real dilemma: raiding feeds the beast (smarter boss, bigger pot), but a kill takes everything. When the Core falls, the Warlord dies and generation N+1 spawns with seed money.

**What breaks without the chain:**
1. **Pot custody and payout:** players won't pay a server that could keep the fees.
2. **Commit–reveal:** the Warlord commits a hash of its layout on chain *before* the raid window, so it can't swap defenses after seeing your army.
3. **Self-funding:** the agent's wallet receives fees and deposits into the 0G Payment Layer contract with no human. Difficulty tiers are publicly verifiable from on-chain balance.
4. **Verifiable AI:** every redesign stores request IDs and the TEE `tee_verified` flag in a war journal on 0G Storage, so the devs can't secretly hand-design a hard base.

## 4. Target tracks and integration depth
| Track | Prize | How we meet it deeply |
|---|---|---|
| **0G: Build with Private Computer** (main) | $2.5k / $1.5k / $1k | Inference in the main loop: layout design (LLM), taunts (TTS), banner (image gen), with request IDs logged. "What breaks without 0G": the Warlord has no brain and no way to prove its moves weren't hand-made. Come-back-tomorrow: it has changed overnight and the pot has grown. Optional iAI bonus: a player's "War Advisor" scouting report runs on their own 0G credits (laptop only). |
| **0G: Agents That Pay for Themselves** | 2 × $1k | Full loop on screen: fee tx → agent deposit tx to Payment Layer → Router balance → inference. Spend cap per epoch and graceful degradation (the tier table) are the *game mechanic*, not a hidden feature. |
| **World: Best Use of IDKit** (add-on) | 2 × $1.25k | Proof of Human is required to **claim the pot**: fair access to a scarce benefit, one human one claim, so bot farms can't grind it. It is the minimum sufficient credential because we only need uniqueness, not identity. Alt path: an unverified player wins and the payout is held until they verify. Backend-verified nullifier. |

**Stacking:** Compute + Storage + Chain. That is the pattern of 0G's 1st-place Lisbon 2026 winner (https://0g.ai/blog/ethglobal-lisbon-2026-recap).

**What 0G's engineers learn from it:**
- The first consumer showcase of the self-funding loop, with graceful degradation as *gameplay*.
- A FEEDBACK file on Payment Layer programmatic deposits, the Router's testnet story, and the Privy localhost limit.

**Realistic upside:** about $2.5k–$4.75k plus a finalist shot. Only 0G and World's requirements can be met deeply; others would be shallow, so we skip them.

## 5. Game design and tech stack
- **Engine:** Phaser 4 (v4.2.1 on npm, verified) for the battle canvas, plus React/Vite for menus and HUD. 2D top-down: fastest path to polish, and its pathfinding is well proven.
- **Pathfinding:** easystar.js, or a hand-rolled BFS on the 16×16 grid.
- **Art:** Kenney CC0 packs (Tower Defense top-down, Medieval RTS). The site returned 403 to curl (bot block), so download manually. One consistent palette.
- **Juice:** screen shake, hit-stop, particles, damage numbers, Howler.js SFX, and a voiced Warlord via 0G TTS.
- **Determinism:** a pure TypeScript sim with integer math and a seeded PRNG at 20 ticks/s. The same module runs in the browser (render), the server (verify), and the AI (layout scoring).
- **Onboarding, zero crypto:**
  - Landing page: "Raid the Warlord", then an instant **free practice raid** (no wallet).
  - "Raid for real" creates a silent burner wallet, funded with testnet 0G by our faucet relayer. No popups.
  - IDKit only appears at pot-claim time.
  - Judges play from their phone via QR, or on our laptop.
- **Is it fun in 3 minutes?** The Clash raid loop is a proven, legible format. The Warlord's personality (taunts, a starving state) and a live pot add stakes. Learnable in under a minute: drag a card, drop it on the edge.

## 6. Architecture
```
Browser (React + Phaser) ──raid inputs──> Game server (Node/TS)
     │  burner wallet                         ├─ shared deterministic sim (verify replay → stars)
     │  enterRaid(fee) ─────────────┐         ├─ settleRaid() signer
     ▼                              ▼         └─ IDKit verify (claim)
           WarlordVault.sol (0G Galileo testnet, chain 16602)
           • enterRaid: 70% pot / 30% → agent wallet
           • commitLayout(epoch, hash) [agent only]
           • settleRaid(raidId, stars, replayRoot) → pays pot on Core kill (human-verified)
                              │ fees
                              ▼
Warlord agent (Node loop) ── deposit ──> 0G Payment Layer (testnet 0x0AD9…9939) → Router balance
   • reads balance → picks tier → 0G Router: LLM layouts / TTS / image (X-Request-Id, verify_tee)
   • sim-scores candidates vs last K replays → commits best hash on chain
   • war journal + replays → 0G Storage (root hashes in README)
```

## 7. Task split and timeline (about 36 h; hacking ~Nov 6–8, exact deadline unverified)
**You (A): gameplay and frontend**
- Sim module, Phaser render, troop drop UI, HUD (pot, Warlord brain meter, tier badge), juice, landing page, practice mode, QR/mobile.

**Me (B): chain and AI**
- WarlordVault.sol + tests + deploy, agent loop, 0G Router integration with request IDs, Payment Layer self-deposit, 0G Storage journal, server-side replay verification, IDKit, READMEs/FEEDBACK, demo video.

| Hours | Milestone |
|---|---|
| 0–2 | Repo, keys, faucet, sim interface + layout JSON schema agreed. **Spike the Payment Layer deposit first.** |
| 2–10 | A: sim + render playable vs a hand-made layout. B: contract deployed, fee split working, Router call returning a valid layout. |
| 10–18 | Full loop: pay → raid → verify → settle; agent epoch: candidates → sim-score → commit. |
| 18–24 | Self-funding deposit, tier degradation, war journal on 0G Storage. **Feature freeze at H24.** |
| 24–30 | Juice, sound, voice taunts, banner art, onboarding polish, IDKit claim. |
| 30–34 | Seed a live Warlord with several raids of history, record the video, README/FEEDBACK. |
| 34–36 | Buffer and submit. |

**Cut-line:**
- **Must-have:**
  - 1 map, 3 troops, 4 towers, deterministic verified raids
  - Fee split on chain, AI redesign with request IDs, commit–reveal
  - Self-deposit loop + visible tiers, Core-kill payout
- **Nice-to-have, in this order:**
  1. Voice taunts
  2. IDKit claim
  3. Banner image generation
  4. 0G Storage journal (note: this is promoted to must-have if 0G says stacking matters)
  5. iAI sign-in advisor
  6. Leaderboard
  7. Mobile

## 8. Demo script (3 min)
- **0:00** Hook: "This Warlord has a ₿ pot and a brain it pays for itself. Its brain meter is at 👑 Genius."
- **0:20** A judge scans the QR and plays a free practice raid on their phone. Troops pour in, towers fire.
- **0:50** "Raid for real": no popup. Show the fee tx: 70% pot, 30% brain.
- **1:20** End the epoch live. The Warlord reads the replays and generates 3 fortress plans. The sim tests each against the last raids (show "Plan B holds 92% vs your archer rush"), commits the hash on chain, and taunts in voice. Show request IDs and `tee_verified: true`.
- **1:55** Show self-funding: the agent deposit tx on chain, then the Router balance going up. Drain its budget (pre-staged): the tier drops to 🐺 Feral and then 💀 Starving with a weak, lazy layout.
- **2:30** We crush the starving Warlord, the Core falls, IDKit claims the pot, payout tx. Generation 2 spawns.
- **2:50** "Every AI move is paid by itself and provable. Come back tomorrow, it's learned from you."

## 9. What validation verified
**Spikes run, logged in spikes/README.md:**
- 0G Router is live: `GET /v1/models` returns 124 models. A chat call without a key returns 401 with an **`X-Request-Id` header**.
- The 0G Payment Layer contract has bytecode on **testnet (16602) and mainnet (16661)**: a 295-byte proxy.
- npm packages exist:
  - `@0gfoundation/0g-compute-ts-sdk` 0.9.0 and `@0gfoundation/0g-ts-sdk` 1.2.8 (updated 2026-10-21)
  - `@worldcoin/idkit` 4.6.0
  - `phaser` 4.2.1
  - `@arkiv-network/sdk` 1.0.1
- From the docs: TEE verification (`verify_tee`, `x_0g_trace.request_id`, `tee_verified`) and 402 `insufficient_balance` when broke (this is our Starving trigger). Model prices show cheap tiers exist (Qwen3.7-Flash about $0.03/$0.12 per 1M tokens; Laya decision model has free input).

## 10. Couldn't verify (must resolve at the 0G workshop, Nov 5, 3:30 PM, Room 1)
1. **#1 risk:** the exact ABI/function for a programmatic **Payment Layer deposit** from an agent wallet. The docs say it's "a standard on-chain transaction signed by your wallet", but the implementation ABI isn't on the explorer.
   - Fallback: use the comfy path the track recommends (no public docs found), or the direct Compute SDK ledger deposit.
   - Last resort: disclose a manual top-up. That loses only the $1k track.
2. Is there a Router **testnet** endpoint, or must we use mainnet with the $1 email credit? A layout call costs fractions of a cent, so mainnet is fine.
3. Can one project win both 0G tracks? And is the max number of partner prizes per team still 3?
4. Is the Privy 0G app ID localhost-only? This only affects the optional iAI bonus.
5. Does the IDKit staging simulator still work for demos?
6. The exact submission deadline (the event page returned HTTP 500).

## 11. Top risks and fallbacks
| Risk | Fallback |
|---|---|
| Self-deposit not possible programmatically | comfy / Compute SDK ledger; else disclose and target the Private Computer track only |
| LLM outputs illegal or bad layouts | JSON schema + validator + sim scoring; fall back to template layouts mutated by the LLM |
| Sim non-determinism between client and server | integer math, a single shared module, a replay hash check in CI |
| Scope overrun on the game | cut-line above; freeze at H24; one map only |
| Testnet / RPC flakiness during the demo | pre-recorded backup video; local replay of a staged epoch |
| Judges' phones can't load the game | laptop play station; the QR is a bonus |

## Things to do today (before hacking starts)
1. Create a pc.0g.ai account, link email for the $1 credit, and create an API key plus an `mk-` management key.
2. Attend the 0G workshop (3:30 PM) and ask questions 1–4 above.
3. Get testnet 0G from the faucet into two wallets: deployer and agent.
