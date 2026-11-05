import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { z } from "zod"

const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/, "expected a 20-byte hex address").transform((a) => a as `0x${string}`)
const uintString = z.string().regex(/^\d+$/, "expected a decimal integer string")

/**
 * What `DeploySeason.s.sol` writes to `deployments/<chainId>/<season>.json`. Large integers are
 * decimal strings so they survive JSON.
 */
export const DeploymentSchema = z.object({
  chainId: z.number().int().positive(),
  season: z.string().min(1),
  realmLabel: z.string().min(1),
  deployBlock: z.number().int().nonnegative(),
  addresses: z.object({
    labelStore: address,
    factory: address,
    resolverImpl: address,
    realm: address,
    court: address,
    throne: address,
    bannerResolver: address,
    decreeResolver: address,
    worldId: address,
    ethRegistry: address,
    universalResolver: address,
  }),
  config: z.object({
    tyrant: address,
    keeper: address,
    attester: address,
    worldMode: z.enum(["onchain", "attested"]),
    externalNullifierHash: uintString,
    seasonStart: z.number().int().nonnegative(),
    seasonEnd: z.number().int().positive(),
    powerCooldown: z.number().int().nonnegative(),
    ballotDuration: z.number().int().positive(),
    concedeImmunity: z.number().int().nonnegative(),
    minYesVotes: z.number().int().positive(),
  }),
  throneAbiHash: z.string(),
})
export type Deployment = z.infer<typeof DeploymentSchema>

/** Repo root: this file is `packages/shared/src/deployments.ts`. */
const REPO_ROOT = resolve(import.meta.dirname, "../../..")

export function deploymentPath(chainId: number, season: string, root = REPO_ROOT): string {
  return resolve(root, "deployments", String(chainId), `${season}.json`)
}

/** Loads and validates a season deployment. Throws a readable error if the file is missing or malformed. */
export function loadDeployment(chainId: number, season: string, root = REPO_ROOT): Deployment {
  const path = deploymentPath(chainId, season, root)
  let raw: string
  try {
    raw = readFileSync(path, "utf8")
  } catch {
    throw new Error(`No deployment file at ${path}. Run the DeploySeason script first (docs/backend/DEPLOY.md).`)
  }
  const parsed = DeploymentSchema.safeParse(JSON.parse(raw))
  if (!parsed.success) {
    throw new Error(`Invalid deployment file ${path}: ${parsed.error.message}`)
  }
  return parsed.data
}
