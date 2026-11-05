# ETHGlobal Mumbai 2026: sponsors and prize tracks

Source: https://ethglobal.com/events/mumbai/prizes (fetched 2026-11-05). Workshops: Thu Nov 5 (IST). Hacking: ~Nov 6–8 (per https://shutternetwork.discourse.group/t/melee-2-slate-build-with-shutter-at-ethglobal-mumbai/896 and iq.wiki). The main event page returned HTTP 500, so the exact deadline is **UNVERIFIED** (check the ETHGlobal dashboard).

**"Game" or "gaming" appears in 0 of 35+ tracks.** The games steer comes only from in-person sponsor conversations. A game therefore has to satisfy each track's written requirements.

Finalist (top ~10 overall): 2-person team gets $250 USDC each + $250 travel each, plus AWS credits.

## Tracks (from-scratch eligible; Continuity-only tracks skipped)

| Sponsor | Track | $ (1st) | Key hard requirements | Judging criteria (if stated) | Game fit (my read) |
|---|---|---|---|---|---|
| 0G | Build with 0G Private Computer | 5k (2.5k) | Inference on 0G PC in main flow, request IDs; judge-tryable app; "reason to come back tomorrow"; 1 sentence "what breaks without 0G". Bonus: user signs in with 0G account (Privy, **localhost:3000/3001/5173 only**) and spends own credits | Not stated; "not a chat wrapper; AI can't be removable" | **HIGH**: AI as the core game mechanic (AI opponent/commander/generated content) |
| 0G | Physical AI | 5k (2.5k) | 0G in decision loop; episode log on 0G Storage; safe-stop fallback; sim OK | – | Low (robotics) |
| 0G | Agents That Pay for Themselves | 2k (2×1k) | Agent earns → credits its own 0G Compute → inference paid from balance; autonomous during demo; spend cap + graceful degradation; comfy CLI recommended | – | **HIGH**: an AI boss/champion that earns from players and pays for its own brain |
| World | World ID Agent Pass | 5k (2.5k) | Official Agent Pass; full journey + denied/expired path; backend validation; integration debrief | "meaningful action that needs a human identity/approval layer", not a login | MED-HIGH: human approval for an agent's high-stakes action |
| World | Best Use of IDKit | 2.5k (2×1.25k) | Credential choice justified as "minimum sufficient"; server/onchain verify; alt path demo; debrief | Best credential decision | MED: bot-free ranked ladder / one-human-one-army |
| Hedera | x402 Agents That Pay | 6.5k (3k) | x402 endpoint settling on Hedera; agent pays autonomously; HashScan link; ≤5 min demo | Extra: spend controls, ERC-8004/HCS-14 identity, HCS logs | MED: AI mercenaries hired per-call |
| Hedera | Tokenize w/ Studios | 5k | ATS / Stablecoin Studio | – | Low |
| Hedera | No Solidity | 2k (2×1k) | SDK only, ≥2 native services (HTS+HCS) | – | MED: HCS as game event log, HTS items |
| Arkiv | Build on Arkiv (scratch) | 4k (3k) | Writes via SDK; user-facing reads; schema.md, friction.md, one file per criterion; OSS license; AI disclosure | 25% each: friction feedback, reach, why Arkiv, how you use Arkiv | MED-HIGH: entities with owners + **expirations** = decaying buildings/territory |
| Arkiv | Mirror Ethereum data | 4k (3k) | Re-runnable importer | same | Low |
| Arkiv | Node tooling | 2k | – | – | None |
| Arkiv | +Swarm bonus | 0.5k | swarm.md | – | add-on |
| EF | Anon-RPC | 5k (2.5k) | Route app reads through Anon-RPC | E2E, UX, % traffic, shippable, depth | Low-Med |
| EF | Frame-tx alt mempool (EIP-8141 / ERC-8421) | 5k (2.5k) | Admitted tx on devnet or code that submits one | Creativity, usefulness, practicality, works, alt-mempool relation | MED: daily-quota paymaster = "free moves per day" game; devnet risk |
| EF | CROPS App | 3.5k (2k) | CROPS README; no trackers; ≤3 min demo | E2E, lead-property depth, other 3 hold, UX, shippable | Low-Med (unstoppable game frontend) |
| Uniswap | Build with Uniswap | 10k (4k/3k/2k/1k) | OSS repo, FEEDBACK.md, feedback form | Not stated | Low-Med (v4 hook as game economy); 4 places = best odds/$ |
| ENS | Best Use of ENSv2 | 7k (3k/2k/1k/1k) | ENSv2 central, Sepolia/mainnet, no hard-coding, live demo | Bonus: agents as namespaces | MED: guild = name, units = subnames with permissions |
| Arc | 4 × $3k tracks | 3k each | **Must be built in Arc Studio**, shown in demo | Same params | Low (USDC finance) |
| Whitechain | Operate / Tokenize / Scale | 5k / 4k / 3k | USDT settlement on Whitechain Sepolia, verified contracts | – | Low ("Scale: payments nobody notices" could fit in-game purchases) |
| 1inch | Aqua app | 5k (2.5k) | Aqua/SwapVM contracts, onchain transfers | SwapVM scores higher | None |
| Chainlink | CRE workflow / CCIP | 1.5k / 3.5k (2×1.75k) | CRE sim OK / CCIP state change in contracts | – | Low-Med |
| Definitive | Flash in social app | 2.5k | Flash advanced orders, onchain execution | – | None |

Max prize count per team is **not stated** on the page (ETHGlobal usually allows ~3 partner prizes; UNVERIFIED for Mumbai).

## Shortlist for deep-dive (game-relevant, best $/competition)
1. **0G Private Computer** ($2.5k 1st) + **0G Agents That Pay for Themselves** ($1k): a game where AI *is* the product; an AI boss that funds itself.
2. **World ID Agent Pass** ($2.5k 1st): human-approval layer on an agent's action.
3. **Arkiv from scratch** ($3k 1st): expiring entities as a game mechanic; criteria reward friction feedback (easy to score).
4. **ENSv2** ($3k 1st, 4 winners).
5. **EF alt mempool** ($2.5k 1st): quota paymaster; very niche → low competition but devnet risk.
6. **Hedera x402** ($3k 1st).
