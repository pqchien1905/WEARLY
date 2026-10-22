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
async function snapshot(client) {
  const tables = {};
  const names = (
    await client.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name COLLATE \"C\"",
    )
  ).rows;
  for (const { table_name: name } of names) {
    const hash = createHash("sha256");
    let count = 0;
    await client.query(
      `DECLARE recovery_rows NO SCROLL CURSOR FOR SELECT to_jsonb(t)::text AS value FROM public.${identifier(name)} t ORDER BY to_jsonb(t)::text COLLATE "C"`,
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
module.exports = { runNative, snapshot };
