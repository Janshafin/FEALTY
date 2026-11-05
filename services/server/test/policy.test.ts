import { Power } from "@fealty/shared"
import type { Address } from "viem"
import { describe, expect, it } from "vitest"
import { LINES, PROCLAMATIONS } from "../src/tyrant/lines.js"
import { decide, type PolicyInput, type PolicyVassal } from "../src/tyrant/policy.js"

const a = (n: number) => `0x${n.toString(16).padStart(40, "0")}` as Address
const [ALICE, BOB, CAROL, DAVE] = [a(1), a(2), a(3), a(4)]

const ready = { alive: true, cooldownRemaining: 0 }
const gone = { alive: false, cooldownRemaining: 0 }
const cooling = { alive: true, cooldownRemaining: 20 }

const vassal = (address: Address, over: Partial<PolicyVassal> = {}): PolicyVassal => ({
  address,
  live: true,
  decreed: false,
  hasHouse: false,
  ...over,
})

function input(over: Partial<PolicyInput> = {}): PolicyInput {
  return {
    powers: [ready, ready, ready],
    vassals: [vassal(ALICE), vassal(BOB), vassal(CAROL)],
    manifestos: [],
    yesVoters: [],
    config: { panic: 0.6, worry: 0.3, idleTaunt: 0.2 },
    rng: () => 0.99, // never idle-taunts, always picks the last line
    ...over,
  }
}

describe("rule 1: silence yes voters", () => {
  it("banishes the earliest yes voter", () => {
    const r = decide(input({ yesVoters: [BOB, CAROL] }))
    expect(r).toMatchObject({ kind: "banish", target: BOB, rule: "silence-yes-voter" })
  })

  it("skips voters who are no longer live and takes the next", () => {
    const r = decide(input({ yesVoters: [DAVE, CAROL] }))
    expect(r).toMatchObject({ kind: "banish", target: CAROL })
  })

  it("falls through once BANISH is stripped", () => {
    expect(decide(input({ powers: [gone, ready, ready], yesVoters: [BOB] }))).toBeNull()
  })

  it("falls through while BANISH cools down", () => {
    expect(decide(input({ powers: [cooling, ready, ready], yesVoters: [BOB] }))).toBeNull()
  })

  it("takes priority over a panicking manifesto", () => {
    const r = decide(
      input({ yesVoters: [CAROL], manifestos: [{ author: ALICE, momentum: 0.9, pledgers: [BOB] }] }),
    )
    expect(r).toMatchObject({ rule: "silence-yes-voter", target: CAROL })
  })
})

describe("rule 2: panic", () => {
  const panicking = { author: ALICE, momentum: 0.7, pledgers: [BOB, CAROL] }

  it("banishes the author of a near-quorum manifesto", () => {
    expect(decide(input({ manifestos: [panicking] }))).toMatchObject({
      kind: "banish",
      target: ALICE,
      rule: "panic-banish-author",
    })
  })

  it("decrees the author instead when BANISH is gone", () => {
    const r = decide(input({ powers: [gone, ready, ready], manifestos: [panicking] }))
    expect(r).toMatchObject({ kind: "decree", target: ALICE, rule: "panic-decree-author" })
    expect(PROCLAMATIONS).toContain((r as { proclamation: string }).proclamation)
  })

  it("does nothing about it once BANISH and DECREE are both gone (the crown is weaker)", () => {
    expect(decide(input({ powers: [gone, gone, ready], manifestos: [panicking] }))).toBeNull()
  })

  it("does not decree an author who is already decreed", () => {
    const vs = [vassal(ALICE, { decreed: true }), vassal(BOB)]
    const noPledgers = { author: ALICE, momentum: 0.7, pledgers: [] }
    expect(decide(input({ powers: [gone, ready, ready], vassals: vs, manifestos: [noPledgers] }))).toBeNull()
  })

  it("falls through to silencing a pledger when the author is already decreed", () => {
    const vs = [vassal(ALICE, { decreed: true }), vassal(BOB)]
    const r = decide(input({ powers: [gone, ready, ready], vassals: vs, manifestos: [panicking] }))
    expect(r).toMatchObject({ kind: "decree", target: BOB, rule: "decree-pledger" })
  })

  it("only reacts at the panic threshold", () => {
    const r = decide(input({ manifestos: [{ author: ALICE, momentum: 0.59, pledgers: [] }] }))
    expect(r).toBeNull()
  })

  it("targets the strongest campaign", () => {
    const r = decide(
      input({
        manifestos: [
          { author: BOB, momentum: 0.65, pledgers: [] },
          { author: CAROL, momentum: 0.8, pledgers: [] },
        ],
      }),
    )
    expect(r).toMatchObject({ target: CAROL })
  })

  it("ignores a manifesto whose author is already gone", () => {
    const vs = [vassal(ALICE, { live: false }), vassal(BOB)]
    expect(decide(input({ vassals: vs, manifestos: [{ author: ALICE, momentum: 0.9, pledgers: [] }] }))).toBeNull()
  })
})

describe("rule 3: decree a pledger", () => {
  const worrying = { author: ALICE, momentum: 0.4, pledgers: [BOB, CAROL] }

  it("decrees the first pledger who is not yet decreed", () => {
    const vs = [vassal(ALICE), vassal(BOB, { decreed: true }), vassal(CAROL)]
    const r = decide(input({ vassals: vs, manifestos: [worrying] }))
    expect(r).toMatchObject({ kind: "decree", target: CAROL, rule: "decree-pledger" })
  })

  it("needs DECREE to be ready", () => {
    expect(decide(input({ powers: [ready, cooling, ready], manifestos: [worrying] }))).toBeNull()
    expect(decide(input({ powers: [ready, gone, ready], manifestos: [worrying] }))).toBeNull()
  })

  it("does nothing when every pledger is already decreed", () => {
    const vs = [vassal(ALICE), vassal(BOB, { decreed: true }), vassal(CAROL, { decreed: true })]
    expect(decide(input({ vassals: vs, manifestos: [worrying] }))).toBeNull()
  })

  it("stays quiet below the worry threshold", () => {
    expect(decide(input({ manifestos: [{ ...worrying, momentum: 0.29 }] }))).toBeNull()
  })
})

describe("rule 4: dissolve houses", () => {
  it("dissolves the first house it finds", () => {
    const vs = [vassal(ALICE), vassal(BOB, { hasHouse: true })]
    expect(decide(input({ vassals: vs }))).toMatchObject({ kind: "dissolve", target: BOB, rule: "dissolve-house" })
  })

  it("needs DISSOLVE to be ready", () => {
    const vs = [vassal(BOB, { hasHouse: true })]
    expect(decide(input({ vassals: vs, powers: [ready, ready, gone] }))).toBeNull()
    expect(decide(input({ vassals: vs, powers: [ready, ready, cooling] }))).toBeNull()
  })

  it("ignores houses of vassals who are gone", () => {
    expect(decide(input({ vassals: [vassal(BOB, { hasHouse: true, live: false })] }))).toBeNull()
  })
})

describe("rule 5: idle", () => {
  it("taunts when the random draw is under the idle probability", () => {
    const r = decide(input({ rng: () => 0.1 }))
    expect(r).toMatchObject({ kind: "taunt", rule: "idle-taunt" })
  })

  it("stays silent otherwise", () => {
    expect(decide(input())).toBeNull()
  })
})

describe("general", () => {
  it("is deterministic for the same input and random source", () => {
    const i = input({ yesVoters: [BOB] })
    expect(decide(i)).toEqual(decide(i))
  })

  it("only ever says lines from its own list", () => {
    const r = decide(input({ yesVoters: [BOB], rng: () => 0 }))
    expect(LINES["silence-yes-voter"]).toContain((r as { taunt: string }).taunt)
  })

  it("a fully stripped Tyrant can only talk", () => {
    const i = input({
      powers: [gone, gone, gone],
      yesVoters: [BOB],
      vassals: [vassal(BOB, { hasHouse: true })],
      manifestos: [{ author: BOB, momentum: 1, pledgers: [BOB] }],
      rng: () => 0.1,
    })
    expect(decide(i)).toMatchObject({ kind: "taunt" })
  })

  it("exposes the power ids used by the shared package", () => {
    expect([Power.Banish, Power.Decree, Power.Dissolve]).toEqual([0, 1, 2])
  })
})
