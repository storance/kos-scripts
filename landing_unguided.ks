
RUN lib_ship.
RUN lib_pid.

function preFlightChecks {
    IF (SHIP:STATUS <> "SUB_ORBITAL" AND SHIP:STATUS <> "FLYING") {
        PRINT "Active vessel must be sub-orbital or flying".
        RETURN false.
    }

    IF (SHIP:BODY:ATM:EXISTS) {
        PRINT "Atmospheric landings are not yet supported".
        RETURN false.
    }

    RETURN true.
}

function killHorizontalVelocity {
    pointAtAndWait(LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR)).

    LOCK STEERING TO LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).
    LOCK THROTTLE TO 1.0.
    WAIT UNTIL VANG(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR) < 45.

    LOCK THROTTLE TO 0.
}

function coastToSuicideBurn {
    pointAtAndWait(LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR)).
    LOCK STEERING TO LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).
    WAIT UNTIL getTimeToSuicideBurn() < 0.5.
}

function suicideBurn {
    LOCK THROTTLE TO 1.0.
    LOCK STEERING TO LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).

    WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG < 15.

    LOCK THROTTLE TO 0.
}

function landingApproach {
    LOCAL velocity_pid TO PID_Init(0.1, 0.2, 0.005, 0, 1).
    LOCAL pitch_pid TO PID_Init(2, 0.05, 0.05, -45, 45).
    LOCAL yaw_pid TO PID_Init(2, 0.05, 0.05, -45, 45).

    LOCAL targetDescentVelocity TO -3.
    LOCAL currentThrottle TO 0.
    LOCAL currentSteering TO LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).

    LOCK THROTTLE TO currentThrottle.
    LOCK STEERING TO currentSteering.

    UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
        LOCAL retrograde TO -SHIP:VELOCITY:SURFACE.
        LOCAL trueAltitude TO getTrueAltitude().

        IF (trueAltitude < 1000) {
            SET targetDescentVelocity TO -50.
        }

        IF (trueAltitude < 500) {
            SET targetDescentVelocity TO -25.
        }
       
        IF (trueAltitude < 250) {
            SET targetDescentVelocity TO -12.
        }
       
        IF (trueAltitude < 100) {
            SET targetDescentVelocity TO -6.
        }

        IF (trueAltitude < 50) {
            SET targetDescentVelocity TO -3.
        }
       
        IF (trueAltitude < 20) {
            SET targetDescentVelocity TO -1.
            SET currentSteering TO SHIP:UP + R(0,0,0).
        } ELSE {
            //LOCAL descentPrograde IS (retrograde:NORMALIZED + (UP + R(0,0,0)):VECTOR:NORMALIZED):NORMALIZED.
            LOCAL descentPrograde TO LOOKDIRUP(retrograde, SHIP:UP:VECTOR):VECTOR:NORMALIZED.
           
            // Still descending, keep trying to reduce horizontal movement.
            // Check if we're way off from up-right, if so, lock to vector mid-way between up and surface.
            IF (VANG(descentPrograde, (UP + R(0,0,0)):VECTOR) < 5) {
                // Let PID keep track of alignment.
                LOCAL pitchOffset IS -1 * PID_Seek(pitch_pid, 0, SHIP:VELOCITY:SURFACE * SHIP:FACING:TOPVECTOR).
                LOCAL yawOffset IS PID_Seek(yaw_pid, 0, SHIP:VELOCITY:SURFACE * SHIP:FACING:STARVECTOR).               
               
                SET currentSteering TO SHIP:UP + R(pitchOffset, yawOffset, 0).
            } ELSE {
                // We're way off, use mid-way vector.
                SET currentSteering TO descentPrograde.
            }
        }
       
        SET currentThrottle TO PID_Seek(velocity_pid, targetDescentVelocity, SHIP:VERTICALSPEED).
    }
}

function getTimeToSuicideBurn {
    LOCAL burnAltitude IS getSuicideBurnAltitude().
       
    IF burnAltitude < 0 {
        RETURN -1.
    }
   
    LOCAL time TO (getTrueAltitude() - burnAltitude) / VELOCITY:SURFACE:MAG.

    RETURN time.
}

function getSuicideBurnAltitude {
    IF (SHIP:AVAILABLETHRUST = 0) {
        RETURN -1.
    }
   
    LOCAL g TO SHIP:BODY:MU / ((SHIP:BODY:RADIUS + SHIP:ALTITUDE) ^ 2).
    LOCAL vd TO SHIP:VELOCITY:SURFACE:MAG.
    LOCAL va to ((SHIP:AVAILABLETHRUST / SHIP:MASS) - g).

    RETURN (vd^2) / (2*va).
    //RETURN (VELOCITY:SURFACE:MAG ^ 2) / (2 * (SHIP:AVAILABLETHRUST / (SHIP:MASS * g))).
}

FUNCTION getTrueAltitude {
    IF (ALT:RADAR = SHIP:ALTITUDE) {
        RETURN SHIP:ALTITUDE.
    } ELSE {
        RETURN SHIP:ALTITUDE - MAX(0, SHIP:GEOPOSITION:TERRAINHEIGHT).
    }
}

IF preFlightChecks() {
    SAS OFF.
    LOCK THROTTLE TO 0.

    // toggle landing gear off than on, since it starts on by default with landing legs not deployed
    GEAR OFF.
    WAIT 0.1.
    GEAR ON.

    killHorizontalVelocity().
    coastToSuicideBurn().
    suicideBurn().
    landingApproach().

    SAS ON.
    UNLOCK STEERING.
    UNLOCK THROTTLE.
}