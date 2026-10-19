CREATE TABLE "AddressCreateReceipt" (
    "userId" UUID NOT NULL,
    "key" VARCHAR(128) NOT NULL,
    "requestHash" VARCHAR(64) NOT NULL,
    "addressId" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AddressCreateReceipt_pkey" PRIMARY KEY ("userId", "key")
);
CREATE UNIQUE INDEX "AddressCreateReceipt_addressId_key" ON "AddressCreateReceipt"("addressId");
ALTER TABLE "AddressCreateReceipt" ADD CONSTRAINT "AddressCreateReceipt_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AddressCreateReceipt" ADD CONSTRAINT "AddressCreateReceipt_addressId_fkey" FOREIGN KEY ("addressId") REFERENCES "Address"("id") ON DELETE SET NULL ON UPDATE CASCADE;
