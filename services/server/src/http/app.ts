import type { RealmSnapshot } from "@fealty/shared"
import { Hono } from "hono"
import { cors } from "hono/cors"
import { isAddress, type Address, type Hex } from "viem"
import { z } from "zod"
import type { FaucetDecision } from "../faucet/limiter.js"

/** Everything the HTTP layer needs from the outside, so routes can be tested without a network. */
export interface AppDeps {
  frontendOrigin: string
  worldAction: string
  worldRpId: string
  worldMode: "onchain" | "attested"
  /** Signs an IDKit request. Wraps `signRequest` from `@worldcoin/idkit-core/signing`. */
  signRpRequest(action: string): { sig: string; nonce: string; createdAt: number; expiresAt: number }
  faucet: {
    check(address: Address, ip: string, nowSeconds: number): FaucetDecision
    isContract(address: Address): Promise<boolean>
    send(address: Address): Promise<{ ethTx: Hex; tglmTx: Hex | null }>
    record(address: Address, ip: string, nowSeconds: number): void
  }
  /** Mode B only. Verifies the proof with World, checks the vote is allowed and signs it. */
  attest?(input: AttestInput): Promise<{ nullifierHash: string; expiry: number; signature: Hex }>
  health(): Promise<Record<string, unknown>>
  snapshot(): Promise<RealmSnapshot>
  now(): number
}

const address = z.string().refine((a) => isAddress(a), "not an address").transform((a) => a as Address)

export const AttestInput = z.object({
  voter: address,
  ballotId: z.number().int().positive(),
  support: z.boolean(),
  /** The unmodified IDKit result payload. */
  idkitResult: z.unknown(),
})
export type AttestInput = z.infer<typeof AttestInput>

export class HttpError extends Error {
  constructor(
    readonly status: 400 | 403 | 404 | 409 | 429 | 501 | 502,
    message: string,
  ) {
    super(message)
  }
}

/** Builds the HTTP app. Routes only validate, delegate and shape responses. */
export function createApp(d: AppDeps): Hono {
  const app = new Hono()
  app.use("*", cors({ origin: d.frontendOrigin }))

  app.onError((err, c) => {
    if (err instanceof HttpError) return c.json({ error: err.message }, err.status)
    console.error(JSON.stringify({ level: "error", msg: err.message }))
    return c.json({ error: "internal error" }, 500)
  })

  const body = async <T>(c: { req: { json(): Promise<unknown> } }, schema: z.ZodType<T>): Promise<T> => {
    let raw: unknown
    try {
      raw = await c.req.json()
    } catch {
      throw new HttpError(400, "body must be JSON")
    }
    const r = schema.safeParse(raw)
    if (!r.success) throw new HttpError(400, r.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; "))
    return r.data
  }

  app.get("/health", async (c) => c.json({ ok: true, ...(await d.health()) }))
  app.get("/realm", async (c) => c.json(await d.snapshot()))

  // IDKit needs a backend-signed request context. Only our one action is ever signed.
  app.post("/world/rp-context", async (c) => {
    const { action } = await body(c, z.object({ action: z.string() }))
    if (action !== d.worldAction) throw new HttpError(403, "unknown action")
    const s = d.signRpRequest(action)
    return c.json({
      rp_id: d.worldRpId,
      nonce: s.nonce,
      created_at: s.createdAt,
      expires_at: s.expiresAt,
      signature: s.sig,
    })
  })

  app.post("/world/attest", async (c) => {
    if (d.worldMode !== "attested" || !d.attest) throw new HttpError(501, "attested voting is disabled")
    const input = await body(c, AttestInput)
    return c.json(await d.attest(input))
  })

  app.post("/faucet", async (c) => {
    const { address: to } = await body(c, z.object({ address }))
    const ip = (c.req.header("x-forwarded-for") ?? "unknown").split(",")[0]!.trim()
    const now = d.now()
    if (await d.faucet.isContract(to)) throw new HttpError(400, "contracts cannot be funded")
    const decision = d.faucet.check(to, ip, now)
    if (!decision.ok) {
      throw new HttpError(decision.reason === "already-funded" ? 409 : 429, decision.reason)
    }
    const tx = await d.faucet.send(to)
    d.faucet.record(to, ip, now)
    return c.json(tx)
  })

  return app
}
