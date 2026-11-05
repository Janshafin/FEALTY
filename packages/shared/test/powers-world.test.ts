import { keccak256, toBytes } from "viem"
import { privateKeyToAccount } from "viem/accounts"
import { recoverTypedDataAddress } from "viem"
import { describe, expect, it } from "vitest"
import {
  ADMIN_SHIFT,
  ATTEST_TYPES,
  POWER_ROLE,
  Power,
  attestTypedData,
  buildVoteSignal,
  computeSignalHash,
  hashToField,
  powerRoleWithAdmin,
} from "../src/index.js"

describe("powers", () => {
  it("role bits equal RegistryRolesLib (pinned by contracts/test/Constants.t.sol)", () => {
    expect(POWER_ROLE[Power.Banish]).toBe(1n << 12n) // ROLE_UNREGISTER
    expect(POWER_ROLE[Power.Decree]).toBe(1n << 24n) // ROLE_SET_RESOLVER
    expect(POWER_ROLE[Power.Dissolve]).toBe(1n << 20n) // ROLE_SET_SUBREGISTRY
  })

  it("strip bitmap is role plus its admin bit", () => {
    expect(powerRoleWithAdmin(Power.Banish)).toBe((1n << 12n) | (1n << (12n + ADMIN_SHIFT)))
  })
})

describe("world signal", () => {
  const voter = "0xAbcd000000000000000000000000000000001234" as const

  it("builds the exact string Solidity builds", () => {
    expect(buildVoteSignal(voter, 7n, true)).toBe("0xabcd000000000000000000000000000000001234:7:1")
    expect(buildVoteSignal("0x0000000000000000000000000000000000000001", 12n, false)).toBe(
      "0x0000000000000000000000000000000000000001:12:0",
    )
  })

  it("hashes to the same field element as Solidity (vector from contracts/test/Constants.t.sol)", () => {
    expect(computeSignalHash(voter, 7n, true)).toBe(0xe24372edb0efef4755ce4127da8b81d1485db66fabfbc5a510ed512d6f8ffan)
  })

  it("hashToField stays below the snark field and shifts out the low byte", () => {
    const h = hashToField("anything")
    expect(h < 1n << 248n).toBe(true)
    expect(h).toBe(BigInt(keccak256(toBytes("anything"))) >> 8n)
  })

  it("choice and ballot change the hash", () => {
    const a = computeSignalHash(voter, 7n, true)
    expect(computeSignalHash(voter, 7n, false)).not.toBe(a)
    expect(computeSignalHash(voter, 8n, true)).not.toBe(a)
  })
})

describe("attestation typed data", () => {
  it("type string equals Throne.ATTEST_TYPEHASH preimage", () => {
    const s = `Attest(${ATTEST_TYPES.Attest.map((f) => `${f.type} ${f.name}`).join(",")})`
    expect(s).toBe("Attest(address voter,uint256 ballotId,bool support,uint256 nullifierHash,uint256 expiry)")
  })

  it("signature recovers to the attester", async () => {
    const account = privateKeyToAccount(("0x" + "a7".repeat(32)) as `0x${string}`)
    const td = attestTypedData(11155111, "0x00000000000000000000000000000000000000aa", {
      voter: "0x00000000000000000000000000000000000000bb",
      ballotId: 1n,
      support: true,
      nullifierHash: 42n,
      expiry: 999n,
    })
    const signature = await account.signTypedData(td)
    const recovered = await recoverTypedDataAddress({ ...td, signature })
    expect(recovered).toBe(account.address)
  })
})
