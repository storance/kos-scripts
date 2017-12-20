RUNONCEPATH("lib/util").

FUNCTION main {
    LOCAL args IS get_arguments().
    LOCAL rel_lng IS ARCSIN(TAN(SHIP:LATITUDE) / TAN(args["inc"])).
    LOCAL univeral_ship_lng IS SHIP:LONGITUDE + SHIP:BODY:ROTATIONANGLE + rel_lng.
    LOCAL an_node_angle IS clampAngle(args["lan"] - univeral_ship_lng).
    LOCAL dn_node_angle IS clampAngle(an_node_angle + 180).
    LOCAL an_eta IS (an_node_angle / 360) * SHIP:BODY:ROTATIONPERIOD.
    LOCAL dn_eta IS (dn_node_angle / 360) * SHIP:BODY:ROTATIONPERIOD.

    IF (dn_eta < an_eta) {
        LOCAL alarm IS addAlarm("DescendingNode", TIME:SECONDS + dn_eta, "Launch Window: " + args["target_name"] + "Descending Node", "").
        SET alarm:ACTION TO "KillWarp".
    } ELSE {
        LOCAL alarm IS addAlarm("AscendingNode", TIME:SECONDS + an_eta, "Launch Window: " + args["target_name"] + "Ascending Node", "").
        SET alarm:ACTION TO "KillWarp".
    }
}

FUNCTION get_arguments {
    LOCAL gui IS GUI(300).
    LOCAL main_box IS gui:ADDVLAYOUT().
    LOCAL main_label IS main_box:ADDLABEL("<size=24><b>Launch Window</b></size>").
    SET main_label:STYLE:ALIGN TO "CENTER".

    LOCAL mode_box IS main_box:ADDHLAYOUT().
    mode_box:ADDLABEL("Mode: ").

    LOCAL mode_radio_box IS mode_box:ADDVLAYOUT().

    LOCAL target_mode_btn IS mode_radio_box:ADDRADIOBUTTON("Target", HASTARGET).
    LOCAL manual_mode_btn IS mode_radio_box:ADDRADIOBUTTON("Manual", NOT HASTARGET).

    LOCAL manual_config_box IS main_box:ADDVBOX().
    LOCAL manual_config_lbl IS manual_config_box:ADDLABEL("<size=20><b>Manual Configuration</b></size>").
    SET manual_config_lbl:STYLE:ALIGN TO "CENTER".

    LOCAL inc_box IS manual_config_box:ADDHLAYOUT().
    inc_box:ADDLABEL("Inclination: ").
    LOCAL inc_field IS inc_box:ADDTEXTFIELD("").
    SET inc_field:STYLE:WIDTH TO 60.
    SET inc_field:STYLE:HEIGHT TO 18.

    LOCAL lan_box IS manual_config_box:ADDHLAYOUT().
    lan_box:ADDLABEL("LAN: ").
    LOCAL lan_field IS lan_box:ADDTEXTFIELD("").
    SET lan_field:STYLE:WIDTH TO 60.
    SET lan_field:STYLE:HEIGHT TO 18.

    LOCAL ok_btn IS main_box:ADDBUTTON("Ok").
    SET ok_btn:STYLE:WIDTH TO 60.
    SET ok_btn:STYLE:MARGIN:LEFT TO 120.
    SET ok_btn:STYLE:MARGIN:TOP TO 10.

    SET mode_radio_box:ONRADIOCHANGE TO {
        PARAMETER selected_btn.

        IF (selected_btn:TEXT = "Target") {
            manual_config_box:HIDE().
        } ELSE {
            manual_config_box:SHOW().
        }
    }.

    IF (HASTARGET) {
        manual_config_box:HIDE().
    } ELSE {
        mode_box:HIDE().
    }

    LOCAL is_done IS FALSE.
    SET ok_btn:ONCLICK TO {
        SET is_done TO TRUE.
    }.

    gui:SHOW().
    WAIT UNTIL is_done.
    gui:HIDE().
    gui:DISPOSE().

    LOCAL args IS LEXICON().

    LOCAL targetName IS "".
    IF (mode_radio_box:RADIOVALUE = "Target") {
        args:ADD("target_name", TARGET:NAME + " ").
        args:ADD("inc", TARGET:ORBIT:INCLINATION).
        args:ADD("lan", TARGET:ORBIT:LAN).
    } ELSE {
        args:ADD("target_name", "").
        args:ADD("inc", inc_field:TEXT:TONUMBER).
        args:ADD("lan", lan_field:TEXT:TONUMBER).
    }

    RETURN args.
}

main().

