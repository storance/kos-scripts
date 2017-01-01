@LAZYGLOBAL off.

FUNCTION clampAngle {
    DECLARE PARAMETER angle.

    IF (angle < 0) {
        SET angle TO angle + 360.
    }

    RETURN MOD(angle, 360).
}
