RUN ONCE lib_node.

SAS OFF.
CLEARSCREEN.

LOCAL nodeNumber TO 0.

FOR nd IN ALLNODES {
    SET nodeNumber TO nodeNumber + 1.

    LOCAL burnTime TO calculateBurnTime(nd:deltav:mag).
    
    PRINT "EXECUTING NODE #" + nodeNumber.
    PRINT "TOTAL DV: " + nd:DELTAV:MAG + "m/s".
    PRINT "PROGRADE DV: " + nd:PROGRADE + "m/s".
    PRINT "NORMAL DV: " + nd:NORMAL + "m/s".
    PRINT "RADIAL DV: " + nd:RADIALOUT + "m/s".
    PRINT "ESTIMATED BURN TIME: " + burnTime + "s".
    PRINT "".

    executeManeuver(nd).

    orientTowardsNormal().
}

SAS ON.