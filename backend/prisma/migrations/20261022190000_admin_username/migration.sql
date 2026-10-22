ALTER TABLE "User" ADD COLUMN "username" VARCHAR(64) NOT NULL DEFAULT gen_random_uuid()::text;
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");
ALTER TABLE "User" ADD CONSTRAINT "User_username_format_check"
  CHECK ("username" ~ '^[a-z0-9][a-z0-9_.-]{2,63}$');
