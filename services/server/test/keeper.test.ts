import { Power, type PledgeInput, type VassalState } from "@fealty/shared"
import type { Address, Hex } from "viem"
import { describe, expect, it } from "vitest"
import type { KeeperArkiv, KeeperChain, ManifestoRecord, ThroneState } from "../src/ports.js"
import { canResolveEarly, keeperTick } from "../src/keeper/tick.js"

const a = (n: number) => `0x${n.toString(16).padStart(40, "0")}` as Address
const [ALICE, BOB, CAROL, DAVE] = [a(1), a(2), a(3), a(4)]
const hex = (n: number) => `0x${n.toString(16).padStart(64, "0")}` as Hex

const baseState = (over: Partial<ThroneState> = {}): ThroneState => ({
  now: 1000,
  seasonStart: 900,
  seasonEnd: 2800,
  finalized: false,
  ballotDuration: 120,
  minYesVotes: 1,
  immuneUntil: 0,
  powersAlive: [true, true, true],
  activeBallot: null,
  ...over,
})

class FakeChain implements KeeperChain {
  calls: string[] = []
  fail: string | null = null
  constructor(
    public s: ThroneState,
    public vassals: Map<string, VassalState> = new Map(
      [ALICE, BOB, CAROL, DAVE].map((x) => [x.toLowerCase(), { live: true, decreed: false }]),
    ),
  ) {}
  async state() {
    return this.s
  }
  async vassalStates() {
    return this.vassals
  }
  private async send(name: string): Promise<Hex> {
    if (this.fail === name) throw new Error(`${name} reverted`)
    this.calls.push(name)
    return hex(99)
  }
  openBallot(p: Power, k: Hex, n: number) {
    this.calls.push(`open:${p}:${k}:${n}`)
    return this.fail === "openBallot" ? Promise.reject(new Error("openBallot reverted")) : Promise.resolve(hex(99))
  }
  resolve(id: number) {
    return this.send(`resolve:${id}`)
  }
  finalize() {
    return this.send("finalize")
  }
}

const manifesto = (n: number, over: Partial<ManifestoRecord> = {}): ManifestoRecord => ({
  entityKey: hex(n),
  owner: ALICE,
  author: ALICE,
  power: Power.Decree,
  createdAt: 100 + n,
  expiresAt: 5000,
  ...over,
})
const pledge = (who: Address, m: Hex, key = `p-${who}`): PledgeInput => ({
  entityKey: key as Hex,
  owner: who,
  pledger: who,
  manifesto: m,
})
const arkiv = (ms: ManifestoRecord[], ps: Record<string, PledgeInput[]> = {}): KeeperArkiv => ({
  async liveManifestos() {
    return ms
  },
  async pledgesFor(k) {
    return ps[k] ?? []
  },
})

const atQuorum = (m: Hex) => [pledge(BOB, m), pledge(CAROL, m), pledge(DAVE, m)]

describe("opening ballots", () => {
  it("opens a ballot for a manifesto that reached the quorum, recording the key and count", async () => {
    const chain = new FakeChain(baseState())
    const m = manifesto(1)
    const ev = await keeperTick(chain, arkiv([m], { [m.entityKey]: atQuorum(m.entityKey) }), { quorum: 3 })
    expect(ev).toMatchObject({ kind: "ballot-opened", power: Power.Decree, manifestoKey: m.entityKey, pledges: 3 })
    expect(chain.calls).toEqual([`open:1:${m.entityKey}:3`])
  })

  it("does nothing below the quorum", async () => {
    const chain = new FakeChain(baseState())
    const m = manifesto(1)
    const ev = await keeperTick(chain, arkiv([m], { [m.entityKey]: atQuorum(m.entityKey).slice(0, 2) }), { quorum: 3 })
    expect(ev).toMatchObject({ kind: "idle", reason: "no manifesto at quorum" })
    expect(chain.calls).toEqual([])
  })

  it("counts only valid pledges: forged and decreed ones do not reach the quorum", async () => {
    const chain = new FakeChain(baseState())
    chain.vassals.set(CAROL.toLowerCase(), { live: true, decreed: true })
    const m = manifesto(1)
    const pledges = [pledge(BOB, m.entityKey), pledge(CAROL, m.entityKey), { ...pledge(DAVE, m.entityKey), owner: BOB }]
    const ev = await keeperTick(chain, arkiv([m], { [m.entityKey]: pledges }), { quorum: 3 })
    expect(ev.kind).toBe("idle")
  })

  it("prefers the oldest manifesto when several reached the quorum", async () => {
    const chain = new FakeChain(baseState())
    const older = manifesto(1, { power: Power.Banish, createdAt: 10 })
    const newer = manifesto(2, { power: Power.Dissolve, createdAt: 20 })
    const ps = { [older.entityKey]: atQuorum(older.entityKey), [newer.entityKey]: atQuorum(newer.entityKey) }
    const ev = await keeperTick(chain, arkiv([newer, older], ps), { quorum: 3 })
    expect(ev).toMatchObject({ kind: "ballot-opened", power: Power.Banish })
  })

  it("skips a manifesto against an already-stripped power and takes the next", async () => {
    const chain = new FakeChain(baseState({ powersAlive: [true, false, true] }))
    const dead = manifesto(1, { power: Power.Decree, createdAt: 10 })
    const live = manifesto(2, { power: Power.Dissolve, createdAt: 20 })
    const ps = { [dead.entityKey]: atQuorum(dead.entityKey), [live.entityKey]: atQuorum(live.entityKey) }
    expect(await keeperTick(chain, arkiv([dead, live], ps), { quorum: 3 })).toMatchObject({ power: Power.Dissolve })
  })

  it("ignores an expired manifesto", async () => {
    const chain = new FakeChain(baseState())
    const m = manifesto(1, { expiresAt: 1000 })
    const ev = await keeperTick(chain, arkiv([m], { [m.entityKey]: atQuorum(m.entityKey) }), { quorum: 3 })
    expect(ev.kind).toBe("idle")
  })

  it.each([
    ["the season has not started", { seasonStart: 2000 }],
    ["after a concession", { immuneUntil: 1500 }],
    ["when the ballot would outlast the season", { seasonEnd: 1100 }],
  ])("waits %s", async (_label, over) => {
    const chain = new FakeChain(baseState(over))
    const m = manifesto(1)
    const ev = await keeperTick(chain, arkiv([m], { [m.entityKey]: atQuorum(m.entityKey) }), { quorum: 3 })
    expect(ev.kind).toBe("idle")
    expect(chain.calls).toEqual([])
  })

  it("reports a revert instead of throwing, so the loop survives", async () => {
    const chain = new FakeChain(baseState())
    chain.fail = "openBallot"
    const m = manifesto(1)
    const ev = await keeperTick(chain, arkiv([m], { [m.entityKey]: atQuorum(m.entityKey) }), { quorum: 3 })
    expect(ev).toEqual({ kind: "error", action: "openBallot", message: "openBallot reverted" })
  })
})

describe("finishing ballots", () => {
  const ballot = (over = {}) => ({ id: 4, power: Power.Banish, deadline: 1100, yes: 0, electorate: 5, ...over })

  it("leaves an open ballot alone", async () => {
    const chain = new FakeChain(baseState({ activeBallot: ballot() }))
    expect((await keeperTick(chain, arkiv([]), { quorum: 3 })).kind).toBe("idle")
    expect(chain.calls).toEqual([])
  })

  it("resolves at the deadline", async () => {
    const chain = new FakeChain(baseState({ now: 1100, activeBallot: ballot() }))
    expect(await keeperTick(chain, arkiv([]), { quorum: 3 })).toMatchObject({ kind: "ballot-resolved", ballotId: 4 })
    expect(chain.calls).toEqual(["resolve:4"])
  })

  it("resolves early on a majority of the electorate", async () => {
    const chain = new FakeChain(baseState({ activeBallot: ballot({ yes: 3 }) }))
    expect(await keeperTick(chain, arkiv([]), { quorum: 3 })).toMatchObject({ kind: "ballot-resolved" })
  })

  it("does not resolve early on exactly half", async () => {
    expect(canResolveEarly(ballot({ yes: 2, electorate: 4 }), 1)).toBe(false)
    expect(canResolveEarly(ballot({ yes: 3, electorate: 4 }), 1)).toBe(true)
  })

  it("honours the minimum yes floor", async () => {
    expect(canResolveEarly(ballot({ yes: 1, electorate: 1 }), 2)).toBe(false)
  })

  it("finishes a ballot even after the season ended, before finalizing", async () => {
    const chain = new FakeChain(baseState({ now: 3000, activeBallot: ballot({ deadline: 2800 }) }))
    expect(await keeperTick(chain, arkiv([]), { quorum: 3 })).toMatchObject({ kind: "ballot-resolved" })
  })

  it("reports a failed resolve as an error", async () => {
    const chain = new FakeChain(baseState({ now: 1100, activeBallot: ballot() }))
    chain.fail = "resolve:4"
    expect(await keeperTick(chain, arkiv([]), { quorum: 3 })).toMatchObject({ kind: "error", action: "resolve" })
  })
})

describe("season end", () => {
  it("finalizes once", async () => {
    const chain = new FakeChain(baseState({ now: 2800 }))
    expect((await keeperTick(chain, arkiv([]), { quorum: 3 })).kind).toBe("season-finalized")
    chain.s = baseState({ now: 2900, finalized: true })
    expect(await keeperTick(chain, arkiv([]), { quorum: 3 })).toMatchObject({ kind: "idle", reason: "season over" })
    expect(chain.calls).toEqual(["finalize"])
  })

  it("never opens a ballot after the season", async () => {
    const chain = new FakeChain(baseState({ now: 2900, finalized: true }))
    const m = manifesto(1)
    await keeperTick(chain, arkiv([m], { [m.entityKey]: atQuorum(m.entityKey) }), { quorum: 3 })
    expect(chain.calls).toEqual([])
  })
})

function ballot(over = {}) {
  return { id: 4, power: Power.Banish, deadline: 1100, yes: 0, electorate: 5, ...over }
}
