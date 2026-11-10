/** A published flag alone cannot outlive the grant authorising character identity. */
export const PUBLIC_PROFILE_ACCESS_SQL=`SELECT 1 AS allowed FROM atlas_observations o
 JOIN atlas_grants g ON g.id=o.grant_id AND g.user_id=o.user_id AND g.producer_id=o.producer_id
 WHERE o.profile_id=? AND g.revoked_at IS NULL
 AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value='own_character')
 AND EXISTS(SELECT 1 FROM json_each(g.scopes) WHERE value=o.scope) LIMIT 1`;
