import type { Address } from "viem"

/** What the chain says about one vassal. */
export interface VassalState {
  /** Joined this season, not banished, and still holding a live name. */
  live: boolean
  /** The name currently points at the Tyrant's decree resolver. */
  decreed: boolean
}

export interface ManifestoInput {
  entityKey: string
  /** Arkiv owner of the entity: the account that signed the write. */
  owner: Address
  /** Author claimed in the entity's attributes. */
  author: Address
  expired: boolean
}

export interface PledgeInput {
  entityKey: string
  /** Arkiv owner of the entity: the account that signed the write. */
  owner: Address
  /** Pledger claimed in the entity's attributes. */
  pledger: Address
  /** Manifesto the pledge points at. */
  manifesto: string
}

export type RejectReason =
  | "manifesto-expired"
  | "manifesto-author-forged"
  | "manifesto-author-not-live"
  | "wrong-manifesto"
  | "pledger-forged"
  | "not-a-live-vassal"
  | "decreed"
  | "duplicate"

export interface PledgeVerdict {
  entityKey: string
  reason: RejectReason
}

export interface PledgeCount {
  /** Number of distinct valid pledgers. */
  valid: number
  /** Distinct valid pledger addresses, lowercase. */
  pledgers: Address[]
  rejected: PledgeVerdict[]
  /** `valid / quorum`, capped at 1. */
  momentum: number
}

function key(a: Address): string {
  return a.toLowerCase()
}

/**
 * Counts the pledges of one manifesto that may count towards a quorum. This is the single rule
 * set shared by the keeper (to open a ballot), the Tyrant bot and the read API (to show momentum).
 *
 * A pledge counts only if all of these hold:
 *  - the manifesto is not expired, was written by the author it names, and its author is a live vassal;
 *  - the pledge points at this manifesto;
 *  - the Arkiv owner of the pledge is the pledger it names (so nobody can pledge on another's behalf);
 *  - that owner is a live vassal who is not currently decreed;
 *  - it is the first counted pledge from that owner.
 */
export function countValidPledges(
  manifesto: ManifestoInput,
  pledges: readonly PledgeInput[],
  vassals: ReadonlyMap<string, VassalState>,
  quorum: number,
): PledgeCount {
  const out: PledgeCount = { valid: 0, pledgers: [], rejected: [], momentum: 0 }
  const rejectAll = (reason: RejectReason): PledgeCount => {
    out.rejected = pledges.map((p) => ({ entityKey: p.entityKey, reason }))
    return out
  }

  if (manifesto.expired) return rejectAll("manifesto-expired")
  if (key(manifesto.owner) !== key(manifesto.author)) return rejectAll("manifesto-author-forged")
  if (!vassals.get(key(manifesto.author))?.live) return rejectAll("manifesto-author-not-live")

  const seen = new Set<string>()
  for (const p of pledges) {
    const reject = (reason: RejectReason) => out.rejected.push({ entityKey: p.entityKey, reason })
    if (p.manifesto !== manifesto.entityKey) {
      reject("wrong-manifesto")
      continue
    }
    if (key(p.owner) !== key(p.pledger)) {
      reject("pledger-forged")
      continue
    }
    const state = vassals.get(key(p.owner))
    if (!state?.live) {
      reject("not-a-live-vassal")
      continue
    }
    if (state.decreed) {
      reject("decreed")
      continue
    }
    if (seen.has(key(p.owner))) {
      reject("duplicate")
      continue
    }
    seen.add(key(p.owner))
    out.pledgers.push(key(p.owner) as Address)
  }
  out.valid = out.pledgers.length
  out.momentum = quorum > 0 ? Math.min(1, out.valid / quorum) : 0
  return out
}
