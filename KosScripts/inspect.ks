DECLARE PARAMETER tag.

SET taggedParts TO SHIP:PARTSDUBBED(tag).

FOR moduleName in taggedParts[0]:MODULES {
	PRINT moduleName.

	SET module TO taggedParts[0]:GETMODULE(moduleName).
	IF (module:ALLFIELDS:LENGTH > 0) {
		PRINT "  Fields:".
		FOR field IN module:ALLFIELDNAMES {
			PRINT "    " + field + " = " + module:GETFIELD(field).
		}
	}

	IF (module:ALLEVENTS:LENGTH > 0) {
		PRINT "  Events:".
		FOR event IN module:ALLEVENTNAMES {
			PRINT "    " + event.
		}
	}

	IF (module:ALLACTIONS:LENGTH > 0) {
		PRINT "  Actions:".
		FOR action IN module:ALLACTIONNAMES {
			PRINT "    " + action.
		}
	}
}