@LAZYGLOBAL off.

function calculateBurnTime {
    DECLARE PARAMETER dv.

    // TODO: calculate burn duration if it span's multiple stages
    // might not be possible

    LOCAL engineInfo TO activeEngineInfo.
    LOCAL g0 TO 9.81.
    LOCAL ve TO engineInfo["isp"] * g0.
    LOCAL m0 TO SHIP:MASS.
    LOCAL Th TO engineInfo["maxThrust"].
    LOCAL e  TO CONSTANT():E.

    RETURN (m0 * ve / Th) * (1 - e^(-dv/ve)).
}

function activeEngineInfo {
    LOCAL engineINFO TO LEXICON().

    LOCAL allEngines TO LIST().
    LOCAL ispSum TO 0.
    LOCAL maxThrust TO 0.

    LIST ENGINES IN allEngines.
    FOR engine IN allEngines {
        IF engine:IGNITION {
            SET ispSum TO ispSum + (engine:MAXTHRUST / engine:ISP).
            SET maxThrust TO maxThrust + engine:AVAILABLETHRUST.
        }
    }

    LOCAL ispAvg TO 0.
    IF ispSum > 0 {
        SET ispAvg TO maxThrust / ispSum.
    }

    engineInfo:ADD("maxThrust", maxThrust).
    engineInfo:ADD("isp", ispAvg).
    engineInfo:ADD("maxTwr", maxThrust / (SHIP:MASS * BODY:MU / (ALTITUDE + BODY:RADIUS)^2)).

    RETURN engineINFO.
}


function calculateStageTwr {
    LOCAL thrust TO calculateStageThrust.

    return thrust / (SHIP:MASS * BODY:MU / (ALTITUDE + BODY:RADIUS)^2).
}

function stageIfNeeded {
    IF (NOT STAGE:READY) {
        RETURN false.
    }

    LOCAL allEngines TO LIST().
    LIST ENGINES IN allEngines.

    LOCAL enginesIgnited TO 0.
    LOCAL enginesFlamedOut TO 0.
    LOCAL animatingEngine TO false.
    FOR engine IN allEngines {
        IF (engine:STAGE = STAGE:NUMBER AND (engine:HASMODULE("SSTUDeployableEngine") OR engine:HASMODULE("ModuleDeployableEngine"))) {
            SET animatingEngine TO true.
        }

        IF (engine:IGNITION) {
            SET enginesIgnited TO enginesIgnited + 1.

            IF (engine:FLAMEOUT) {
                SET enginesFlamedOut TO enginesFlamedOut + 1.
            }
        }
    }

    IF (enginesIgnited = 0 AND animatingEngine) {
        WAIT 2.
        RETURN false.
    }

    IF (enginesIgnited = 0 OR enginesFlamedOut > 0) {
        STAGE.
        WAIT UNTIL STAGE:READY.
        RETURN true.
    }

    RETURN false.
}

function stageLaunchClamps {
    LOCAL launchClampsCount TO SHIP:MODULESNAMED("LaunchClamp"):LENGTH + SHIP:MODULESNAMED("ExtendingLaunchClamp"):LENGTH + SHIP:MODULESNAMED("ModuleRestockLaunchClamp"):LENGTH.

    UNTIL launchClampsCount = 0 {
        STAGE.
        WAIT UNTIL STAGE:READY.

        SET launchClampsCount TO SHIP:MODULESNAMED("LaunchClamp"):LENGTH + SHIP:MODULESNAMED("ExtendingLaunchClamp"):LENGTH + SHIP:MODULESNAMED("ModuleRestockLaunchClamp"):LENGTH.
    }
}

function orientTowardsNormal {
    LOCAL normVec TO VCRS(SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT).
    LOCAL normDir TO LOOKDIRUP(normVec, SHIP:BODY:POSITION).

    pointAtAndWait(normDir).
}

function pointAtAndWait {
    DECLARE PARAMETER direction.

    LOCK STEERING TO direction.
    WAIT UNTIL abs(direction:PITCH - SHIP:FACING:PITCH) < 0.15 and abs(direction:YAW - SHIP:FACING:YAW) < 0.15.
}