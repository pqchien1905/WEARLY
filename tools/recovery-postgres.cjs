const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const execute = promisify(execFile);
const { createHash } = require("node:crypto");
async function runNative(binary, args, options = {}) {
  try {
    return (
      await execute(binary, args, {
        ...options,
        windowsHide: true,
        timeout: 120000,
        maxBuffer: 1024 * 1024,
        encoding: "utf8",
      })
    ).stdout;
  } catch {
    throw Error("RECOVERY_NATIVE_COMMAND_FAILED");
  }
}
const identifier = (value) => '"' + value.replaceAll('"', '""') + '"';
function environment(connection, input = process.env) {
  const result = { ...input };
  for (const key of Object.keys(result))
    if (key.toUpperCase().startsWith("PG")) delete result[key];
  return {
    ...result,
    PGPASSWORD: connection.password,
    PGOPTIONS: "-c timezone=UTC",
    PGCONNECT_TIMEOUT: "5",
  };
}
async function snapshot(client, expressions = {}) {
  const tables = {};
  const names = (
    await client.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name COLLATE \"C\"",
    )
  ).rows;
  for (const { table_name: name } of names) {
    const hash = createHash("sha256");
    let count = 0;
    const expression = expressions[name] ?? "to_jsonb(t)";
    await client.query(
      `DECLARE recovery_rows NO SCROLL CURSOR FOR SELECT (${expression})::text AS value FROM public.${identifier(name)} t ORDER BY (${expression})::text COLLATE "C"`,
    );
    try {
      for (;;) {
        const { rows } = await client.query(
          "FETCH FORWARD 500 FROM recovery_rows",
        );
        if (!rows.length) break;
        for (const row of rows) {
          hash.update(row.value).update("\n");
          count++;
        }
      }
    } finally {
      await client.query("CLOSE recovery_rows");
    }
    tables[name] = { count, sha256: hash.digest("hex") };
  }
  const queries = {
    columns:
      "SELECT table_name,column_name,ordinal_position,data_type,udt_name,is_nullable,column_default,numeric_precision,numeric_scale,character_maximum_length FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,column_name",
    enums:
      "SELECT t.typname,e.enumlabel,e.enumsortorder FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' ORDER BY t.typname,e.enumsortorder",
    constraints:
      "SELECT c.relname AS table_name,co.conname,pg_get_constraintdef(co.oid,true) AS definition FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY c.relname,co.conname",
    indexes:
      "SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename,indexname",
    triggers:
      "SELECT c.relname AS table_name,t.tgname,pg_get_triggerdef(t.oid,true) AS definition FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal ORDER BY c.relname,t.tgname",
    functions:
      "SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS arguments,pg_get_functiondef(p.oid) AS definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN ('f','p') ORDER BY p.proname,arguments",
    views:
      "SELECT viewname,definition FROM pg_views WHERE schemaname='public' ORDER BY viewname",
    sequences:
      "SELECT sequencename,data_type,start_value,min_value,max_value,increment_by,cycle,cache_size FROM pg_sequences WHERE schemaname='public' ORDER BY sequencename",
  };
  const schema = {};
  for (const [key, sql] of Object.entries(queries))
    schema[key] = (await client.query(sql)).rows;
  return { tables, schema };
}
async function quarantine(client, target) {
  const current = (await client.query("SELECT current_database() AS database"))
    .rows[0].database;
  if (
    current !== target ||
    !/^wearly_recovery_[0-9]{13}_[a-f0-9]{8}$/.test(target)
  )
    throw Error("RECOVERY_TARGET_REQUIRED");
  // Prisma stores TIMESTAMP(3); expected JSON must use the same rounded precision.
  const time = "((now() AT TIME ZONE 'UTC')::timestamp(3))",
    active = "status IN ('PENDING','PROCESSING')",
    usage = "status IN ('RESERVED','PROCESSING')";
  const transforms = {
    User: { active: "false" },
    RefreshToken: { revokedAt: `COALESCE("revokedAt",${time})` },
    PasswordResetToken: { consumedAt: `COALESCE("consumedAt",${time})` },
    ImageAsset: {
      deletedAt: `COALESCE("deletedAt",${time})`,
      purgedAt: `COALESCE("purgedAt",${time})`,
      expiresAt: `LEAST("expiresAt",${time})`,
    },
    TryOnResult: { expiresAt: `LEAST("expiresAt",${time})` },
    AIJob: {
      status: `CASE WHEN ${active} THEN 'FAILED' ELSE status END`,
      errorCode: `CASE WHEN ${active} THEN 'LOCAL_RECOVERY_REVIEW' ELSE "errorCode" END`,
    },
    AiUsage: {
      status: `CASE WHEN ${usage} THEN 'UNKNOWN' ELSE status END`,
      errorCode: `CASE WHEN ${usage} THEN 'LOCAL_RECOVERY_REVIEW' ELSE "errorCode" END`,
      finishedAt: `CASE WHEN ${usage} THEN ${time} ELSE "finishedAt" END`,
    },
    OutboxEvent: { publishedAt: `COALESCE("publishedAt",${time})` },
    MailOutbox: {
      status: `CASE WHEN ${active} THEN 'FAILED' ELSE status END`,
      lastError: `CASE WHEN ${active} THEN 'LOCAL_RECOVERY_REVIEW' ELSE "lastError" END`,
      leaseToken: `CASE WHEN ${active} THEN NULL ELSE "leaseToken" END`,
      leaseUntil: `CASE WHEN ${active} THEN NULL ELSE "leaseUntil" END`,
    },
  };
  const expressions = {};
  for (const [table, columns] of Object.entries(transforms))
    expressions[table] =
      "to_jsonb(t)||jsonb_build_object(" +
      Object.entries(columns)
        .map(([key, value]) => `'${key}',${value}`)
        .join(",") +
      ")";
  await client.query("BEGIN");
  try {
    const expected = await snapshot(client, expressions),
      counts = {};
    for (const [table, columns] of Object.entries(transforms))
      counts[table] = (
        await client.query(
          `UPDATE public.${identifier(table)} SET ${Object.entries(columns)
            .map(([key, value]) => `${identifier(key)}=${value}`)
            .join(",")}`,
        )
      ).rowCount;
    const actual = await snapshot(client);
    if (JSON.stringify(actual) !== JSON.stringify(expected))
      throw Error("RECOVERY_QUARANTINE_MISMATCH");
    await client.query("COMMIT");
    return { tablesChecked: counts, snapshot: actual };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  }
}
function validateSnapshot(value) {
  const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
  const invalid = () => { throw Error("RECOVERY_INVALID_MANIFEST"); };
  const string = (v) => typeof v === "string" && v.length <= 100000;
  const integer = (v) => Number.isSafeInteger(v);
  const nullable = (check) => (v) => v === null || check(v);
  const int64 = (v) => integer(v) || (typeof v === "string" && /^-?\d{1,20}$/.test(v));
  if (!object(value) || !object(value.tables) || !Object.keys(value.tables).length || !object(value.schema)) invalid();
  for (const [name, row] of Object.entries(value.tables)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name) || !object(row) ||
      !integer(row.count) || row.count < 0 || !/^[a-f0-9]{64}$/.test(row.sha256)) invalid();
  }
  const fields = {
    columns: {table_name:string,column_name:string,ordinal_position:integer,data_type:string,udt_name:string,is_nullable:(v)=>v==='YES'||v==='NO',column_default:nullable(string),numeric_precision:nullable(integer),numeric_scale:nullable(integer),character_maximum_length:nullable(integer)},
    enums: {typname:string,enumlabel:string,enumsortorder:Number.isFinite},
    constraints: {table_name:string,conname:string,definition:string},
    indexes: {tablename:string,indexname:string,indexdef:string},
    triggers: {table_name:string,tgname:string,definition:string},
    functions: {proname:string,arguments:string,definition:string},
    views: {viewname:string,definition:string},
    sequences: {sequencename:string,data_type:string,start_value:int64,min_value:int64,max_value:int64,increment_by:int64,cycle:(v)=>typeof v==='boolean',cache_size:int64},
  };
  if (Object.keys(value.schema).length !== Object.keys(fields).length) invalid();
  for (const [section, validators] of Object.entries(fields)) {
    const rows = value.schema[section];
    if (!Array.isArray(rows) || rows.length > 100000) invalid();
    for (const row of rows) {
      if (!object(row) || Object.keys(row).length !== Object.keys(validators).length ||
        Object.entries(validators).some(([key, check]) => !check(row[key]))) invalid();
    }
  }
  return value;
}
function canonicalConstraint(definition) {
  // pg_dump/parse moves varchar[] -> text[] coercion onto each literal element.
  // Keep all other casts, literals and operators intact.
  return definition.replace(
    /ARRAY\[((?:'(?:[^']|'')*'::character varying)(?:, '(?:[^']|'')*'::character varying)*)\]::text\[\]/g,
    (_match, items) =>
      "ARRAY[" +
      items.replace(
        /('(?:[^']|'')*')::character varying/g,
        "$1::character varying::text",
      ) +
      "]",
  );
}
function canonicalSnapshot(value) {
  return {
    ...value,
    schema: {
      ...value.schema,
      constraints: value.schema.constraints.map((row) => ({
        ...row,
        definition: canonicalConstraint(row.definition),
      })),
    },
  };
}
module.exports = {
  validateSnapshot,
  environment,
  runNative,
  snapshot,
  quarantine,
  canonicalConstraint,
  canonicalSnapshot,
};
