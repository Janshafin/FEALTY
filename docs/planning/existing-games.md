# Existing onchain / AI games: what exists, what failed

| Game | What | Status / lesson | Source |
|---|---|---|---|
| Dark Forest | zk fog-of-war space RTS | Revamped as DF Ares; forks; Dark Frontier on World Engine. Hidden info via ZK is the known gold standard (heavy to build) | https://paragraph.xyz/@vamient-labs/aw-weekly-5 |
| Sky Strife (Lattice/MUD) | Fully onchain RTS | **Discontinued**; moved to "autonomous mode" in Aug 2024 | https://games.gg/sky-strife |
| Primodium | Onchain base-builder/factory | 0.9 added P2P trading; status unclear | https://world.mirror.xyz/LHd1yHs2zK810-ZmHmFMEbqdqhedNnGWf1sCmS9J9Fo |
| Pirate Nation (Proof of Play) | Onchain RPG | **Winding down**; "fully onchain thesis… failed to materialize" (engagement + token value) | Binance Square post (date unverified) |
| AI Arena | Train NN fighters (NFT), auto-battle | Paradigm-backed; AI trained by player, not LLM | https://medium.com/@aiarena/welcome-to-ai-arena-50983b5dd915 |
| Parallel Colony | Humans + AI avatars survival sim, agents transact (Solana) | AI agents as players | https://www.blockchaingamer.biz/?p=31058 |
| Freysa | An AI guards a prize pool; players pay rising fees to convince it to release funds | Viral 2024. **Closest prior art to "AI guards a pot"**, but it's a prompt-injection chat, not a strategy game, and it doesn't pay for its own compute | (verify link in validation) |
| Warriors AI-rena | AI agents battle (0G) | ETHGlobal Cannes 2025 0G bronze | past-winners.md |
| LLM RTS research (HIVE, Adaptive Command, rts-commander) | Natural-language/voice command of armies | Research prototypes, not onchain | https://arxiv.org/pdf/2508.16580 |

## Lessons
- Fully onchain strategy games struggled with **engagement and token economics**, not tech. Tokens bolted on don't keep players.
- Full onchain real-time state is slow and expensive; successful designs use **async/turn-based** play or commit only results.
- Open gap: **an adversary that adapts, has real stakes, and can be verified**. Today's game AIs are scripted or secret server code; the "AI with a pot" (Freysa) was a chat box, not a game.
