SWITCH TO ARCHIVE.

LIST FILES IN scripts.
FOR file IN scripts {
    IF file:ISFILE AND file:EXTENSION = "ks" {
        COMPILE file:NAME.
    }
}