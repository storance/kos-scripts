RUNONCEPATH("lib/lazcalc").
RUNONCEPATH("lib/ship").
RUNONCEPATH("lib/node").

LOCAL inclination TO "".
LOCAL azimuth TO "".
LOCAL targetOrbitKm TO 0.
LOCAL targetOrbit TO 0.
LOCAL deployAltitude TO 0.
LOCAL sasLevel TO 0.
LOCAL decoupledFairings TO false.
LOCAL deployedSolarPanels TO false.
LOCAL deployedRadiators TO false.
LOCAL deployedAntennas TO false.
LOCAL jettisonedLES TO false.
LOCAL hasDeployables TO false.

function checkForDeployables {
    LOCAL fairings TO SHIP:PARTSTAGGED("payloadFairing").
    LOCAL solarPanels TO SHIP:PARTSTAGGED("solarPanel").
    LOCAL radiators TO SHIP:PARTSTAGGED("radiator").
    LOCAL antennas TO SHIP:PARTSTAGGED("antenna").
    LOCAL les TO SHIP:PARTSTAGGED("les").

    SET hasDeployables TO fairings:LENGTH + solarPanels:LENGTH + radiators:LENGTH + antennas:LENGTH + les:LENGTH > 0.
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
    LOCAL controllingTimeToAP TO FALSE.

    LOCAL timeToApPid TO PIDLOOP(0.5, 0.006, 0.006, -10, 30).
    SET timeToApPid:SETPOINT TO 60.

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
        LOCAL effectiveTWR TO engineInfo["maxTwr"].

        SET turnExponent TO MAX(1 / (2.5 * effectiveTWR - 1.7), 0.25).
        SET turnEnd TO (0.128 * SHIP:BODY:ATM:HEIGHT * effectiveTWR) + (0.4 * SHIP:BODY:ATM:HEIGHT) + ((targetOrbit - SHIP:BODY:ATM:HEIGHT) * effectiveTWR * 0.192).
        SET turnStartVel TO 100 - (effectiveTWR - 1.5) * 125.
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
        IF (NOT controllingTimeToAP) {
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
        }

        IF (controllingTimeToAP OR (pitch >= 80 AND ETA:APOAPSIS < 60))  {
            IF (NOT controllingTimeToAP AND SHIP:ALTITUDE < turnEnd ) {
                PRINT "Aborting pitch program and entering control time to apoapsis mode.".
            }
            SET controllingTimeToAP TO TRUE.
            LOCAL pitchUpdate TO timeToApPid:UPDATE(TIME:SECONDS, ETA:APOAPSIS).
            SET newPitch TO 90 - pitchUpdate.
        }

        SET pitch TO newPitch.

        IF (hasDeployables AND SHIP:ALTITUDE >= deployAltitude) {
            decoupleFairings().
            jettisonLaunchEscapeSystem().
            deploySolarPanels().
            deployRadiators().
            deployAntennas().
        }

        stageIfNeeded().

        IF (SHIP:APOAPSIS > (targetOrbit - 5000)) {
            LOCK THROTTLE TO 0.25.
        }

        IF (NOT SHIP:BODY:ATM:EXISTS OR SHIP:ALTITUDE >= SHIP:BODY:ATM:HEIGHT) {
            SET buffer TO 0.
        } ELSE {
            SET buffer TO 400 * LN(SHIP:BODY:ATM:HEIGHT / SHIP:ALTITUDE).
        }

        WAIT 0.01.
    }
}

function circularizeOrbit {
    LOCK THROTTLE TO 0.
    LOCK STEERING TO SHIP:PROGRADE.
    WAIT 1.0.

    stageIfNeeded().
    LOCAL nd TO createApoapsisManeuver(targetOrbit).
    LOCAL burnTime TO calculateBurnTime(nd:deltav:mag).

    IF sasLevel > 0 {
        SAS ON.
        WAIT 0.1.
        SET SASMODE TO "PROGRADE".
    } ELSE {
        WAIT 0.1.
    }
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
                IF module:HASEVENT("jettison fairing") {
                    module:DOEVENT("jettison fairing").
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

function jettisonLaunchEscapeSystem {
    IF (jettisonedLES) {
        RETURN.
    }

    LOCAL launchEscapeSystems TO SHIP:PARTSTAGGED("les").
    IF (launchEscapeSystems:LENGTH > 0) {
        PRINT "Jettisoning Launch Escape System".

        FOR les IN launchEscapeSystems {
            LOCAL decoupleModule TO "".
            LOCAL engineModule TO "".

            IF (les:MODULES:CONTAINS("ModuleDecouple")) {
                SET decoupleModule TO les:GETMODULE("ModuleDecouple").
            }

            IF (les:MODULES:CONTAINS("ModuleEnginesFX")) {
                SET engineModule TO les:GETMODULE("ModuleEnginesFX").
            } ELSE IF (les:MODULES:CONTAINS("ModuleEngines")) {
                SET engineModule TO les:GETMODULE("ModuleEngines").
            }

            If (engineModule <> "" AND decoupleModule <> "") {
                if (engineModule:HASEVENT("activate engine") AND decoupleModule:HASEVENT("decouple")) {
                    engineModule:DOEVENT("activate engine").
                    decoupleModule:DOEVENT("decouple").
                } ELSE {
                    PRINT "ERROR: Could not find event 'decouple' and/or 'activate engine'".
                }
            } ELSE {
                PRINT "ERROR: Could not fine 'ModuleDecouple' and/or a 'ModuleEngines'".
            }
        }
    }

    SET jettisonedLES TO true.
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
                } ELSE IF (module:HASEVENT("extend panel")) {
                    module:DOEVENT("extend panel").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend solar panel' event.".
                }
            } ELSE IF (solarPanel:MODULES:CONTAINS("KopernicusSolarPanel")) {
                LOCAL module TO solarPanel:GETMODULE("KopernicusSolarPanel").
                IF (module:HASEVENT("extend solar panel")) {
                    module:DOEVENT("extend solar panel").
                } ELSE IF (module:HASEVENT("extend panel")) {
                    module:DOEVENT("extend panel").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend solar panel' event.".
                }
            } ELSE IF (solarPanel:MODULES:CONTAINS("SSTUSolarPanelDeployable")) {
                LOCAL module TO solarPanel:GETMODULE("SSTUSolarPanelDeployable").
                IF (module:HASEVENT("extend solar panels")) {
                    module:DOEVENT("extend solar panels").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend solar panels' event.".
                }
            } ELSE {
                PRINT "ERROR: Could not find ModuleDeployableSolarPanel, KopernicusSolarPanel, or SSTUSolarPanelDeployable module.".
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
                } ELSE IF (module:HASEVENT("extend panel")) {
                    module:DOEVENT("extend panel").
                } ELSE IF (module:HASEVENT("extend")) {
                    module:DOEVENT("extend").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend antenna' or 'extend panel' event.".
                }
            } ELSE IF (antenna:MODULES:CONTAINS("ModuleAnimateGeneric")) {
                LOCAL module TO antenna:GETMODULE("ModuleAnimateGeneric").
                IF (module:HASEVENT("extend")) {
                    module:DOEVENT("extend").
                } ELSE {
                    PRINT "ERROR: Could not find 'extend' event.".
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
        // Calculate and orbit that is 1.4 higher than the atmosphere height rounded up to nearest 10 km.
        SET initial_orbit_km TO CEILING((SHIP:BODY:ATM:HEIGHT * 1.4) / 10000) * 10.
    }

    LOCAL target_orbit_box IS main_box:ADDHLAYOUT().
    target_orbit_box:ADDLABEL("Target Orbit (km): ").
    LOCAL target_orbit_field IS target_orbit_box:ADDTEXTFIELD("" + initial_orbit_km).
    SET target_orbit_field:STYLE:WIDTH TO 90.
    SET target_orbit_field:STYLE:HEIGHT TO 18.

    LOCAL initial_deploy_altitude TO 0.
    IF (SHIP:BODY:ATM:EXISTS) {
       SET initial_deploy_altitude TO FLOOR(SHIP:BODY:ATM:HEIGHT / 1000).
    }

    LOCAL deploy_altitude_box IS main_box:ADDHLAYOUT().
    deploy_altitude_box:ADDLABEL("Deploy Altitude (km): ").
    LOCAL deploy_altitude_field IS deploy_altitude_box:ADDTEXTFIELD("" + initial_deploy_altitude).
    SET deploy_altitude_field:STYLE:WIDTH TO 90.
    SET deploy_altitude_field:STYLE:HEIGHT TO 18.


    LOCAL sas_level_box IS main_box:ADDHLAYOUT().
    sas_level_box:ADDLABEL("SAS Level: ").
    LOCAL sas_level_field IS sas_level_box:ADDTEXTFIELD("0").
    SET sas_level_field:STYLE:WIDTH TO 90.
    SET sas_level_field:STYLE:HEIGHT TO 18.

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
    SET deployAltitude TO deploy_altitude_field:TEXT:TONUMBER * 1000.
    SET sasLevel TO sas_level_field:TEXT:TONUMBER.
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
    //orientTowardsNormal().

    SAS ON.
    SET SHIP:CONTROL:MAINTHROTTLE TO 0.0.
    UNLOCK STEERING.
    UNLOCK THROTTLE.
}
