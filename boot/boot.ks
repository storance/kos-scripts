function compileDirectory {
    DECLARE PARAMETER path.

    FOR file IN path:LIST:VALUES {
        IF (NOT file:ISFILE) AND (file:NAME <> "boot") AND NOT (file:NAME:STARTSWITH(".")) {
            LOCAL subDirPath TO PATH(path):COMBINE(file:NAME).
            LOCAL destDir TO changeVolume(CORE:VOLUME, subDirPath).

            IF NOT EXISTS(destDir) {
                CREATEDIR(destDir).
            }

            compileDirectory(OPEN(subDirPath)).
        }

        IF file:ISFILE AND file:EXTENSION = "ks" {
            LOCAL srcPath TO PATH(path):COMBINE(file:NAME).
            LOCAL destPath TO changeVolume(CORE:VOLUME, path):COMBINE(file:NAME + "m").
            COMPILE srcPath TO destPath.
        }
    }
}

function changeVolume {
    DECLARE PARAMETER newVolume.
    DECLARE PARAMETER path.

    LOCAL newPath TO PATH(newVolume:ROOT).
    FOR segment IN PATH(path):SEGMENTS {
        SET newPath TO newPath:COMBINE(segment).
    }

    RETURN newPath.
}

IF SHIP:STATUS = "prelaunch" {
    compileDirectory(ARCHIVE:ROOT).
    SWITCH TO CORE:VOLUME.
}