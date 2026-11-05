import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"

export type FaucetDecision = { ok: true } | { ok: false; reason: "already-funded" | "ip-limit" | "daily-cap" }

interface State {
  addresses: string[]
  /** Unix day number -> drips counted. */
  perDay: Record<string, number>
  perIp: Record<string, number>
}

const DAY = 86_400

/**
 * Keeps the faucet from being drained: one drip per address ever, a per-IP daily limit and a global
 * daily cap. State is persisted so a restart does not reset the limits.
 */
export class FaucetLimiter {
  private state: State
  constructor(
    private readonly path: string,
    private readonly opts: { perIpPerDay: number; globalPerDay: number },
  ) {
    try {
      this.state = JSON.parse(readFileSync(path, "utf8")) as State
    } catch {
      this.state = { addresses: [], perDay: {}, perIp: {} }
    }
  }

  check(address: string, ip: string, nowSeconds: number): FaucetDecision {
    const day = Math.floor(nowSeconds / DAY)
    if (this.state.addresses.includes(address.toLowerCase())) return { ok: false, reason: "already-funded" }
    if ((this.state.perIp[`${day}:${ip}`] ?? 0) >= this.opts.perIpPerDay) return { ok: false, reason: "ip-limit" }
    if ((this.state.perDay[String(day)] ?? 0) >= this.opts.globalPerDay) return { ok: false, reason: "daily-cap" }
    return { ok: true }
  }

  /** Records a drip that was actually sent. */
  record(address: string, ip: string, nowSeconds: number): void {
    const day = Math.floor(nowSeconds / DAY)
    this.state.addresses.push(address.toLowerCase())
    this.state.perDay[String(day)] = (this.state.perDay[String(day)] ?? 0) + 1
    this.state.perIp[`${day}:${ip}`] = (this.state.perIp[`${day}:${ip}`] ?? 0) + 1
    // forget old days so the file stays small
    for (const k of Object.keys(this.state.perDay)) if (Number(k) < day - 2) delete this.state.perDay[k]
    for (const k of Object.keys(this.state.perIp)) if (Number(k.split(":")[0]) < day - 2) delete this.state.perIp[k]
    mkdirSync(dirname(this.path), { recursive: true })
    writeFileSync(this.path, JSON.stringify(this.state))
  }
}
