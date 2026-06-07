#!/usr/bin/env bash
set -euo pipefail

echo "===== Intel System Summary ====="

CPU_MODEL=$(lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')
SOCKETS=$(lscpu | awk -F: '/Socket\(s\)/ {gsub(/ /,"",$2); print $2}')
CORES_PER_SOCKET=$(lscpu | awk -F: '/Core\(s\) per socket/ {gsub(/ /,"",$2); print $2}')
THREADS_PER_CORE=$(lscpu | awk -F: '/Thread\(s\) per core/ {gsub(/ /,"",$2); print $2}')
TOTAL_CORES=$((SOCKETS * CORES_PER_SOCKET))
TOTAL_THREADS=$(nproc)

MAX_MHZ=$(lscpu | awk -F: '/CPU max MHz/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')
CUR_MHZ=$(awk '/cpu MHz/ {print $4; exit}' /proc/cpuinfo)

TOTAL_MEM_GB=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
DRAM_PER_SOCKET_GB=$(awk -v m="$TOTAL_MEM_GB" -v s="$SOCKETS" 'BEGIN {printf "%.1f", m/s}')

echo "CPU Model              : $CPU_MODEL"
echo "Sockets                : $SOCKETS"
echo "Cores per socket       : $CORES_PER_SOCKET"
echo "Total physical cores   : $TOTAL_CORES"
echo "Threads per core       : $THREADS_PER_CORE"
echo "Total logical CPUs     : $TOTAL_THREADS"
echo "Current CPU MHz        : ${CUR_MHZ:-Unknown}"
echo "Max CPU MHz            : ${MAX_MHZ:-Unknown}"

echo
echo "===== DRAM Capacity ====="
echo "Total system DRAM      : ${TOTAL_MEM_GB} GB"
echo "Approx DRAM/socket     : ${DRAM_PER_SOCKET_GB} GB"

if command -v numactl >/dev/null 2>&1; then
    echo
    echo "DRAM per NUMA node:"
    numactl --hardware | awk '
        /node [0-9]+ size:/ {
            printf "  NUMA node %-2s          : %.1f GB\n", $2, $4/1024
        }'
fi

echo
echo "===== DIMM / Channel Detection ====="

sudo dmidecode -t memory 2>/dev/null | awk -v sockets="$SOCKETS" '
BEGIN {
    dimm_count=0
    total_mib=0
    max_speed=0
}

/^Handle / {
    size_mib=0
    locator=""
    bank=""
    socket=""
    channel=""
    speed=0
}

/^[ \t]*Size:/ {
    line=$0
    gsub(/^[ \t]*Size:[ \t]*/, "", line)

    if (line ~ /No Module Installed/) {
        size_mib=0
    } else {
        split(line,a," ")
        val=a[1]
        unit=a[2]

        if (unit == "GiB" || unit == "GB") {
            size_mib=val * 1024
        } else if (unit == "MiB" || unit == "MB") {
            size_mib=val
        }
    }
}

/^[ \t]*Locator:/ {
    locator=$0
    gsub(/^[ \t]*Locator:[ \t]*/, "", locator)

    # GNR example: CPU0_DIMM_A, CPU1_DIMM_L
    if (match(locator, /CPU[0-9]+/)) {
        socket=substr(locator, RSTART+3, RLENGTH-3)
    }

    if (match(locator, /DIMM_[A-Z]/)) {
        channel=substr(locator, RSTART+5, 1)
    } else if (match(locator, /DIMM[A-Z]/)) {
        channel=substr(locator, RSTART+4, 1)
    }
}

/^[ \t]*Bank Locator:/ {
    bank=$0
    gsub(/^[ \t]*Bank Locator:[ \t]*/, "", bank)
}

/^[ \t]*Configured Memory Speed:/ {
    line=$0
    gsub(/^[ \t]*Configured Memory Speed:[ \t]*/, "", line)
    split(line,a," ")
    if (a[1] ~ /^[0-9]+$/) speed=a[1]
}

/^[ \t]*Speed:/ {
    # fallback if Configured Memory Speed is absent
    if (speed == 0) {
        line=$0
        gsub(/^[ \t]*Speed:[ \t]*/, "", line)
        split(line,a," ")
        if (a[1] ~ /^[0-9]+$/) speed=a[1]
    }
}

/^[ \t]*Volatile Size:/ {
    # End-ish of populated DIMM block on your GNR output.
    # Print once we have size + locator data.
    if (size_mib > 0 && locator != "") {
        dimm_count++
        total_mib += size_mib

        if (speed > max_speed) max_speed=speed

        if (socket == "") socket="unknown"
        if (channel == "") channel="unknown"

        key=socket ":" channel
        seen_channel[key]=1

        printf "DIMM %-2d Socket=%-2s Channel=%-2s Size=%6.1f GiB Speed=%s MT/s Locator=%s Bank=%s\n", \
            dimm_count, socket, channel, size_mib/1024, speed ? speed : "Unknown", locator, bank

        # Prevent duplicate print from same block
        size_mib=0
        locator=""
    }
}

END {
    print ""
    print "===== Memory Summary From dmidecode ====="
    printf "Populated DIMMs          : %d\n", dimm_count
    printf "dmidecode total DRAM     : %.1f GiB\n", total_mib/1024

    if (max_speed > 0)
        printf "Configured memory speed  : %d MT/s\n", max_speed
    else
        printf "Configured memory speed  : Unknown\n"

    for (k in seen_channel) {
        split(k,a,":")
        if (a[2] != "unknown")
            channels_per_socket[a[1]]++
    }

    total_channels=0
    socket_count=0

    for (s in channels_per_socket) {
        printf "Socket %-2s channels       : %d\n", s, channels_per_socket[s]
        total_channels += channels_per_socket[s]
        socket_count++
    }

    if (socket_count > 0)
        channels_socket = total_channels / socket_count
    else
        channels_socket = dimm_count / sockets

    print ""
    print "===== Theoretical DRAM Bandwidth ====="

    if (max_speed > 0 && channels_socket > 0) {
        bw_socket = channels_socket * max_speed * 8 / 1000
        bw_total  = bw_socket * sockets

        printf "Channels/socket used     : %.0f\n", channels_socket
        printf "DRAM speed used          : %d MT/s\n", max_speed
        printf "Theoretical BW/socket    : %.1f GB/s\n", bw_socket
        printf "Theoretical BW/system    : %.1f GB/s\n", bw_total
    } else {
        print "Could not calculate bandwidth."
    }

    print ""
    print "Formula:"
    print "  BW/socket = channels/socket × MT/s × 8 bytes / 1000"
}'
