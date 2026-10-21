import { Prisma } from '../generated/prisma/client';
import * as enums from '../generated/prisma/enums';
import { DATABASE_SCHEMA } from './prisma.service';
import { Client } from 'pg';

type Reader = Pick<Client, 'query'>;

/** Current schema uses unmapped model/field names; generated enums track additions.
 * This is a runtime compatibility probe, not a substitute for migration validation.
 */
export async function databaseSchemaReady(db: Reader): Promise<boolean> {
  // A single statement gives the caller one server-side execution deadline.
  // search_path can differ from the schema explicitly targeted by Prisma.
  const { rows } = await db.query<{ kind: string; name: string; value: string }>(`
    SELECT 'column' AS kind, table_name AS name, column_name AS value
    FROM information_schema.columns WHERE table_schema = $1
    UNION ALL
    SELECT 'enum' AS kind, t.typname AS name, e.enumlabel AS value
    FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = $1`, [DATABASE_SCHEMA]);
  const present = new Set(rows.filter((row) => row.kind === 'column').map((row) => `${row.name}.${row.value}`));
  const generated = Prisma as unknown as Record<string, Record<string, string>>;
  for (const model of Object.values(Prisma.ModelName)) {
    const fields = generated[`${model}ScalarFieldEnum`];
    if (!fields || Object.values(fields).some((field) => !present.has(`${model}.${field}`))) {
      return false;
    }
  }
  const actual = new Set(rows.filter((row) => row.kind === 'enum').map((row) => `${row.name}.${row.value}`));
  return Object.entries(enums).every(([name, entries]) =>
    Object.values(entries).every((value) => actual.has(`${name}.${value}`)),
  );
}
