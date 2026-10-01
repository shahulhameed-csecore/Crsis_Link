BEGIN;

--
-- ACTION DROP TABLE
--
DROP TABLE "sos_alert" CASCADE;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "sos_alert" (
    "id" bigserial PRIMARY KEY,
    "deviceId" text NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    "message" text,
    "isActive" boolean NOT NULL,
    "status" text NOT NULL,
    "senderName" text NOT NULL,
    "volunteerDeviceId" text
);


--
-- MIGRATION VERSION FOR crsis_link
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('crsis_link', '20261001071614201', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261001071614201', "timestamp" = now();

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
