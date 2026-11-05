import { hashSignal } from "@worldcoin/idkit-core/hashing"
import { describe, expect, it } from "vitest"
import { buildVoteSignal, computeSignalHash, hashToField } from "../src/index.js"

/**
 * Our `hashToField` must equal World's own `hashSignal`, otherwise a proof made by IDKit for our
 * signal would never match the hash `Throne.vote` recomputes on-chain.
 */
describe("parity with @worldcoin/idkit-core", () => {
  const voter = "0xAbcd000000000000000000000000000000001234" as const

  it("hashes our vote signal to the same field element as IDKit", () => {
    const signal = buildVoteSignal(voter, 7n, true)
    expect(BigInt(hashSignal(signal))).toBe(computeSignalHash(voter, 7n, true))
  })

  it("agrees on assorted inputs", () => {
    for (const s of ["", "a", "fealty", "0x00:1:0", "ünïcödé"]) {
      expect(BigInt(hashSignal(s)), s).toBe(hashToField(s))
    }
  })
})
