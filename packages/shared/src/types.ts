import { z } from "zod"

const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/).transform((a) => a as `0x${string}`)
const powerId = z.union([z.literal(0), z.literal(1), z.literal(2)])

export const OutcomeSchema = z.enum(["undecided", "rebels-win", "tyrant-wins", "emancipated"])
export type OutcomeName = z.infer<typeof OutcomeSchema>

/** One of the Tyrant's three powers, read live from ENSv2 (never from a stored flag). */
export const PowerStateSchema = z.object({
  power: powerId,
  /** BANISH, DECREE or DISSOLVE. */
  name: z.string(),
  /** The ENSv2 role that embodies it, e.g. ROLE_UNREGISTER. */
  ensRole: z.string(),
  /** True while the Throne still holds the root role. False is permanent. */
  alive: z.boolean(),
  /** Seconds until the Tyrant may use it again. */
  cooldownRemaining: z.number().int().nonnegative(),
})
export type PowerState = z.infer<typeof PowerStateSchema>

export const VassalViewSchema = z.object({
  address,
  label: z.string(),
  /** Full ENS name, e.g. alice.s1.fealty.eth. */
  name: z.string(),
  /** Banner read through ENS resolution. A decreed vassal shows the Tyrant's proclamation here. */
  banner: z.string(),
  joinedAt: z.number().int(),
  banished: z.boolean(),
  decreed: z.boolean(),
  /** Joined, not banished, and the ENS name still resolves to them. */
  live: z.boolean(),
  /** An NPC seeded for the demo. NPCs can pledge but cannot vote (no World ID). */
  npc: z.boolean(),
  /** Sub-court attached to the name, or null. */
  house: address.nullable(),
})
export type VassalView = z.infer<typeof VassalViewSchema>

export const BallotViewSchema = z.object({
  id: z.number().int().positive(),
  power: powerId,
  /** Arkiv entity key of the manifesto whose quorum opened this ballot. */
  manifestoKey: z.string(),
  pledges: z.number().int().nonnegative(),
  openedAt: z.number().int(),
  deadline: z.number().int(),
  electorate: z.number().int().nonnegative(),
  yes: z.number().int().nonnegative(),
  no: z.number().int().nonnegative(),
  resolved: z.boolean(),
  passed: z.boolean(),
})
export type BallotView = z.infer<typeof BallotViewSchema>

export const ManifestoViewSchema = z.object({
  entityKey: z.string(),
  author: address,
  authorName: z.string(),
  title: z.string(),
  text: z.string(),
  power: powerId,
  /** Unix seconds at which Arkiv will drop the entity. No event fires at that moment. */
  expiresAt: z.number().int(),
  /** Distinct valid pledgers. */
  pledgeCount: z.number().int().nonnegative(),
  pledgers: z.array(address),
  /** pledgeCount / quorum, capped at 1. */
  momentum: z.number().min(0).max(1),
})
export type ManifestoView = z.infer<typeof ManifestoViewSchema>

export const ChronicleViewSchema = z.object({
  entityKey: z.string(),
  kind: z.string(),
  actor: address,
  target: address.nullable(),
  power: powerId.nullable(),
  ballot: z.number().int().nullable(),
  txHash: z.string().nullable(),
  text: z.string().nullable(),
  /** Unix seconds the entry was written. */
  at: z.number().int(),
})
export type ChronicleView = z.infer<typeof ChronicleViewSchema>

/** Everything the UI needs to draw the realm. Served by `GET /realm` and pushed over `GET /stream`. */
export const RealmSnapshotSchema = z.object({
  season: z.string(),
  courtName: z.string(),
  chainId: z.number().int(),
  outcome: OutcomeSchema,
  finalized: z.boolean(),
  seasonStart: z.number().int(),
  seasonEnd: z.number().int(),
  /** Server clock in unix seconds when this snapshot was built. */
  now: z.number().int(),
  powers: z.tuple([PowerStateSchema, PowerStateSchema, PowerStateSchema]),
  vassals: z.array(VassalViewSchema),
  activeBallot: BallotViewSchema.nullable(),
  manifestos: z.array(ManifestoViewSchema),
  /** Newest first, at most 50. */
  chronicle: z.array(ChronicleViewSchema),
  config: z.object({
    quorum: z.number().int().positive(),
    minYesVotes: z.number().int().positive(),
    ballotDuration: z.number().int().positive(),
    powerCooldown: z.number().int().nonnegative(),
    worldMode: z.enum(["onchain", "attested"]),
    tyrant: address,
    keeper: address,
    throne: address,
    court: address,
  }),
  /** Sepolia block the on-chain parts were read at. */
  updatedAtBlock: z.number().int().nonnegative(),
})
export type RealmSnapshot = z.infer<typeof RealmSnapshotSchema>
