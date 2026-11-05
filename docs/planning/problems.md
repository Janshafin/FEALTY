# Real problems (with evidence)

1. **Sponsors are asking for agents that pay for themselves and get thriftier when money runs low.** 0G's Mumbai track asks for exactly this: "budget-aware agents that adapt when funds run low (cheaper models, slower pace, or pausing)" and "no wallet a human keeps refilling". https://ethglobal.com/events/mumbai/prizes
   - An outside builder says the same: "Agent Payments Are Still Nobody's Problem". Inference providers require a human account and a credit card. https://dev.to/gpubridge/the-inference-market-is-consolidating-agent-payments-are-still-nobodys-problem-23ac
2. **0G wants AI that is the product, with a reason to come back.** The Private Computer track says: "something people open, use, and come back to tomorrow". It also says "not chat wrappers".
   - None of the 9 Lisbon 2026 winners was a consumer game. https://0g.ai/blog/ethglobal-lisbon-2026-recap
3. **Players will pay to beat an AI that guards real money, but the existing format is a chat box.**
   - Freysa drew 482 paid attempts from 195 players and paid out a $47k pot. https://www.theblock.co/post/328747/human-player-outwits-freysa-ai-agent-in-47000-crypto-challenge
   - The "game" was prompt injection. It had no strategy, visuals, or replay value.
4. **Players can't trust a game opponent that holds a stake.** When money is on the line, a house that controls the opponent's AI can rig difficulty.
   - 0G's Router signs each response inside a TEE and returns a `request_id`. A third party can verify the signature on chain. https://docs.0g.ai/developer-hub/building-on-0g/compute-network/router/features/verifiable-execution
5. **Fully onchain games died from weak engagement and bolted-on token economies, not from technical limits.**
   - Sky Strife was discontinued. https://games.gg/sky-strife
   - Proof of Play is winding down. Its stated reason was "fully onchain thesis… failed to materialize" (Binance Square, date unverified).
   - Lesson: the economy has to be the game itself, and the game needs a short, fun core loop.
6. **LLMs are weak at tower-defense planning when used raw.** TowerMind (AAAI 2026) found "inadequate planning validation" and "inefficient action use". https://arxiv.org/pdf/2601.05899
   - Design implication: the LLM proposes base layouts and a deterministic simulator scores them against real past raids. That gives "learning" we can verify.
7. **Bots farm onchain games, and any open pot gets botted.** World's IDKit track gives "fair access to a scarce benefit" as an example use. https://ethglobal.com/events/mumbai/prizes
