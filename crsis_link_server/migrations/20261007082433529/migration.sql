BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "sos_alert" DROP COLUMN "photoBase64";
ALTER TABLE "sos_alert" ADD COLUMN "photoUrl" text;
CREATE INDEX "sos_active_status_idx" ON "sos_alert" USING btree ("isActive", "status");
CREATE INDEX "sos_device_idx" ON "sos_alert" USING btree ("deviceId");
CREATE INDEX "sos_geo_idx" ON "sos_alert" USING btree ("latitude", "longitude");

--
-- MIGRATION VERSION FOR crsis_link
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('crsis_link', '20261007082433529', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261007082433529', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod_auth_idp
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod_auth_idp', '20260213194423028', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260213194423028', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod_auth
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod_auth', '20260129181059877', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129181059877', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod_auth_core
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod_auth_core', '20260129181112269', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129181112269', "timestamp" = now();


COMMIT;
