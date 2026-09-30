BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "sos_alert" (
    "id" bigserial PRIMARY KEY,
    "userId" bigint NOT NULL,
    "userInfoId" bigint NOT NULL,
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    "message" text,
    "isActive" boolean NOT NULL
);

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "sos_alert"
    ADD CONSTRAINT "sos_alert_fk_0"
    FOREIGN KEY("userInfoId")
    REFERENCES "serverpod_user_info"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR crsis_link
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('crsis_link', '20260930095631115', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260930095631115', "timestamp" = now();

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
