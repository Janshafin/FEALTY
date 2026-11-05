import { keccak256, stringToBytes, type Address, type Hex } from "viem"

/**
 * The signal a World ID proof must commit to. It must match `VoteSignal.encode` in Solidity exactly:
 * lowercase hex address, ballot id and choice joined by colons.
 */
export function buildVoteSignal(voter: Address, ballotId: bigint, support: boolean): string {
  return `${voter.toLowerCase()}:${ballotId.toString()}:${support ? "1" : "0"}`
}

/** World ID `hashToField`: keccak256 shifted right by 8 bits so it fits the snark field. */
export function hashToField(input: string | Uint8Array): bigint {
  const bytes = typeof input === "string" ? stringToBytes(input) : input
  return BigInt(keccak256(bytes)) >> 8n
}

export function computeSignalHash(voter: Address, ballotId: bigint, support: boolean): bigint {
  return hashToField(buildVoteSignal(voter, ballotId, support))
}

/** EIP-712 domain and types of an attested vote (Mode B). Must match `Throne.ATTEST_TYPEHASH`. */
export const ATTEST_TYPES = {
  Attest: [
    { name: "voter", type: "address" },
    { name: "ballotId", type: "uint256" },
    { name: "support", type: "bool" },
    { name: "nullifierHash", type: "uint256" },
    { name: "expiry", type: "uint256" },
  ],
} as const

export function attestDomain(chainId: number, throne: Address) {
  return { name: "FealtyThrone", version: "1", chainId, verifyingContract: throne } as const
}

export interface AttestMessage {
  voter: Address
  ballotId: bigint
  support: boolean
  nullifierHash: bigint
  expiry: bigint
}

/** Everything `signTypedData` needs to produce the attester signature `Throne.voteAttested` expects. */
export function attestTypedData(chainId: number, throne: Address, message: AttestMessage) {
  return {
    domain: attestDomain(chainId, throne),
    types: ATTEST_TYPES,
    primaryType: "Attest",
    message,
  } as const
}

export type { Hex }
