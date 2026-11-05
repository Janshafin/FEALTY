import type { Address } from "viem"
import { describe, expect, it } from "vitest"
import { countValidPledges, type ManifestoInput, type PledgeInput, type VassalState } from "../src/index.js"

const A = "0x00000000000000000000000000000000000000a1" as const
const B = "0x00000000000000000000000000000000000000b2" as const
const C = "0x00000000000000000000000000000000000000c3" as const
const D = "0x00000000000000000000000000000000000000d4" as const

const manifesto: ManifestoInput = { entityKey: "0xman", owner: A, author: A, expired: false }
const pledge = (who: Address, key = `0xp-${who}`, over: Partial<PledgeInput> = {}): PledgeInput => ({
  entityKey: key,
  owner: who,
  pledger: who,
  manifesto: "0xman",
  ...over,
})
const vassals = (entries: [string, Partial<VassalState>][]) =>
  new Map(entries.map(([k, v]) => [k.toLowerCase(), { live: true, decreed: false, ...v }]))

describe("countValidPledges", () => {
  it("counts distinct live vassals and reports momentum against the quorum", () => {
    const r = countValidPledges(manifesto, [pledge(A), pledge(B), pledge(C)], vassals([[A, {}], [B, {}], [C, {}]]), 4)
    expect(r.valid).toBe(3)
    expect(r.momentum).toBe(0.75)
    expect(r.rejected).toEqual([])
  })

  it("caps momentum at 1", () => {
    const r = countValidPledges(manifesto, [pledge(A), pledge(B), pledge(C)], vassals([[A, {}], [B, {}], [C, {}]]), 2)
    expect(r.momentum).toBe(1)
  })

  it("rejects a pledge written by someone other than the pledger it names", () => {
    const forged = pledge(B, "0xforged", { pledger: C })
    const r = countValidPledges(manifesto, [forged], vassals([[A, {}], [B, {}], [C, {}]]), 3)
    expect(r.valid).toBe(0)
    expect(r.rejected).toEqual([{ entityKey: "0xforged", reason: "pledger-forged" }])
  })

  it("rejects pledgers who are not live vassals (banished, never joined)", () => {
    const r = countValidPledges(manifesto, [pledge(B), pledge(D)], vassals([[A, {}], [B, { live: false }]]), 3)
    expect(r.valid).toBe(0)
    expect(r.rejected.map((x) => x.reason)).toEqual(["not-a-live-vassal", "not-a-live-vassal"])
  })

  it("rejects decreed pledgers: the Tyrant's DECREE silences them", () => {
    const r = countValidPledges(manifesto, [pledge(B), pledge(C)], vassals([[A, {}], [B, { decreed: true }], [C, {}]]), 3)
    expect(r.pledgers).toEqual([C.toLowerCase()])
    expect(r.rejected).toEqual([{ entityKey: `0xp-${B}`, reason: "decreed" }])
  })

  it("counts each owner once", () => {
    const r = countValidPledges(manifesto, [pledge(B, "0x1"), pledge(B, "0x2")], vassals([[A, {}], [B, {}]]), 3)
    expect(r.valid).toBe(1)
    expect(r.rejected).toEqual([{ entityKey: "0x2", reason: "duplicate" }])
  })

  it("ignores pledges that point at another manifesto", () => {
    const r = countValidPledges(manifesto, [pledge(B, "0x1", { manifesto: "0xother" })], vassals([[A, {}], [B, {}]]), 3)
    expect(r.valid).toBe(0)
    expect(r.rejected[0]?.reason).toBe("wrong-manifesto")
  })

  it("matches addresses case-insensitively", () => {
    const upper = "0x00000000000000000000000000000000000000B2" as const
    const r = countValidPledges(manifesto, [pledge(upper, "0x1", { owner: B })], vassals([[A, {}], [B, {}]]), 3)
    expect(r.valid).toBe(1)
  })

  it("an expired manifesto counts nothing", () => {
    const r = countValidPledges({ ...manifesto, expired: true }, [pledge(B)], vassals([[A, {}], [B, {}]]), 3)
    expect(r.valid).toBe(0)
    expect(r.rejected[0]?.reason).toBe("manifesto-expired")
  })

  it("a manifesto whose author is not its Arkiv owner is forged", () => {
    const r = countValidPledges({ ...manifesto, owner: B }, [pledge(C)], vassals([[A, {}], [B, {}], [C, {}]]), 3)
    expect(r.rejected[0]?.reason).toBe("manifesto-author-forged")
  })

  it("a manifesto whose author was banished counts nothing", () => {
    const r = countValidPledges(manifesto, [pledge(B)], vassals([[A, { live: false }], [B, {}]]), 3)
    expect(r.valid).toBe(0)
    expect(r.rejected[0]?.reason).toBe("manifesto-author-not-live")
  })

  it("a zero quorum yields zero momentum instead of dividing by zero", () => {
    expect(countValidPledges(manifesto, [pledge(B)], vassals([[A, {}], [B, {}]]), 0).momentum).toBe(0)
  })
})
