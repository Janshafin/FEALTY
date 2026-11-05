import { countValidPledges, type PledgeCount } from "@fealty/shared"
import type { Hex } from "viem"
import type { KeeperArkiv, KeeperChain, ManifestoRecord, ThroneState } from "../ports.js"

export type KeeperEvent =
  | { kind: "idle"; reason: string }
  | { kind: "ballot-opened"; ballotId?: number; power: number; manifestoKey: Hex; pledges: number; tx: Hex }
  | { kind: "ballot-resolved"; ballotId: number; tx: Hex }
  | { kind: "season-finalized"; tx: Hex }
  | { kind: "error"; action: string; message: string }

export interface KeeperConfig {
  quorum: number
}

/** Mirrors `Throne.resolve`: a ballot may end early once yes votes are a majority of the electorate. */
export function canResolveEarly(b: NonNullable<ThroneState["activeBallot"]>, minYesVotes: number): boolean {
  return b.yes >= minYesVotes && b.yes * 2 > b.electorate
}

export interface Candidate {
  manifesto: ManifestoRecord
  count: PledgeCount
}

/**
 * One keeper step. It derives everything from the chain and Arkiv, never from memory, so a restart
 * or a second keeper instance does the same thing. It does at most one transaction per call.
 *
 * Priority: settle the season, finish the active ballot, otherwise open a ballot for the oldest
 * manifesto whose valid pledges reached the quorum. The keeper decides only *when* a ballot opens;
 * it cannot cast or alter votes.
 */
export async function keeperTick(
  chain: KeeperChain,
  arkiv: KeeperArkiv,
  config: KeeperConfig,
): Promise<KeeperEvent> {
  const state = await chain.state()
  const attempt = async (action: string, run: () => Promise<KeeperEvent>): Promise<KeeperEvent> => {
    try {
      return await run()
    } catch (e) {
      return { kind: "error", action, message: e instanceof Error ? e.message : String(e) }
    }
  }

  // An active ballot is finished before anything else, including after the season ends.
  const active = state.activeBallot
  if (active) {
    if (state.now >= active.deadline || canResolveEarly(active, state.minYesVotes)) {
      return attempt("resolve", async () => ({
        kind: "ballot-resolved",
        ballotId: active.id,
        tx: await chain.resolve(active.id),
      }))
    }
    return { kind: "idle", reason: `ballot ${active.id} still open` }
  }

  if (state.now >= state.seasonEnd) {
    if (!state.finalized) {
      return attempt("finalize", async () => ({ kind: "season-finalized", tx: await chain.finalize() }))
    }
    return { kind: "idle", reason: "season over" }
  }
  if (state.now < state.seasonStart) return { kind: "idle", reason: "season not started" }
  if (state.now < state.immuneUntil) return { kind: "idle", reason: "immunity period after a concession" }
  if (state.now + state.ballotDuration > state.seasonEnd) {
    return { kind: "idle", reason: "a ballot would outlast the season" }
  }

  const winner = await pickCandidate(chain, arkiv, state, config.quorum)
  if (!winner) return { kind: "idle", reason: "no manifesto at quorum" }

  const { manifesto, count } = winner
  return attempt("openBallot", async () => ({
    kind: "ballot-opened",
    power: manifesto.power,
    manifestoKey: manifesto.entityKey,
    pledges: count.valid,
    tx: await chain.openBallot(manifesto.power, manifesto.entityKey, count.valid),
  }))
}

/** The oldest live manifesto against a living power whose valid pledges reach the quorum. */
export async function pickCandidate(
  chain: KeeperChain,
  arkiv: KeeperArkiv,
  state: ThroneState,
  quorum: number,
): Promise<Candidate | null> {
  const manifestos = (await arkiv.liveManifestos())
    .filter((m) => state.powersAlive[m.power] === true)
    .sort((a, b) => a.createdAt - b.createdAt || a.entityKey.localeCompare(b.entityKey))
  if (manifestos.length === 0) return null

  const vassals = await chain.vassalStates()
  for (const manifesto of manifestos) {
    const pledges = await arkiv.pledgesFor(manifesto.entityKey)
    const count = countValidPledges(
      {
        entityKey: manifesto.entityKey,
        owner: manifesto.owner,
        author: manifesto.author,
        expired: manifesto.expiresAt <= state.now,
      },
      pledges,
      vassals,
      quorum,
    )
    if (count.valid >= quorum) return { manifesto, count }
  }
  return null
}
