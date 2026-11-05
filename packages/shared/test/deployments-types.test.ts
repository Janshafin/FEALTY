import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { describe, expect, it } from "vitest"
import { RealmSnapshotSchema, loadDeployment } from "../src/index.js"

const addr = (n: number) => `0x${n.toString(16).padStart(40, "0")}`

const valid = {
  chainId: 11155111,
  season: "s1",
  realmLabel: "fealty",
  deployBlock: 100,
  addresses: Object.fromEntries(
    ["labelStore", "factory", "resolverImpl", "realm", "court", "throne", "bannerResolver", "decreeResolver", "worldId", "ethRegistry", "universalResolver"].map(
      (k, i) => [k, addr(i + 1)],
    ),
  ),
  config: {
    tyrant: addr(100),
    keeper: addr(101),
    attester: addr(0),
    worldMode: "onchain",
    externalNullifierHash: "123456789",
    seasonStart: 1,
    seasonEnd: 1801,
    powerCooldown: 45,
    ballotDuration: 120,
    concedeImmunity: 60,
    minYesVotes: 1,
  },
  throneAbiHash: "0xabc",
}

function root(file: unknown) {
  const dir = mkdtempSync(join(tmpdir(), "fealty-dep-"))
  mkdirSync(join(dir, "deployments", "11155111"), { recursive: true })
  writeFileSync(join(dir, "deployments", "11155111", "s1.json"), JSON.stringify(file))
  return dir
}

describe("loadDeployment", () => {
  it("loads a valid file", () => {
    const d = loadDeployment(11155111, "s1", root(valid))
    expect(d.addresses.throne).toBe(addr(6))
    expect(d.config.worldMode).toBe("onchain")
  })

  it("explains a missing file", () => {
    expect(() => loadDeployment(11155111, "nope", root(valid))).toThrow(/No deployment file/)
  })

  it("rejects malformed addresses and modes", () => {
    const bad = { ...valid, addresses: { ...valid.addresses, throne: "0x123" } }
    expect(() => loadDeployment(11155111, "s1", root(bad))).toThrow(/Invalid deployment file/)
    const badMode = { ...valid, config: { ...valid.config, worldMode: "mock" } }
    expect(() => loadDeployment(11155111, "s1", root(badMode))).toThrow(/Invalid deployment file/)
  })
})

describe("RealmSnapshotSchema", () => {
  const power = (p: 0 | 1 | 2) => ({ power: p, name: "BANISH", ensRole: "ROLE_UNREGISTER", alive: true, cooldownRemaining: 0 })
  const snapshot = {
    season: "s1",
    courtName: "s1.fealty.eth",
    chainId: 11155111,
    outcome: "undecided",
    finalized: false,
    seasonStart: 1,
    seasonEnd: 1801,
    now: 5,
    powers: [power(0), power(1), power(2)],
    vassals: [],
    activeBallot: null,
    manifestos: [],
    chronicle: [],
    config: {
      quorum: 3,
      minYesVotes: 1,
      ballotDuration: 120,
      powerCooldown: 45,
      worldMode: "onchain",
      tyrant: addr(1),
      keeper: addr(2),
      throne: addr(3),
      court: addr(4),
    },
    updatedAtBlock: 10,
  }

  it("accepts a well-formed snapshot", () => {
    expect(RealmSnapshotSchema.parse(snapshot).season).toBe("s1")
  })

  it("rejects an unknown outcome and a missing power", () => {
    expect(RealmSnapshotSchema.safeParse({ ...snapshot, outcome: "won" }).success).toBe(false)
    expect(RealmSnapshotSchema.safeParse({ ...snapshot, powers: [power(0), power(1)] }).success).toBe(false)
  })
})
