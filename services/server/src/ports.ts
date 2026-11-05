import type { Power, PledgeInput, VassalState } from "@fealty/shared"
import type { Address, Hex } from "viem"

/** The slice of Throne state the keeper needs. All times are unix seconds. */
export interface ThroneState {
  now: number
  seasonStart: number
  seasonEnd: number
  finalized: boolean
  ballotDuration: number
  minYesVotes: number
  /** No new ballot may open before this time (after a concession). */
  immuneUntil: number
  powersAlive: readonly [boolean, boolean, boolean]
  activeBallot: { id: number; power: Power; deadline: number; yes: number; electorate: number } | null
}

/** Chain access for the keeper. Implementations must simulate before sending and throw on revert. */
export interface KeeperChain {
  state(): Promise<ThroneState>
  /** Live and decreed flags for every vassal, keyed by lowercase address. */
  vassalStates(): Promise<ReadonlyMap<string, VassalState>>
  openBallot(power: Power, manifestoKey: Hex, pledges: number): Promise<Hex>
  resolve(ballotId: number): Promise<Hex>
  finalize(): Promise<Hex>
}

export interface ManifestoRecord {
  entityKey: Hex
  /** Arkiv owner of the entity. */
  owner: Address
  author: Address
  power: Power
  /** Unix seconds the entity was created, for picking the oldest campaign. */
  createdAt: number
  /** Unix seconds at which Arkiv drops the entity. */
  expiresAt: number
}

/** Arkiv access for the keeper. */
export interface KeeperArkiv {
  /** Manifestos of this season that have not expired yet. */
  liveManifestos(): Promise<ManifestoRecord[]>
  pledgesFor(manifestoKey: Hex): Promise<PledgeInput[]>
}
