#!/bin/bash

AWLSrcDirPath=$(cd "$(dirname "$0")/../../"; pwd)
cd "$AWLSrcDirPath"

"$AWLSrcDirPath/Shared/Conf/Scripts/BuildPhase_SwiftLint.sh" "$SRCROOT/Attenuator"
"$AWLSrcDirPath/Shared/Conf/Scripts/BuildPhase_CheckHeaders.sh" "Attenuator" "$SRCROOT/Attenuator"
