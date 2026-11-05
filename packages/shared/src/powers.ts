/** The three powers of the Tyrant. Values equal the Solidity `Power` enum. */
export enum Power {
  Banish = 0,
  Decree = 1,
  Dissolve = 2,
}

export const POWERS = [Power.Banish, Power.Decree, Power.Dissolve] as const

export const POWER_NAMES: Record<Power, string> = {
  [Power.Banish]: "BANISH",
  [Power.Decree]: "DECREE",
  [Power.Dissolve]: "DISSOLVE",
}

/** What each power really is in ENSv2. */
export const POWER_ENS_ROLE_NAMES: Record<Power, string> = {
  [Power.Banish]: "ROLE_UNREGISTER",
  [Power.Decree]: "ROLE_SET_RESOLVER",
  [Power.Dissolve]: "ROLE_SET_SUBREGISTRY",
}

/**
 * ENSv2 root role bit of each power (RegistryRolesLib). Pinned against Solidity by
 * `contracts/test/Constants.t.sol`, so a change upstream fails a test instead of silently diverging.
 */
export const POWER_ROLE: Record<Power, bigint> = {
  [Power.Banish]: 1n << 12n,
  [Power.Decree]: 1n << 24n,
  [Power.Dissolve]: 1n << 20n,
}

/** The admin bit sits 128 bits above the role. Holding it is what makes revocation irreversible. */
export const ADMIN_SHIFT = 128n

export function powerRole(p: Power): bigint {
  return POWER_ROLE[p]
}

/** Role plus its admin counterpart: exactly the bitmap the Throne revokes when a power is stripped. */
export function powerRoleWithAdmin(p: Power): bigint {
  return POWER_ROLE[p] | (POWER_ROLE[p] << ADMIN_SHIFT)
}

export function isPower(n: number): n is Power {
  return n === 0 || n === 1 || n === 2
}
