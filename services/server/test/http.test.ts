import type { Address, Hex } from "viem"
import { describe, expect, it, vi } from "vitest"
import { HttpError, createApp, type AppDeps } from "../src/http/app.js"

const ADDR = "0x00000000000000000000000000000000000000a1" as Address
const hex = (n: number) => `0x${n.toString(16).padStart(64, "0")}` as Hex

function deps(over: Partial<AppDeps> = {}): AppDeps {
  return {
    frontendOrigin: "http://localhost:5173",
    worldAction: "fealty-vote",
    worldRpId: "rp_test",
    worldMode: "onchain",
    signRpRequest: vi.fn(() => ({ sig: "0xsig", nonce: "0xnonce", createdAt: 10, expiresAt: 310 })),
    faucet: {
      check: vi.fn(() => ({ ok: true }) as const),
      isContract: vi.fn(async () => false),
      send: vi.fn(async () => ({ ethTx: hex(1), tglmTx: hex(2) })),
      record: vi.fn(),
    },
    health: async () => ({ season: "s1" }),
    snapshot: async () => ({ season: "s1" }) as never,
    now: () => 1000,
    ...over,
  }
}
const post = (app: ReturnType<typeof createApp>, path: string, json: unknown, headers: Record<string, string> = {}) =>
  app.request(path, { method: "POST", body: JSON.stringify(json), headers: { "content-type": "application/json", ...headers } })

describe("GET /health and /realm", () => {
  it("returns health with ok", async () => {
    const r = await createApp(deps()).request("/health")
    expect(await r.json()).toEqual({ ok: true, season: "s1" })
  })
  it("serves the snapshot", async () => {
    const r = await createApp(deps()).request("/realm")
    expect((await r.json()).season).toBe("s1")
  })
  it("sends CORS for the frontend origin only", async () => {
    const r = await createApp(deps()).request("/health", { headers: { origin: "http://localhost:5173" } })
    expect(r.headers.get("access-control-allow-origin")).toBe("http://localhost:5173")
  })
})

describe("POST /world/rp-context", () => {
  it("signs only the game's action and shapes IDKit's rp_context", async () => {
    const d = deps()
    const r = await post(createApp(d), "/world/rp-context", { action: "fealty-vote" })
    expect(r.status).toBe(200)
    expect(await r.json()).toEqual({ rp_id: "rp_test", nonce: "0xnonce", created_at: 10, expires_at: 310, signature: "0xsig" })
    expect(d.signRpRequest).toHaveBeenCalledWith("fealty-vote")
  })
  it("refuses to sign any other action", async () => {
    const d = deps()
    const r = await post(createApp(d), "/world/rp-context", { action: "drain-the-treasury" })
    expect(r.status).toBe(403)
    expect(d.signRpRequest).not.toHaveBeenCalled()
  })
  it("rejects malformed bodies", async () => {
    expect((await post(createApp(deps()), "/world/rp-context", {})).status).toBe(400)
    const r = await createApp(deps()).request("/world/rp-context", { method: "POST", body: "not json" })
    expect(r.status).toBe(400)
  })
})

describe("POST /world/attest", () => {
  const input = { voter: ADDR, ballotId: 1, support: true, idkitResult: { any: "thing" } }

  it("is disabled unless attested mode is on", async () => {
    expect((await post(createApp(deps()), "/world/attest", input)).status).toBe(501)
  })
  it("delegates to the attester and returns its signature", async () => {
    const attest = vi.fn(async () => ({ nullifierHash: "42", expiry: 99, signature: "0xdead" as Hex }))
    const r = await post(createApp(deps({ worldMode: "attested", attest })), "/world/attest", input)
    expect(await r.json()).toEqual({ nullifierHash: "42", expiry: 99, signature: "0xdead" })
    expect(attest).toHaveBeenCalledOnce()
  })
  it("turns a refusal into a clean error", async () => {
    const attest = vi.fn(async () => {
      throw new HttpError(403, "not eligible")
    })
    const r = await post(createApp(deps({ worldMode: "attested", attest })), "/world/attest", input)
    expect(r.status).toBe(403)
    expect(await r.json()).toEqual({ error: "not eligible" })
  })
  it("rejects a non-address voter", async () => {
    const attest = vi.fn()
    const r = await post(createApp(deps({ worldMode: "attested", attest })), "/world/attest", { ...input, voter: "bob" })
    expect(r.status).toBe(400)
    expect(attest).not.toHaveBeenCalled()
  })
})

describe("POST /faucet", () => {
  it("drips once and records it", async () => {
    const d = deps()
    const r = await post(createApp(d), "/faucet", { address: ADDR }, { "x-forwarded-for": "5.5.5.5, 6.6.6.6" })
    expect(await r.json()).toEqual({ ethTx: hex(1), tglmTx: hex(2) })
    expect(d.faucet.check).toHaveBeenCalledWith(ADDR, "5.5.5.5", 1000)
    expect(d.faucet.record).toHaveBeenCalledWith(ADDR, "5.5.5.5", 1000)
  })
  it("does not fund contracts", async () => {
    const d = deps()
    d.faucet.isContract = vi.fn(async () => true)
    expect((await post(createApp(d), "/faucet", { address: ADDR })).status).toBe(400)
    expect(d.faucet.send).not.toHaveBeenCalled()
  })
  it("maps limiter decisions to status codes without sending", async () => {
    for (const [reason, status] of [["already-funded", 409], ["ip-limit", 429], ["daily-cap", 429]] as const) {
      const d = deps()
      d.faucet.check = vi.fn(() => ({ ok: false, reason }) as const)
      const r = await post(createApp(d), "/faucet", { address: ADDR })
      expect(r.status).toBe(status)
      expect(d.faucet.send).not.toHaveBeenCalled()
      expect(d.faucet.record).not.toHaveBeenCalled()
    }
  })
  it("does not record a drip that failed to send", async () => {
    const d = deps()
    d.faucet.send = vi.fn(async () => {
      throw new Error("rpc down")
    })
    expect((await post(createApp(d), "/faucet", { address: ADDR })).status).toBe(500)
    expect(d.faucet.record).not.toHaveBeenCalled()
  })
  it("rejects a bad address", async () => {
    expect((await post(createApp(deps()), "/faucet", { address: "0x123" })).status).toBe(400)
  })
})
