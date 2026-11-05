import { POWER_NAMES, type Power } from "@fealty/shared"
import type { Address } from "viem"

/** A decoded Throne log, as produced by viem's `getLogs`/`watchContractEvent` with the Throne ABI. */
export interface ThroneLog {
  eventName: string
  args: Record<string, unknown>
  transactionHash: string
  logIndex: number
}

export interface ChronicleContext {
  season: string
  tyrant: Address
  keeper: Address
}

/** Values for one `fealty.v1.chronicle` entity. */
export interface ChronicleValues {
  season: string
  kind: string
  actor: Address
  target?: Address
  power?: number
  ballot?: number
  txHash?: string
  text?: string
}

export interface MappedLog {
  /** Stable id of the source log, used so a restart never writes an entry twice. */
  dedupeKey: string
  values: ChronicleValues
}

const POWERS = ["BANISH", "DECREE", "DISSOLVE"]
const name = (p: unknown) => POWER_NAMES[Number(p) as Power] ?? POWERS[Number(p)] ?? "?"
const trunc = (s: string, n = 140) => (s.length > n ? s.slice(0, n - 1) + "…" : s)

/**
 * Turns a Throne event into a Chronicle entry. Returns null for events the public record omits.
 * Pure: the keeper wallet signs the resulting entity, so readers trust only the keeper's entries.
 */
export function mapThroneLog(log: ThroneLog, ctx: ChronicleContext): MappedLog | null {
  const a = log.args
  const base = { season: ctx.season, txHash: log.transactionHash }
  const key = `${log.transactionHash}:${log.logIndex}`
  const ok = (values: Omit<ChronicleValues, "season" | "txHash">): MappedLog => ({
    dedupeKey: key,
    values: { ...base, ...values },
  })

  switch (log.eventName) {
    case "Joined":
      return ok({ kind: "joined", actor: a.vassal as Address, text: `${a.label} joined the court` })
    case "BannerSet":
      return ok({ kind: "banner", actor: a.vassal as Address, text: trunc(String(a.banner)) })
    case "Banished":
      return ok({ kind: "banished", actor: ctx.tyrant, target: a.vassal as Address, power: 0, text: `${a.label} was banished` })
    case "Decreed":
      return ok({ kind: "decreed", actor: ctx.tyrant, target: a.vassal as Address, power: 1, text: trunc(String(a.proclamation)) })
    case "Dissolved":
      return ok({ kind: "dissolved", actor: ctx.tyrant, target: a.vassal as Address, power: 2, text: `${a.label}'s house was dissolved` })
    case "BallotOpened":
      return ok({
        kind: "ballot-opened",
        actor: ctx.keeper,
        power: Number(a.power),
        ballot: Number(a.ballotId),
        text: `Ballot to strip ${name(a.power)} opened with ${a.pledges} pledges`,
      })
    case "Voted":
      // The nullifier is public on-chain anyway; the Chronicle records the vote, not the person.
      return ok({
        kind: "voted",
        actor: a.voter as Address,
        ballot: Number(a.ballotId),
        text: a.support ? "voted to strip the power" : "voted to keep the power",
      })
    case "VoteRemoved":
      return ok({ kind: "vote-removed", actor: a.voter as Address, ballot: Number(a.ballotId), text: "vote removed: banished" })
    case "BallotResolved":
      return ok({
        kind: "ballot-resolved",
        actor: ctx.keeper,
        ballot: Number(a.ballotId),
        text: `${a.passed ? "Passed" : "Failed"} (${a.yes} yes, ${a.no} no)`,
      })
    case "BallotCancelled":
      return ok({ kind: "ballot-cancelled", actor: ctx.tyrant, ballot: Number(a.ballotId), text: "cancelled by a concession" })
    case "PowerStripped":
      return ok({
        kind: "power-stripped",
        actor: ctx.keeper,
        power: Number(a.power),
        ballot: Number(a.ballotId),
        text: `${name(a.power)} is gone forever`,
      })
    case "Conceded":
      return ok({ kind: "conceded", actor: ctx.tyrant, power: Number(a.power), text: `The Tyrant conceded ${name(a.power)}` })
    case "OutcomeChanged":
    case "Finalized":
      return ok({ kind: "outcome", actor: ctx.keeper, text: `Outcome: ${["undecided", "rebels win", "tyrant wins", "emancipated"][Number(a.outcome)] ?? a.outcome}` })
    default:
      return null
  }
}
