import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import type { Address } from "viem"
import { describe, expect, it } from "vitest"
import { mapThroneLog } from "../src/chronicle/map.js"
import { SeenStore } from "../src/chronicle/seen.js"
import { loadConfig } from "../src/config.js"
import { FaucetLimiter } from "../src/faucet/limiter.js"

const pk = "0x" + "11".repeat(32)
const goodEnv = {
  SEPOLIA_RPC_URL: "https://rpc.example",
  KEEPER_PK: pk,
  TYRANT_PK: pk,
  FAUCET_PK: pk,
  SEASON: "s1",
  WORLD_APP_ID: "app_x",
  WORLD_RP_ID: "rp_x",
  WORLD_RP_SIGNING_KEY: "sk",
}
const tmp = () => mkdtempSync(join(tmpdir(), "fealty-"))

describe("loadConfig", () => {
  it("applies defaults", () => {
    const c = loadConfig(goodEnv)
    expect(c.WORLD_MODE).toBe("onchain")
    expect(c.QUORUM_PLEDGES).toBe(3)
    expect(c.TYRANT_ENABLED).toBe(true)
    expect(c.PORT).toBe(8787)
  })

  it("lists every problem and never echoes secrets", () => {
    const bad = { ...goodEnv, SEPOLIA_RPC_URL: "nope", KEEPER_PK: "0xsecretvalue", SEASON: "" }
    let msg = ""
    try {
      loadConfig(bad)
    } catch (e) {
      msg = (e as Error).message
    }
    expect(msg).toContain("SEPOLIA_RPC_URL")
    expect(msg).toContain("KEEPER_PK")
    expect(msg).toContain("SEASON")
    expect(msg).not.toContain("secretvalue")
  })

  it("requires the attester key in attested mode", () => {
    expect(() => loadConfig({ ...goodEnv, WORLD_MODE: "attested" })).toThrow(/ATTESTER_PK/)
    expect(loadConfig({ ...goodEnv, WORLD_MODE: "attested", ATTESTER_PK: pk }).WORLD_MODE).toBe("attested")
  })

  it("rejects an odd manifesto TTL", () => {
    expect(() => loadConfig({ ...goodEnv, MANIFESTO_TTL_S: "181" })).toThrow(/even/)
  })
})

describe("mapThroneLog", () => {
  const ctx = { season: "s1", tyrant: "0x00000000000000000000000000000000000000t1" as Address, keeper: "0x00000000000000000000000000000000000000k1" as Address }
  const v = "0x00000000000000000000000000000000000000a1" as Address
  const log = (eventName: string, args: Record<string, unknown>) => ({ eventName, args, transactionHash: "0xabc", logIndex: 3 })

  it("maps a ban to the Tyrant as actor and the vassal as target", () => {
    const m = mapThroneLog(log("Banished", { vassal: v, label: "alice" }), ctx)
    expect(m).toMatchObject({ dedupeKey: "0xabc:3", values: { kind: "banished", actor: ctx.tyrant, target: v, power: 0, txHash: "0xabc", season: "s1" } })
  })

  it("maps votes to the voter", () => {
    expect(mapThroneLog(log("Voted", { ballotId: 2n, voter: v, support: true }), ctx)?.values).toMatchObject({ kind: "voted", actor: v, ballot: 2 })
  })

  it("names the stripped power", () => {
    const m = mapThroneLog(log("PowerStripped", { power: 1, ballotId: 4n }), ctx)
    expect(m?.values.text).toBe("DECREE is gone forever")
    expect(m?.values).toMatchObject({ kind: "power-stripped", power: 1, ballot: 4 })
  })

  it("truncates long banners", () => {
    const m = mapThroneLog(log("BannerSet", { vassal: v, label: "a", banner: "x".repeat(300) }), ctx)
    expect(m?.values.text?.length).toBe(140)
  })

  it("covers every Throne event the record keeps and skips others", () => {
    const names = ["Joined", "BannerSet", "Banished", "Decreed", "Dissolved", "BallotOpened", "Voted", "VoteRemoved", "BallotResolved", "BallotCancelled", "PowerStripped", "Conceded", "OutcomeChanged", "Finalized"]
    const args = { vassal: v, voter: v, label: "x", banner: "b", proclamation: "p", power: 0, ballotId: 1n, pledges: 3, support: false, passed: true, yes: 1, no: 0, outcome: 1 }
    for (const n of names) expect(mapThroneLog(log(n, args), ctx), n).not.toBeNull()
    expect(mapThroneLog(log("HouseRegistered", args), ctx)).toBeNull()
  })
})

describe("SeenStore", () => {
  it("persists across restarts", () => {
    const path = join(tmp(), "seen.json")
    const a = new SeenStore(path)
    expect(a.has("x")).toBe(false)
    a.add(["x", "y"])
    const b = new SeenStore(path)
    expect(b.has("x")).toBe(true)
    expect(b.size).toBe(2)
  })
})

describe("FaucetLimiter", () => {
  const T = 1_800_000_000
  const make = (over = {}) => new FaucetLimiter(join(tmp(), "f.json"), { perIpPerDay: 2, globalPerDay: 3, ...over })

  it("funds an address once", () => {
    const f = make()
    expect(f.check("0xAA", "1.1.1.1", T)).toEqual({ ok: true })
    f.record("0xAA", "1.1.1.1", T)
    expect(f.check("0xaa", "2.2.2.2", T)).toEqual({ ok: false, reason: "already-funded" })
  })

  it("limits each IP per day and resets the next day", () => {
    const f = make()
    f.record("0x01", "9.9.9.9", T)
    f.record("0x02", "9.9.9.9", T)
    expect(f.check("0x03", "9.9.9.9", T)).toEqual({ ok: false, reason: "ip-limit" })
    expect(f.check("0x03", "9.9.9.9", T + 86_400)).toEqual({ ok: true })
  })

  it("enforces a global daily cap", () => {
    const f = make()
    ;["0x01", "0x02", "0x03"].forEach((a, i) => f.record(a, `ip${i}`, T))
    expect(f.check("0x04", "ip9", T)).toEqual({ ok: false, reason: "daily-cap" })
  })

  it("keeps its limits across restarts", () => {
    const path = join(tmp(), "f.json")
    new FaucetLimiter(path, { perIpPerDay: 2, globalPerDay: 3 }).record("0x01", "ip", T)
    expect(new FaucetLimiter(path, { perIpPerDay: 2, globalPerDay: 3 }).check("0x01", "ip", T)).toEqual({ ok: false, reason: "already-funded" })
  })
})
