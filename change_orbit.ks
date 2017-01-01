DECLARE PARAMETER newPeKm.
DECLARE PARAMETER newApKm.

RUN lib_node.

SAS OFF.

SET apKm TO FLOOR(SHIP:APOAPSIS / 1000).
SET peKm TO FLOOR(SHIP:PERIAPSIS / 1000).

IF (newPeKm = apKm AND newApKm <> peKm) {
    executeManeuver(createApoapsisManeuver(newApKm * 1000)).
} ELSE IF (newApKm = peKm AND newPeKm <> apKm) {
    executeManeuver(createPeriapsisManeuver(newPeKm* 1000)).
} ELSE {
    LOCAL changeAp TO newApKm <> apKm.
    LOCAL changePe TO newPeKm <> peKm.

    // burn at the peFirst if we're at least 10 minutes away and it's closer than the apoapsis
    SET peFirst TO ETA:APOAPSIS > ETA:PERIAPSIS AND ETA:PERIAPSIS > 600.

    IF (peFirst) {
        LOCAL secondManeuverAtPe TO newApKm < peKm.

        IF (changeAp) {
            executeManeuver(createPeriapsisManeuver(newApKm * 1000)).
        }

        IF (changePe AND secondManeuverAtPe) {
            executeManeuver(createPeriapsisManeuver(newPeKm * 1000)).
        } ELSE IF (changePe) {
            executeManeuver(createApoapsisManeuver(newPeKm * 1000)).
        }
    } ELSE {
        LOCAL secondManeuverAtAp TO newPeKm > apKm.

        IF (changePe) {
            executeManeuver(createApoapsisManeuver(newPeKm * 1000)).
        }

        IF (changeAp AND secondManeuverAtAp) {
            executeManeuver(createApoapsisManeuver(newApKm * 1000)).
        } ELSE IF (changeAp) {
            executeManeuver(createPeriapsisManeuver(newApKm * 1000)).
        }
    }
}

orientTowardsNormal().
SAS ON.

