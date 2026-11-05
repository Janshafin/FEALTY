import { Power } from "@fealty/shared"
import type { Address } from "viem"
import { LINES, PROCLAMATIONS, pick } from "./lines.js"

export type Rule =
  | "silence-yes-voter"
  | "panic-banish-author"
  | "panic-decree-author"
  | "decree-pledger"
  | "dissolve-house"
  | "idle-taunt"

export interface PowerStatus {
  /** Still held by the Throne. Once false it never returns. */
  alive: boolean
  cooldownRemaining: number
}

export interface PolicyVassal {
  address: Address
  live: boolean
  decreed: boolean
  hasHouse: boolean
}

export interface PolicyManifesto {
  author: Address
  /** Valid pledges divided by quorum, from `countValidPledges`. */
  momentum: number
  /** Valid pledgers, earliest first. */
  pledgers: Address[]
}

export interface PolicyInput {
  powers: readonly [PowerStatus, PowerStatus, PowerStatus]
  vassals: readonly PolicyVassal[]
  manifestos: readonly PolicyManifesto[]
  /** Addresses that voted yes in the active ballot, earliest first. Empty when no ballot is active. */
  yesVoters: readonly Address[]
  config: { panic: number; worry: number; idleTaunt: number }
  rng: () => number
}

export type Action =
  | { kind: "banish"; target: Address; rule: Rule; taunt: string }
  | { kind: "decree"; target: Address; proclamation: string; rule: Rule; taunt: string }
  | { kind: "dissolve"; target: Address; rule: Rule; taunt: string }
  | { kind: "taunt"; rule: "idle-taunt"; taunt: string }

const key = (a: Address) => a.toLowerCase()

/** A power can be used right now. */
function ready(input: PolicyInput, p: Power): boolean {
  const s = input.powers[p]
  return s.alive && s.cooldownRemaining === 0
}

/**
 * Decides the Tyrant's next move. Pure: same input and random source, same output, so every rule can
 * be tested and the bot's reasoning can be logged and replayed. The first rule that applies wins;
 * a rule whose power is stripped or cooling down falls through to the next, which is what makes
 * every successful revolution genuinely weaken the Tyrant.
 *
 * Order, from most to least urgent:
 *  1. Someone voted yes in the active ballot: BANISH the earliest yes voter (their vote is removed).
 *  2. A manifesto is close to quorum: BANISH its author, or DECREE them if BANISH is gone.
 *  3. A manifesto has some momentum: DECREE its first pledger who is not yet decreed (silencing them).
 *  4. Some vassal has a house: DISSOLVE it.
 *  5. Otherwise, sometimes taunt.
 */
export function decide(input: PolicyInput): Action | null {
  const live = new Map(input.vassals.filter((v) => v.live).map((v) => [key(v.address), v]))
  const line = (rule: Rule) => pick(LINES[rule], input.rng)
  const proclamation = () => pick(PROCLAMATIONS, input.rng)

  // 1. Silence the yes voters.
  if (ready(input, Power.Banish)) {
    const target = input.yesVoters.find((a) => live.has(key(a)))
    if (target) return { kind: "banish", target, rule: "silence-yes-voter", taunt: line("silence-yes-voter") }
  }

  // The strongest campaign decides rules 2 and 3.
  const campaigns = [...input.manifestos].sort((a, b) => b.momentum - a.momentum)
  const top = campaigns[0]

  // 2. Panic: a campaign is about to reach quorum.
  if (top && top.momentum >= input.config.panic && live.has(key(top.author))) {
    if (ready(input, Power.Banish)) {
      return { kind: "banish", target: top.author, rule: "panic-banish-author", taunt: line("panic-banish-author") }
    }
    if (ready(input, Power.Decree) && !live.get(key(top.author))?.decreed) {
      return {
        kind: "decree",
        target: top.author,
        proclamation: proclamation(),
        rule: "panic-decree-author",
        taunt: line("panic-decree-author"),
      }
    }
  }

  // 3. Worry: silence a pledger of a campaign gaining ground.
  if (top && top.momentum >= input.config.worry && ready(input, Power.Decree)) {
    const target = top.pledgers.find((a) => {
      const v = live.get(key(a))
      return v !== undefined && !v.decreed
    })
    if (target) {
      return { kind: "decree", target, proclamation: proclamation(), rule: "decree-pledger", taunt: line("decree-pledger") }
    }
  }

  // 4. Tear down houses.
  if (ready(input, Power.Dissolve)) {
    const holder = [...live.values()].find((v) => v.hasHouse)
    if (holder) return { kind: "dissolve", target: holder.address, rule: "dissolve-house", taunt: line("dissolve-house") }
  }

  // 5. Idle chatter.
  if (input.rng() < input.config.idleTaunt) {
    return { kind: "taunt", rule: "idle-taunt", taunt: line("idle-taunt") }
  }
  return null
}
