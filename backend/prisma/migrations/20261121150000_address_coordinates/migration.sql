-- Optional delivery pin chosen on a map. Both or neither, within valid ranges.
ALTER TABLE "Address" ADD COLUMN "latitude" DOUBLE PRECISION;
ALTER TABLE "Address" ADD COLUMN "longitude" DOUBLE PRECISION;
ALTER TABLE "Address" ADD CONSTRAINT "Address_coordinates_check" CHECK (
  ("latitude" IS NULL AND "longitude" IS NULL)
  OR ("latitude" BETWEEN -90 AND 90 AND "longitude" BETWEEN -180 AND 180)
);
