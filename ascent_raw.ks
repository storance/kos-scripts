DECLARE PARAMETER targetOrbitKm.
DECLARE PARAMETER azimuth.
DECLARE PARAMETER inclination.

RUN ONCE lib_lazcalc.
RUN ONCE lib_ship.
RUN ONCE lib_node.

LOCAL targetOrbit TO targetOrbitKm * 1000.

LOCAL decoupledFairings TO false.
LOCAL deployedSolarPanels TO false.
LOCAL deployedRadiators TO false.
LOCAL deployedAntennas TO false.
LOCAL hasDeployables TO false.

function checkForDeployables {
    LOCAL fairings TO SHIP:PARTSTAGGED("payloadFairing").
    LOCAL solarPanels TO SHIP:PARTSTAGGED("solarPanel").
    LOCAL radiators TO SHIP:PARTSTAGGED("radiator").
    LOCAL antennas TO SHIP:PARTSTAGGED("antenna").

    SET hasDeployables TO fairings:LENGTH + solarPanels:LENGTH + radiators:LENGTH + antennas:LENGTH > 0.
}

function preFlightChecks {
    IF (azimuth <> "" AND inclination <> "") {
        PRINT "Either azimuth or inclination should be set; not both.".
        RETURN false.
    }

    IF (STATUS <> "PRELAUNCH" AND STATUS <> "LANDED" AND STATUS <> "SPLASHED") {
        PRINT "Active vessel must be landed".
        RETURN false.
    }

    IF (SHIP:BODY:ATM:EXISTS) {
        IF (targetOrbit < SHIP:BODY:ATM:HEIGHT) {
            PRINT "Target orbit is inside of " + SHIP:BODY:NAME + "'s atmosphere".
            RETURN false.
        }

        LOCAL hasPresSensor TO hasPressureSensor().
        IF (hasDeployables AND NOT hasPresSensor) {
            PRINT "Pressure sensor is required for atmospheric ascent".
            RETURN false.
        }
    }

    RETURN true.
}

function hasPressureSensor {
    LOCAL sensorList TO LIST().
    LIST SENSORS IN sensorList.
    FOR sensor IN sensorList {
        IF (sensor:TYPE = "PRES") {
            RETURN true.
        }
    }

    RETURN false.
}

function countdownToLaunch {
    FROM {LOCAL countdown is 5.} UNTIL countdown < 0 STEP {SET countdown to countdown - 1.} DO {
        HUDTEXT("T-" + countdown, 1, 2, 30, GREEN, FALSE).
        WAIT 1. 
    }

    HUDTEXT("LIFT OFF", 10, 2, 30, GREEN, FALSE).
}

function ascendToApoapsis {
    LOCAL startAlt TO SHIP:ALTITUDE.
    LOCAL buffer TO 0.
    LOCAL pitch TO 0.
    LOCAL azData TO LIST().
    LOCAL launchAzimuth TO azimuth.
    LOCAL turnStart TO 0.
    LOCAL turnEnd TO 0.
    LOCAL turnExponent TO 0.
    LOCAL hasPresSensor TO hasPressureSensor().
    
    IF (launchAzimuth = "") {
        SET azData TO LAZcalc_init(targetOrbitKm, inclination).
        SET launchAzimuth TO LAZcalc(azData).
    }

    LOCK STEERING TO HEADING(launchAzimuth, 90 - pitch).
    LOCK THROTTLE TO 1.0.
    stageIfNeeded().

    IF SHIP:BODY:ATM:EXISTS {
        LOCAL engineInfo TO activeEngineInfo().
        SET turnExponent TO MAX(1 / (2.5 * engineInfo["maxTwr"] - 1.7), 0.25).
        SET turnEnd TO 0.128 * SHIP:BODY:ATM:HEIGHT * engineInfo["maxTwr"] + 0.5 * SHIP:BODY:ATM:HEIGHT.

        PRINT "TWR: " + engineInfo["maxTwr"].
        PRINT "Turn End: " + turnEnd.
        PRINT "Turn Exp: " + turnExponent.
    }

    UNTIL SHIP:APOAPSIS > targetOrbit + buffer {
        IF (inclination <> "") {
            SET launchAzimuth TO LAZcalc(azData).
        }

        IF (azimuth = "") {
            SET launchAzimuth TO LAZcalc(azData).
        }

        LOCAL newPitch TO 0.
        IF (SHIP:BODY:ATM:EXISTS) {
            IF (SHIP:OBT:VELOCITY:SURFACE:MAG >= 100) {
                IF (turnStart = 0) {
                    SET turnStart TO SHIP:ALTITUDE.
                }

                //LOCAL c to (0.13 * (SHIP:BODY:ATM:HEIGHT - startAlt)) / 70000.
                //SET newPitch TO min(90, sqrt(c * (SHIP:ALTITUDE - startAlt))).
                SET newPitch TO MIN(90, ((SHIP:ALTITUDE - turnStart) / (turnEnd - turnStart)) ^ turnExponent * 90.0).
            } ELSE {
                SET newPitch TO 0.
            }
        } ELSE {
            // ptich 45 degress until we have enough clearance with the ground, than go horizontal
            IF (SHIP:ALTITUDE < 5000 OR SHIP:ALTITUDE < startAlt + 1000) {
                SET newPitch TO 45.
            } ELSE {
                SET newPitch TO 90.
            }
        }

        IF (newPitch - pitch > 0.2) {
            SET pitch TO newPitch.
        }
        
        IF (SHIP:BODY:ATM:EXISTS AND hasPresSensor) {
            IF (hasDeployables AND SHIP:SENSORS:PRES <= 0.1) {
                decoupleFairings().
            }

            IF (hasDeployables AND SHIP:SENSORS:PRES <= 0.01) {
                deploySolarPanels().
                deployRadiators().
                deployAntennas().
            }
        }

        IF (stageIfNeeded()) {
            // check if we still have a pressure sensor after staging
            SET hasPresSensor TO hasPressureSensor().
        }

        IF (SHIP:APOAPSIS > targetOrbit * 0.95) {
            LOCK THROTTLE TO 0.25.
        }

        IF (NOT SHIP:BODY:ATM:EXISTS OR SHIP:ALTITUDE >= SHIP:BODY:ATM:HEIGHT) {
            SET buffer TO 0.
        } ELSE {
            SET buffer TO 400 * LN(SHIP:BODY:ATM:HEIGHT / SHIP:ALTITUDE).
        }

        WAIT 0.1.
    }
}

function circularizeOrbit {
    LOCK THROTTLE TO 0.
    LOCK STEERING TO SHIP:PROGRADE.

    stageIfNeeded().
    LOCAL nd TO createApoapsisManeuver(targetOrbit).
    LOCAL burnTime TO calculateBurnTime(nd:deltav:mag).

    warpFor(nd:ETA - (burnTime/2) - 60).
    updateApoapsisManeuver(nd, targetOrbit).

    decoupleFairings().
    deploySolarPanels().
    deployRadiators().
    deployAntennas().

    executeManeuver(nd).
}

function decoupleFairings {
    IF (decoupledFairings) {
        RETURN.
    }

    LOCAL fairings TO SHIP:PARTSTAGGED("payloadFairing").

    IF (fairings:LENGTH > 0) {
        PRINT "JETTISONING PAYLOAD FAIRINGS".

        FOR fairing IN fairings {
            decoupleFairing(fairing).
        }
    }

    SET decoupledFairings TO true.
}

function decoupleFairing {
    DECLARE PARAMETER fairing.

    IF (fairing:MODULES:CONTAINS("ProceduralFairingBase")) {
        // Procedural Fairings
        FOR child in fairing:CHILDREN {
            IF (child:MODULES:CONTAINS("ProceduralFairingDecoupler")) {
                child:GETMODULE("ProceduralFairingDecoupler"):DOEVENT("jettison").
            }
        }
    } else IF (fairing:MODULES:CONTAINS("ModuleProceduralFairing")) {
        // Stock fairings
        fairing:GETMODULE("ModuleProceduralFairing"):DOEVENT("deploy").
    }
}

function deploySolarPanels {
    IF (deployedSolarPanels) {
        RETURN.
    }

    LOCAL solarPanels TO SHIP:PARTSTAGGED("solarPanel").

    IF (solarPanels:LENGTH > 0) {
        PRINT "DEPLOYING " + solarPanels:LENGTH + " SOLAR PANEL(S)".

        FOR solarPanel IN solarPanels {
            IF (solarPanel:MODULES:CONTAINS("ModuleDeployableSolarPanel")) {
                LOCAL module TO solarPanel:GETMODULE("ModuleDeployableSolarPanel").
                IF (module:HASEVENT("extend solar panel")) {
                    module:DOEVENT("extend solar panel").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend solar panel' event.".
                }
            } ELSE {
                PRINT "ERROR: Could not find ModuleDeployableSolarPanel module.".
            }
        }
    }

    SET deployedSolarPanels TO true.
}

function deployRadiators {
    IF (deployedRadiators) {
        RETURN.
    }

    LOCAL radiators TO SHIP:PARTSTAGGED("radiator").

    IF (radiators:LENGTH > 0) {
        PRINT "DEPLOYING " + radiators:LENGTH + " RADIATOR(S)".

        FOR radiator IN radiators {
            IF (radiator:MODULES:CONTAINS("ModuleDeployableRadiator")) {
                LOCAL module TO radiator:GETMODULE("ModuleDeployableRadiator").
                IF (module:HASEVENT("extend radiator")) {
                    module:DOEVENT("extend radiator").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend radiator' event.".
                }
            } ELSE {
                PRINT "ERROR: Could not find ModuleDeployableRadiator module.".
            }
        }
    }

    SET deployedRadiators TO true.
}

function deployAntennas {
    IF (deployedAntennas) {
        RETURN.
    }

    LOCAL antennas TO SHIP:PARTSTAGGED("antenna").
    IF (antennas:LENGTH > 0) {
        PRINT "DEPLOYING " + antennas:LENGTH + " ANTENNA(S)".
        
        FOR antenna IN antennas {
            IF (antenna:MODULES:CONTAINS("ModuleDeployableAntenna")) {
                LOCAL module TO antenna:GETMODULE("ModuleDeployableAntenna").
                IF (module:HASEVENT("extend antenna")) {
                    module:DOEVENT("extend antenna").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend antenna' event.".
                }
            } ELSE {
                PRINT "ERROR: Could not find ModuleDeployableAntenna module.".
            }
        }
    }

    SET deployedAntennas TO true.
}

checkForDeployables().
IF preFlightChecks() {
    SAS OFF.
    
    LOCK THROTTLE TO 0.0.
    countdownToLaunch().

    ascendToApoapsis().
    circularizeOrbit().
    orientTowardsNormal().

    SAS ON.
    SET SHIP:CONTROL:MAINTHROTTLE TO 0.0.
    UNLOCK STEERING.
    UNLOCK THROTTLE.
}
