RUNONCEPATH("lib/lazcalc").
RUNONCEPATH("lib/ship").
RUNONCEPATH("lib/node").

LOCAL inclination TO "".
LOCAL azimuth TO "".
LOCAL targetOrbitKm TO 0.
LOCAL targetOrbit TO 0.
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
    }

    RETURN true.
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
    LOCAL turnEnd TO targetOrbit * 0.5.
    LOCAL turnExponent TO 0.5.
    LOCAL turnStartVel TO 100.
    LOCAL deployAltitude TO 0.
    
    IF (launchAzimuth = "") {
        SET azData TO LAZcalc_init(targetOrbitKm, inclination).
        SET launchAzimuth TO LAZcalc(azData).
    }

    LOCK STEERING TO HEADING(launchAzimuth, 90 - pitch).
    LOCK THROTTLE TO 1.0.
    stageIfNeeded().
    stageLaunchClamps().

    IF SHIP:BODY:ATM:EXISTS {
        LOCAL engineInfo TO activeEngineInfo().
        SET turnExponent TO MAX(1 / (2.5 * engineInfo["maxTwr"] - 1.7), 0.25).
        //SET turnEnd TO 0.128 * SHIP:BODY:ATM:HEIGHT * engineInfo["maxTwr"] + 0.5 * SHIP:BODY:ATM:HEIGHT.
        SET turnEnd TO 0.128 * targetOrbit * engineInfo["maxTwr"] + 0.5 * SHIP:BODY:ATM:HEIGHT.
        SET deployAltitude TO SHIP:BODY:ATM:HEIGHT * 0.8.
        SET turnStartVel TO 100 - (engineInfo["maxTwr"] - 1.5) * 125.
    }

    PRINT "Turn Start Vel: " + turnStartVel + "m/s".
    PRINT "Turn End: " + turnEnd + "m".
    PRINT "Turn Exp: " + turnExponent.
    PRINT "Deploy Altitude: " + deployAltitude + "m".

    UNTIL SHIP:APOAPSIS > targetOrbit + buffer {
        IF (inclination <> "") {
            SET launchAzimuth TO LAZcalc(azData).
        }

        IF (azimuth = "") {
            SET launchAzimuth TO LAZcalc(azData).
        }

        LOCAL newPitch TO 0.
        IF (SHIP:BODY:ATM:EXISTS) {
            IF (SHIP:OBT:VELOCITY:SURFACE:MAG >= turnStartVel) {
                IF (turnStart = 0) {
                    SET turnStart TO SHIP:ALTITUDE.
                }

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

        IF (hasDeployables AND SHIP:ALTITUDE >= deployAltitude) {
            decoupleFairings().
            deploySolarPanels().
            deployRadiators().
            deployAntennas().
        }
        
        stageIfNeeded().

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

    WAIT 0.1.
    warpFor(nd:ETA - (burnTime/2) - 60).
    updateApoapsisManeuver(nd, targetOrbit).
    SAS OFF.

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

        WAIT 1.0.
    }

    SET decoupledFairings TO true.
}

function decoupleFairing {
    DECLARE PARAMETER fairing.

    IF (fairing:MODULES:CONTAINS("ProceduralFairingBase")) {
        // Procedural Fairings
        FOR child in fairing:CHILDREN {
            IF (child:MODULES:CONTAINS("ProceduralFairingDecoupler")) {
                LOCAL module TO child:GETMODULE("ProceduralFairingDecoupler").
                IF module:HASEVENT("jettison") {
                    module:DOEVENT("jettison").
                }
            }
        }
    } ELSE IF (fairing:MODULES:CONTAINS("ModuleProceduralFairing")) {
        // Stock fairings
        LOCAL module to fairing:GETMODULE("ModuleProceduralFairing").
        IF module:HASEVENT("deploy") {
            module:DOEVENT("deploy").
        }
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
            } ELSE IF (solarPanel:MODULES:CONTAINS("KopernicusSolarPanel")) {
                LOCAL module TO solarPanel:GETMODULE("KopernicusSolarPanel").
                IF (module:HASEVENT("extend solar panel")) {
                    module:DOEVENT("extend solar panel").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend solar panel' event.".
                }
            } ELSE {
                PRINT "ERROR: Could not find ModuleDeployableSolarPanel or KopernicusSolarPanel module.".
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

FUNCTION getArguments {
    LOCAL gui IS GUI(300).
    LOCAL main_box IS gui:ADDVLAYOUT().
    LOCAL main_label IS main_box:ADDLABEL("<size=24><b>Ascent Program</b></size>").
    SET main_label:STYLE:ALIGN TO "CENTER".

    LOCAL mode_box IS main_box:ADDHLAYOUT().
    mode_box:ADDLABEL("Mode: ").

    LOCAL mode_radio_box IS mode_box:ADDVLAYOUT().

    LOCAL inc_mode_btn IS mode_radio_box:ADDRADIOBUTTON("Inclination", FALSE).
    LOCAL az_mode_btn IS mode_radio_box:ADDRADIOBUTTON("Azimuth", TRUE).

    LOCAL inc_box IS main_box:ADDHLAYOUT().
    LOCAL inc_label IS inc_box:ADDLABEL("Inclination: ").
    LOCAL inc_field IS inc_box:ADDTEXTFIELD("" + ROUND(SHIP:LATITUDE, 2)).
    SET inc_field:STYLE:WIDTH TO 90.
    SET inc_field:STYLE:HEIGHT TO 18.

    LOCAL az_box IS main_box:ADDHLAYOUT().
    LOCAL az_label IS az_box:ADDLABEL("Azimuth: ").
    LOCAL az_field IS az_box:ADDTEXTFIELD("90").
    SET az_field:STYLE:WIDTH TO 90.
    SET az_field:STYLE:HEIGHT TO 18.

    LOCAL initial_orbit_km TO 25.
    IF (SHIP:BODY:ATM:EXISTS) {
        SET initial_orbit_km TO FLOOR((SHIP:BODY:ATM:HEIGHT * 1.4) / 1000).
    }

    LOCAL target_orbit_box IS main_box:ADDHLAYOUT().
    target_orbit_box:ADDLABEL("Target Orbit (km): ").
    LOCAL target_orbit_field IS target_orbit_box:ADDTEXTFIELD("" + initial_orbit_km).
    SET target_orbit_field:STYLE:WIDTH TO 90.
    SET target_orbit_field:STYLE:HEIGHT TO 18.

    LOCAL ok_btn IS main_box:ADDBUTTON("Ok").
    SET ok_btn:STYLE:WIDTH TO 60.
    SET ok_btn:STYLE:MARGIN:LEFT TO 120.
    SET ok_btn:STYLE:MARGIN:TOP TO 10.

    SET mode_radio_box:ONRADIOCHANGE TO {
        PARAMETER selected_btn.

        IF (selected_btn:TEXT = "Azimuth") {
            az_box:SHOW().
            inc_box:HIDE().
        } ELSE {
            az_box:HIDE().
            inc_box:SHOW().
        }
    }.

    inc_box:HIDE().

    LOCAL is_done IS FALSE.
    SET ok_btn:ONCLICK TO {
        SET is_done TO TRUE.
    }.

    gui:SHOW().
    WAIT UNTIL is_done.
    gui:HIDE().
    gui:DISPOSE().

    SET targetOrbitKm TO target_orbit_field:TEXT:TONUMBER.
    SET targetOrbit TO targetOrbitKm * 1000.
    IF (mode_radio_box:RADIOVALUE = "Azimuth") {       
        SET azimuth TO az_field:TEXT:TONUMBER.
    } ELSE {
        SET inclination TO inc_field:TEXT:TONUMBER. 
    }
}

getArguments().
checkForDeployables().
IF preFlightChecks() {
    SAS OFF.
    RCS ON.
    
    SET SHIP:CONTROL:MAINTHROTTLE TO 0.0.
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
