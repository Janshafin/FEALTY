import { addr, defineSchema, i32, key, str } from "@arkiv-network/sdk/schema"

/** Versioned schema names. Every entity is tagged with its name by the SDK. */
export const SCHEMA_NAMES = {
  manifesto: "fealty.v1.manifesto",
  pledge: "fealty.v1.pledge",
  chronicle: "fealty.v1.chronicle",
} as const

/**
 * A rebel's call to strip one power. Owned (signed) by the rebel, so only they can delete it.
 * It expires on its own after the campaign window: no cleanup job exists.
 */
export const ManifestoSchema = defineSchema(SCHEMA_NAMES.manifesto, {
  season: str().indexed(),
  court: addr().indexed(),
  power: i32().indexed(),
  author: addr().indexed(),
  title: str(),
  text: str(),
  authorName: str(),
})

/**
 * A vassal's backing of a manifesto. Owned by the pledger and expiring with the manifesto, so
 * momentum decays by itself. Validity is decided by `countValidPledges`, never by the writer.
 */
export const PledgeSchema = defineSchema(SCHEMA_NAMES.pledge, {
  season: str().indexed(),
  manifesto: key().indexed(),
  power: i32().indexed(),
  pledger: addr().indexed(),
})

/**
 * The realm's public record, mirrored from Throne events by the keeper. Readers must filter by the
 * keeper as owner, otherwise anyone could forge history.
 */
export const ChronicleSchema = defineSchema(SCHEMA_NAMES.chronicle, {
  season: str().indexed(),
  kind: str().indexed(),
  actor: addr().indexed(),
  target: addr().optional(),
  power: i32().optional(),
  ballot: i32().optional(),
  txHash: str().optional(),
  text: str().optional(),
})

/** Known chronicle entry kinds. */
export const CHRONICLE_KINDS = [
  "joined",
  "banner",
  "banished",
  "decreed",
  "dissolved",
  "ballot-opened",
  "voted",
  "vote-removed",
  "ballot-resolved",
  "ballot-cancelled",
  "power-stripped",
  "conceded",
  "outcome",
  "taunt",
] as const
export type ChronicleKind = (typeof CHRONICLE_KINDS)[number]
