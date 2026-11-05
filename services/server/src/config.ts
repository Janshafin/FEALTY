import { z } from "zod"

const hexKey = z.string().regex(/^0x[0-9a-fA-F]{64}$/, "expected a 0x-prefixed 32-byte private key")
const num = (def: number) => z.coerce.number().default(def)
const bool = (def: boolean) =>
  z
    .enum(["true", "false"])
    .default(def ? "true" : "false")
    .transform((v) => v === "true")

const schema = z.object({
  SEPOLIA_RPC_URL: z.string().url(),
  KEEPER_PK: hexKey,
  TYRANT_PK: hexKey,
  FAUCET_PK: hexKey,
  ATTESTER_PK: hexKey.optional(),
  SEASON: z.string().min(1),
  WORLD_MODE: z.enum(["onchain", "attested"]).default("onchain"),
  WORLD_APP_ID: z.string().min(1),
  WORLD_RP_ID: z.string().min(1),
  WORLD_RP_SIGNING_KEY: z.string().min(1),
  WORLD_ACTION: z.string().default("fealty-vote"),
  WORLD_ENV: z.enum(["staging", "production"]).default("staging"),
  ARKIV_ACCESS_KEY: z.string().default(""),
  ARKIV_RPC_URL: z.string().url().default("https://rpc.rabdi.db-chain.testnet.arkiv.network"),
  QUORUM_PLEDGES: num(3),
  MANIFESTO_TTL_S: num(180),
  KEEPER_INTERVAL_MS: num(4000),
  TYRANT_ENABLED: bool(true),
  TYRANT_REACTION_MS: num(8000),
  TYRANT_PANIC: num(0.6),
  TYRANT_WORRY: num(0.3),
  TYRANT_IDLE_TAUNT: num(0.2),
  FAUCET_SEPOLIA_WEI: z.string().regex(/^\d+$/).default("3000000000000000"),
  FAUCET_TGLM_WEI: z.string().regex(/^\d+$/).default("500000000000000000"),
  FAUCET_PER_IP_PER_DAY: num(3),
  FAUCET_GLOBAL_PER_DAY: num(200),
  FRONTEND_ORIGIN: z.string().default("http://localhost:5173"),
  PORT: num(8787),
  DATA_DIR: z.string().default("services/server/data"),
})

export type ServerConfig = z.infer<typeof schema>

/**
 * Reads and validates the environment. Fails fast with every problem listed at once, instead of
 * crashing later on the first missing value. Secrets are never echoed in the error.
 */
export function loadConfig(env: Record<string, string | undefined> = process.env): ServerConfig {
  const parsed = schema.safeParse(env)
  if (!parsed.success) {
    const lines = parsed.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`)
    throw new Error(`Invalid server configuration:\n${lines.join("\n")}\nSee .env.example.`)
  }
  const cfg = parsed.data
  if (cfg.WORLD_MODE === "attested" && !cfg.ATTESTER_PK) {
    throw new Error("Invalid server configuration:\n  ATTESTER_PK: required when WORLD_MODE=attested")
  }
  if (cfg.MANIFESTO_TTL_S % 2 !== 0) {
    throw new Error("Invalid server configuration:\n  MANIFESTO_TTL_S: must be even (Arkiv blocks are 2 seconds)")
  }
  return cfg
}
