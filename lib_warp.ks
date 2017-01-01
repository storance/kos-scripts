@LAZYGLOBAL off.

function warpFor {
    DECLARE PARAMETER dt.

    IF (dt < 0) {
        SET KUNIVERSE:TIMEWARP:WARP TO 0.
        RETURN.
    }

    warpUntil(TIME:SECONDS + dt).
}

function warpUntil {
    DECLARE PARAMETER absTime.

    IF (SHIP:BODY:ATM:EXISTS AND SHIP:ALTITUDE < SHIP:BODY:ATM:HEIGHT) {
        SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
    } ELSE {
        SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
    }

    UNTIL absTime - 5 <= TIME:SECONDS {
        LOCAL timeRemaining TO absTime - TIME:SECONDS.

        LOCAL warpFactor TO 0.

        // detect if we should switch between physics and rails warp
        IF (NOT SHIP:BODY:ATM:EXISTS OR SHIP:ALTITUDE >= SHIP:BODY:ATM:HEIGHT) {
            IF (KUNIVERSE:TIMEWARP:MODE <> "RAILS") {
                SET KUNIVERSE:TIMEWARP:WARP TO 0.
                SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
            }
        } ELSE {
            IF (KUNIVERSE:TIMEWARP:MODE <> "PHYSICS") {
                SET KUNIVERSE:TIMEWARP:WARP TO 0.
                SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
            }
        }

        IF (WARPMODE = "PHYSICS") {
            SET warpFactor TO 4.
        } ELSE IF (timeRemaining > 100000) {
            SET warpFactor TO 7.
        } ELSE IF (timeRemaining > 10000) {
            SET warpFactor TO 6.
        } ELSE IF (timeRemaining > 1000) {
            SET warpFactor TO 5.
        } ELSE IF (timeRemaining > 100) {
            SET warpFactor TO 4.
        } ELSE IF (timeRemaining > 50) {
            SET warpFactor TO 3.
        } ELSE IF (timeRemaining > 15) {
            SET warpFactor TO 2.
        } ELSE IF (timeRemaining > 10) {
            SET warpFactor TO 1.
        }

        IF (KUNIVERSE:TIMEWARP:WARP <> warpFactor) {
            SET KUNIVERSE:TIMEWARP:WARP TO warpFactor.
        }

        WAIT 0.5.
    }

    SET KUNIVERSE:TIMEWARP:WARP TO 0.
    WAIT UNTIL absTime <= TIME:SECONDS.
}