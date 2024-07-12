#!/bin/bash
s=/mnt/desynced/server
p=/mnt/desynced/persistentdata

verify_cpu_mhz() {
    local float_regex
    local cpu_mhz
    float_regex="^([0-9]+\\.?[0-9]*)\$"
    cpu_mhz=$(grep "^cpu MHz" /proc/cpuinfo | head -1 | cut -d : -f 2 | xargs)
    if [ -n "$cpu_mhz" ] && [[ "$cpu_mhz" =~ $float_regex ]] && [ "${cpu_mhz%.*}" -gt 0 ]; then
        debug "Found CPU with $cpu_mhz MHz"
        unset CPU_MHZ
    else
        debug "Unable to determine CPU Frequency - setting a default of 1.5 GHz so steamcmd won't complain"
        export CPU_MHZ="1500.000"
    fi
}

term_handler() {
	echo "Shutting down Server"

	PID=$(pgrep -f "^${s}/DesyncedServer.exe")
	if [[ -z $PID ]]; then
		echo "Could not find DesyncedServer.exe pid. Assuming server is dead..."
	else
		kill -n 15 "$PID"
		wait "$PID"
	fi
	wineserver -k
	sleep 1
	exit
}

cleanup_logs() {
	echo "Cleaning up logs older than $LOGDAYS days"
	find "$p" -name "*.log" -type f -mtime +$LOGDAYS -exec rm {} \;
}

trap 'term_handler' SIGTERM

verify_cpu_mhz

if [ -z "$LOGDAYS" ]; then
	LOGDAYS=30
fi
if [[ -n $UID ]]; then
	usermod -u "$UID" docker 2>&1
fi
if [[ -n $GID ]]; then
	groupmod -g "$GID" docker 2>&1
fi
if [ -z "$SERVERNAME" ]; then
	SERVERNAME="trueosiris-V"
fi
override_savename=""
if [[ -n "$WORLDNAME" ]]; then
	override_savename="-saveName $WORLDNAME"
fi
game_port=""
if [[ -n $GAMEPORT ]]; then
	game_port=" -gamePort $GAMEPORT"
fi
query_port=""
if [[ -n $QUERYPORT ]]; then
	query_port=" -queryPort $QUERYPORT"
fi

cleanup_logs

mkdir -p /root/.steam 2>/dev/null
chmod -R 777 /root/.steam 2>/dev/null
echo " "
echo "Updating Desynced Dedicated Server files..."
echo " "
/usr/bin/steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$s" +login anonymous +app_update 2943070 validate +quit
printf "steam_appid: "
cat "$s/steam_appid.txt"

#echo " "
#if ! grep -q -o 'avx[^ ]*' /proc/cpuinfo; then
#	unsupported_file="VRisingServer_Data/Plugins/x86_64/lib_burst_generated.dll"
#	echo "AVX or AVX2 not supported; Check if unsupported ${unsupported_file} exists"
#	if [ -f "${s}/${unsupported_file}" ]; then
#		echo "Changing ${unsupported_file} as attempt to fix issues..."
#		mv "${s}/${unsupported_file}" "${s}/${unsupported_file}.bak"
#	fi
#fi

#echo " "
#mkdir "$p/Settings" 2>/dev/null
#if [ ! -f "$p/Settings/ServerGameSettings.json" ]; then
#	echo "$p/Settings/ServerGameSettings.json not found. Copying default file."
#	cp "$s/VRisingServer_Data/StreamingAssets/Settings/ServerGameSettings.json" "$p/Settings/" 2>&1
#fi
#if [ ! -f "$p/Settings/ServerHostSettings.json" ]; then
#	echo "$p/Settings/ServerHostSettings.json not found. Copying default file."
#	cp "$s/VRisingServer_Data/StreamingAssets/Settings/ServerHostSettings.json" "$p/Settings/" 2>&1
#fi

# Checks if log file exists, if not creates it
current_date=$(date +"%Y%m%d-%H%M")
logfile="$current_date-DesyncedServer.log"
if ! [ -f "${p}/$logfile" ]; then
	echo "Creating ${p}/$logfile"
	touch "$p/$logfile"
fi

cd "$s" || {
	echo "Failed to cd to $s"
	exit 1
}
echo "Starting Desynced Dedicated Server with name $SERVERNAME"
echo "Trying to remove /tmp/.X0-lock"
rm /tmp/.X0-lock 2>&1
echo " "
echo "Starting Xvfb"
Xvfb :0 -screen 0 1024x768x16 &
echo "Launching wine64 Desynced"
echo " "
v() {
	DISPLAY=:0.0 wine64 /mnt/desynced/server/DesyncedServer.exe -persistentDataPath $p -serverName "$SERVERNAME" "$override_savename" -logFile "$p/$logfile" "$game_port" "$query_port" 2>&1 &
}
v
# Gets the PID of the last command
ServerPID=$!

# Tail log file and waits for Server PID to exit
/usr/bin/tail -n 0 -f "$p/$logfile" &
wait $ServerPID