DECLARE PARAMETER lan IS "".
DECLARE PARAMETER inc IS "".

RUN ONCE lib_util.

LOCAL targetName IS "".
IF (lan = "" OR inc = "") {
    SET targetName TO TARGET:NAME + " ".
    SET lan TO TARGET:ORBIT:LAN.
    SET inc to TARGET:ORBIT:INCLINATION.
}

LOCAL relLng IS ARCSIN(TAN(SHIP:LATITUDE) / TAN(inc)).
LOCAL univeralShipLng IS SHIP:LONGITUDE + SHIP:BODY:ROTATIONANGLE + relLng.
LOCAL anNodeAngle IS clampAngle(lan - univeralShipLng).
LOCAL dnNodeAngle IS clampAngle(anNodeAngle + 180).
LOCAL anEta IS (anNodeAngle / 360) * SHIP:BODY:ROTATIONPERIOD.
LOCAL dnEta IS (dnNodeAngle / 360) * SHIP:BODY:ROTATIONPERIOD.

PRINT "LAN:" + lan.
PRINT "Universal Ship Longitude: " + univeralShipLng.
PRINT "Ascending Node Angle: " + anNodeAngle + ", ETA: " + anETA.
PRINT "Descending Node Angle: " + dnNodeAngle + ", ETA: " + dnETA.

IF (dnEta < anEta) {
    LOCAL alarm IS addAlarm("DescendingNode", TIME:SECONDS + dnEta, "Launch Window: " + targetName + "Descending Node", "").
    SET alarm:ACTION TO "KillWarp".
} ELSE {
    LOCAL alarm IS addAlarm("AscendingNode", TIME:SECONDS + anEta, "Launch Window: " + targetName + "Ascending Node", "").
    SET alarm:ACTION TO "KillWarp".
}

