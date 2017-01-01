IF SHIP:STATUS = "prelaunch" {
    SWITCH TO ARCHIVE.

    LIST FILES IN scripts.
    LOCAL size IS 0.
    FOR file IN scripts {
        IF file:ISFILE AND file:EXTENSION = "ksm" {
            SET size TO size + file:SIZE.
            COPYPATH(file:name, "1:").
        }
    }
    PRINT "Total Size: " + size.
}

SWITCH TO CORE:VOLUME.