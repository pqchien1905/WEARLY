CREATE TABLE "StylePreference" (
  "userId" UUID NOT NULL,
  "size" TEXT NOT NULL,
  "style" TEXT NOT NULL,
  "color" TEXT NOT NULL,
  "budget" DECIMAL(14,0) NOT NULL,
  "version" INTEGER NOT NULL DEFAULT 1,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "StylePreference_pkey" PRIMARY KEY ("userId"),
  CONSTRAINT "StylePreference_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
