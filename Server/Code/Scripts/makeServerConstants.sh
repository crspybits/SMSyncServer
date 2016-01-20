#!/bin/bash

# Script to extract constants out of .swift file containing constants and put them into a .js module so we don't have to keep retyping them every time they change.

# The relative path for INPUTFILE assumes that we run this script from the directory where serverConstants.js is located.
# Any spaces in the directory names don't need backslashes to escape the spaces.
INPUTFILE="../../iOSFramework/Code/Internal/SMServerConstants.swift"

OUTPUTFILE="serverConstants.js"
START="SERVER-CONSTANTS-START"
END="SERVER-CONSTANTS-END"
WARNING="// ***** This is a machine generated file: Do not change by hand!! *****"

echo "${WARNING}" > "${OUTPUTFILE}"
echo "'use strict';" >> "${OUTPUTFILE}"

# It turns out constants in modules are a bit of a PITA.
# See http://stackoverflow.com/questions/8595509/how-do-you-share-constants-in-nodejs-modules

echo "function define(name, value) {" >> "${OUTPUTFILE}"
echo "	Object.defineProperty(exports, name, {" >> "${OUTPUTFILE}"
echo "		value:      value," >> "${OUTPUTFILE}"
echo "		enumerable: true" >> "${OUTPUTFILE}"
echo "	});" >> "${OUTPUTFILE}"
echo "}" >> "${OUTPUTFILE}"

# http://stackoverflow.com/questions/17988756/how-to-select-lines-between-two-marker-patterns-which-may-occur-multiple-times-w
# http://www.thegeekstuff.com/2009/09/unix-sed-tutorial-replace-text-inside-a-file-using-substitute-command/

# The first awk is to only grab lines between the START and END bracketing lines.
# The second awk is to retain, in their entirety, purely comment lines (and empty lines), and do our define substitution on the other lines.

# The other lines have the form: public static let X = Y
# To change the pattern for the "other lines", you need to change the $4, $6 field numbers below appropriately.

# which we'll replace with: define("X", Y);
# print -- prints with a newline; printf -- prints without a newline
awk "/${START}/{flag=1;next}/${END}/{flag=0}flag" "${INPUTFILE}" | \
	awk '{ if (($1 == "//") || (0 == NF))\
				print $0; \
			else \
				printf "\tdefine(\"%s\", %s);\n", $4, $6 }' >> "${OUTPUTFILE}"
								
echo "${WARNING}" >> "${OUTPUTFILE}"
