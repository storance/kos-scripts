@LAZYGLOBAL off.

RUNONCEPATH("/lib/ship").
RUNONCEPATH("/lib/warp").

function createApoapsisManeuver {
    DECLARE PARAMETER pe.

    LOCAL deltaV TO calculateDeltaV(SHIP:APOAPSIS, SHIP:APOAPSIS, SHIP:PERIAPSIS, SHIP:APOAPSIS, pe).

    LOCAL nd to node(TIME:SECONDS + ETA:APOAPSIS, 0, 0, deltaV).
    ADD nd.

    RETURN nd.
}

function createPeriapsisManeuver {
    DECLARE PARAMETER ap.

    LOCAL deltaV TO calculateDeltaV(SHIP:PERIAPSIS, SHIP:APOAPSIS, SHIP:PERIAPSIS,ap, SHIP:PERIAPSIS).

    LOCAL nd to node(TIME:SECONDS + ETA:PERIAPSIS, 0, 0, deltaV).
    ADD nd.

    RETURN nd.
}

function updateApoapsisManeuver {
    DECLARE PARAMETER nd.
    DECLARE PARAMETER pe.

    LOCAL deltaV TO calculateDeltaV(SHIP:APOAPSIS, SHIP:APOAPSIS, SHIP:PERIAPSIS, SHIP:APOAPSIS, pe).

    IF (nd:PROGRADE <> deltaV) {
        SET nd:PROGRADE TO deltaV.
    }

    IF (nd:ETA <> ETA:APOAPSIS) {
        SET nd:ETA TO ETA:APOAPSIS.
    }
}

function updatePeriapsisManeuver {
    DECLARE PARAMETER pe.

    LOCAL deltaV TO calculateDeltaV(SHIP:PERIAPSIS, SHIP:APOAPSIS, SHIP:PERIAPSIS,ap, SHIP:PERIAPSIS).

    IF (nd:PROGRADE <> deltaV) {
        SET nd:PROGRADE TO deltaV.
    }

    IF (nd:ETA <> ETA:PERIAPSIS) {
        SET nd:ETA TO ETA:PERIAPSIS.
    }
}

function calculateDeltaV {
    DECLARE PARAMETER alt.
    DECLARE PARAMETER ap1.
    DECLARE PARAMETER pe1.
    DECLARE PARAMETER ap2.
    DECLARE PARAMETER pe2.

    LOCAL radius TO SHIP:BODY:RADIUS.
    LOCAL r TO alt + radius.
    LOCAL ac TO (ap1 + radius + pe1 + radius) / 2.
    LOCAL ad TO (ap2 + radius + pe2 + radius) / 2.

    LOCAL v1 TO sqrt(SHIP:BODY:MU * ((2/r) - (1/ac))).
    LOCAL v2 TO sqrt(SHIP:BODY:MU * ((2/r) - (1/ad))).

    RETURN v2 - v1.
}

function warpToNodeBurn {
    DECLARE PARAMETER nd.
    DECLARE PARAMETER burnTime.
    DECLARE PARAMETER extradt.

    warpFor(nd:ETA - (burnTime/2) - extradt).
}

function executeManeuver {
    DECLARE PARAMETER nd.

    LOCAL burnTime TO calculateBurnTime(nd:deltav:mag).

    warpFor(nd:ETA - (burnTime/2) - 60).
    pointAtNode(nd).
    warpFor(nd:ETA - (burnTime/2)).

    LOCAL dv0 TO nd:deltav.
    LOCAL done TO false.
    LOCAL np to R(0,0,0) * nd:deltav.

    UNTIL done {
        stageIfNeeded().

        LOCAL maxAcc to SHIP:AVAILABLETHRUST / SHIP:MASS.
        LOCAL thrott TO 1.0.
        IF (maxAcc > 0) {
            SET thrott TO MIN(nd:deltav:mag / maxAcc, 1).
        }
        LOCK THROTTLE TO thrott.

        LOCK STEERING TO LOOKDIRUP(nd:deltav, SHIP:FACING:TOPVECTOR).
            
        IF (vdot(dv0, nd:deltav) < 0) {
            LOCK THROTTLE TO 0.
            SET done TO true.
        } ELSE IF (nd:deltav:mag < 0.1) {
            WAIT UNTIL vdot(dv0, nd:deltav) < 0.5.

            LOCK THROTTLE TO 0.
            SET done TO true.
        }

        WAIT 0.1.
    }

    UNLOCK STEERING.
    REMOVE nd.
}

function pointAtNode {
    DECLARE PARAMETER nd.

    LOCAL np TO LOOKDIRUP(nd:deltav, SHIP:FACING:TOPVECTOR).
    LOCK STEERING TO np.
    WAIT UNTIL (abs(np:pitch - SHIP:FACING:PITCH) < 0.15 AND abs(np:yaw - SHIP:FACING:YAW) < 0.15) OR nd:ETA <= 1.
}