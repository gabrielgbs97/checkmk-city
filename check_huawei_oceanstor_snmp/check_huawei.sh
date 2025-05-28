#!/bin/bash

if [ ! "$#" == "4" ]; then
        echo -e "\nWarning: Wrong command line arguments. \nUsage: ./check_huawei <hostname> <part> <warning> <critical>\n \nParts are:  lunusage, poolusage, poolstatus, cpu, tempsys, hdstatus, psustatus, fanstatus, controller, enclosure, bbustatus, uptime, memuse, luntraffic, latency and iops\nExample: ./check_huawei 127.0.0.1 poolusage  10 5\n" && exit "3"
fi
strHostname=$1
strpart=$2
strWarning=$3
strCritical=$4

strAuthUser='checkmk'
strAuthSecret=''
strPrivSecret=''
snmpwalk_cmd="snmpwalk -v 3 -t 120 -O vqe  -u $strAuthUser -l authPriv -a SHA -A $strAuthSecret -x AES -X $strPrivSecret $strHostname"
# Check if storage is accessible.
TEST=$(snmpstatus -v 3 -r 0 -u $strAuthUser -l authPriv -a SHA -A $strAuthSecret -x AES -X $strPrivSecret $strHostname 2>&1) 
# echo "Test: $TEST"; 
if [ "$TEST" == "Timeout: No Response from $strHostname" ]; then 
echo "CRITICAL: SNMP to $strHostname is not available"; 
exit 2;
fi

# LUNUSAGE ---------------------------------------------------------------------------------------------------------------------------------------
if [ "$strpart" == "lunusage" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.8.1.2 | tr -d '"' | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.8.1.1 | tr -d '"' |  tr '\n' ' '))
    declare -a capacity=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.8.1.5 | tr -d '"' | tr '\n' ' '))
    declare -a usedspace=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.8.1.6 | tr -d '"' | tr '\n' ' '))
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Unknown: Check not supported"
        exit 3
    fi

    status_message=""
    crit=0
    warn=0
    ok=0
    
    for line in ${ids[@]}
    do
        let "perc=((${usedspace[c]}*100)/${capacity[c]})"
        perfdata="$perfdata LUN_${nums[c]}=$perc;$strWarning;$strCritical"
        status=""
        if [[ $perc -gt $strCritical ]]
        then
            status="CRIT"
            crit=1
        elif [[ $perc -gt $strWarning ]]
        then
            status="WARN"
            warn=1
        else
            status="OK"
            ok=1
        fi
        status_message="$status_message $status: LUN ${nums[c]} $perc% used;"
        let c++
    done
    
    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message |$perfdata"
        exit 2
    elif [[ $warn -eq 1 ]]
    then
        echo "Warning:$status_message |$perfdata"
        exit 1
    elif [[ $ok -eq 1 ]]
    then
        echo "OK:$status_message |$perfdata"
        exit 0
    else
        echo "Unknown: StoragePool Status not found"
        exit 3
    fi

# Poolusage ----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "poolusage" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.2.1.2 | tr -d '"' | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.2.1.1 | tr -d '"' |  tr '\n' ' '))
    declare -a capacity=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.2.1.7 | tr '\n' ' '))
    declare -a usedspace=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.2.1.9 | tr '\n' ' '))
    
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Unknown: Check not supported"
        exit 3
    fi

    status_message=""
    crit=0
    warn=0
    ok=0
    
    for line in ${ids[@]}
    do
        let "perc=((${usedspace[c]}*100)/${capacity[c]})"
        perfdata="$perfdata ${nums[c]}=$perc;$strWarning;$strCritical"
        status=""
        if [[ $perc -gt $strCritical ]]
        then
            status="CRIT"
            crit=1
        elif [[ $perc -gt $strWarning ]]
        then
            status="WARN"
            warn=1
        else
            status="OK"
            ok=1
        fi
        status_message="$status_message $status: SP ${nums[c]} $perc% used;"
        let c++
    done
    
    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message |$perfdata"
        exit 2
    elif [[ $warn -eq 1 ]]
    then
        echo "Warning:$status_message |$perfdata"
        exit 1
    elif [[ $ok -eq 1 ]]
    then
        echo "OK:$status_message |$perfdata"
        exit 0
    else
        echo "Unknown: StoragePool Status not found"
        exit 3
    fi


# Poolstatus ----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "poolstatus" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.2.1.2 | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.2.1.1 |  tr '\n' ' '))
    declare -a sp_status=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.2.1.5 | tr '\n' ' '))

    c=0
    if [ "$ids" = "No" ]
    then
        echo "Unknown: Check not supported"
        exit 3
    fi

    status_message=""
    crit=0
    warn=0
    ok=0
    
    for line in ${ids[@]}
    do
        status=""
        if [[ ${sp_status[${c}]} -eq 0 ]]
        then
            status="CRIT"
            crit=true
        else
            status="OK"
            ok=1
        fi
        status_message="$status_message $status: SP ${nums[c]};"
        let c++
    done
    
    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message"
        exit 2
    elif [[ $ok -eq 1 ]]
    then
        echo "OK:$status_message"
        exit 0
    else
        echo "Unknown: StoragePool Status not found"
        exit 3
    fi

# CPU ----------------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "cpu" ]; then
        declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.21.3.1.1 | tr '\n' ' '))
        declare -a cpu=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.21.3.1.2 | tr '\n' ' '))
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Unknown: Check not supported"
        exit 3
    fi

    status_message=""
    crit=0
    warn=0
    ok=0

    for line in ${ids[@]}
        do
        perfdata="$perfdata CPU${ids[c]}=$cpu;$strWarning;$strCritical"
        if [[ ${cpu[${c}]} -gt $strCritical  ]]
        then
            status="CRIT"
            crit=1
        elif [[ ${cpu[${c}]} -gt $strWarning  ]]
        then
            status="WARN"
            warn=1
        else
            status="OK"
            ok=1
        fi
        status_message="$status_message $status: CPU${ids[c]} ${cpu[${c}]}% used;"
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message |$perfdata"
        exit 2
    elif [[ $warn -eq 1 ]]
    then
        echo "Warning:$status_message |$perfdata"
        exit 1
    elif [[ $ok -eq 1 ]]
    then
        echo "OK:$status_message |$perfdata"
        exit 0
    else
        echo "Unknown: CPU Status not found"
        exit 3
    fi
        
# Enclosure Temperature---------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "tempsys" ]; then
    TEMPSYS=$($snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.6.1.8)
    status_message="Enclosure Temp=$[TEMPSYS]C|'Enclosure Temp C'=$[TEMPSYS]C;$strWarning;$strCritical"

    if [[ $TEMPSYS -ge $strCritical ]]; then
            echo "CRITICAL: "$status_message
            exit 2
    fi
    if [[ $TEMPSYS -ge $strWarning ]]; then
            echo "WARNING: "$status_message
            exit 1
    fi
    echo "OK: "$status_message
    exit 0
        
# HD Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "hdstatus" ]; then
    declare -a nums=($(eval $snmpwalk_cmd  .1.3.6.1.4.1.34774.4.1.23.5.1.1.4 | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd  .1.3.6.1.4.1.34774.4.1.23.5.1.1.1 | tr -d '"' | tr '\n' ' '))
    declare -a hd_status=($(eval $snmpwalk_cmd  .1.3.6.1.4.1.34774.4.1.23.5.1.1.2 | tr '\n' ' '))
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Check not supported"
        exit 3
    fi

    crit=0
    ok=0

    for line in ${ids[@]}
        do
        if [[ ${hd_status[${c}]} -ne 1 ]]
        then
            status="CRIT"
            crit=1
            status_message="$status_message DISK${ids[c]}=$status"
        elif [[ ${hd_status[${c}]} -eq 1 ]]
        then
            status="OK"
            ok=1
        fi
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message"
        exit 2
    elif [[ $ok -eq 1 ]]
    then
        echo "OK: All (${#hd_status[@]}) Disks are healthy"
        exit 0
    else
        echo "Unknown: Disks Status not found"
        exit 3
    fi

# PSU Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "psustatus" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.3.1.2 | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.3.1.1 | tr -d '"' | tr '\n' ' '))
    declare -a psu_status=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.3.1.3 | tr '\n' ' '))
    
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Check not supported"
        exit 3
    fi

    crit=0
    ok=0

    for line in ${ids[@]}
        do
        if [[ ${psu_status[${c}]} -ne 1 ]]
        then
            status="CRIT"
            crit=1
            status_message="$status_message PSU${ids[c]}=$status"
        elif [[ ${psu_status[${c}]} -eq 1 ]]
        then
            status="OK"
            ok=1
        fi
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message"
        exit 2
    elif [[ $ok -eq 1 ]]
    then
        echo "OK: All (${#psu_status[@]}) PSUs are healthy"
        exit 0
    else
        echo "Unknown: PSUs Status not found"
        exit 3
    fi

# FAN Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "fanstatus" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.4.1.2 | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.4.1.1 |  tr '\n' ' '))
    declare -a fan_status=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.4.1.3 | tr '\n' ' '))
    
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Check not supported"
        exit 3
    fi

    crit=0
    ok=0

    for line in ${ids[@]}
        do
        if [[ ${fan_status[${c}]} -ne 1 ]]
        then
            status="CRIT"
            crit=1
            status_message="$status_message FAN${ids[c]} $status"
        elif [[ ${fan_status[${c}]} -eq 1 ]]
        then
            status="OK"
            ok=1
        fi
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message"
        exit 2
    elif [[ $ok -eq 1 ]]
    then
        echo "OK: All (${#fan_status[@]}) Fans are healthy"
        exit 0
    else
        echo "Unknown: Fan Status not found"
        exit 3
    fi
    
# Controller Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "controller" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.2.1.5 | tr -d '"' | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.2.1.1 | tr -d '"' |  tr '\n' ' '))
    declare -a ctrl_status=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.2.1.2 | tr -d '"' | tr '\n' ' '))
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Check not supported"
        exit 3
    fi

    crit=0
    ok=0

    for line in ${ids[@]}
        do
        if [[ ${ctrl_status[${c}]} -ne 1 ]]
        then
            status="CRIT"
            crit=1
            status_message="$status_message CTRL${ids[c]}=$status"
        elif [[ ${ctrl_status[${c}]} -eq 1 ]]
        then
            status="OK"
            ok=1
        fi
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message"
        exit 2
    elif [[ $ok -eq 1 ]]
    then
        echo "OK: All (${#ctrl_status[@]}) Controllers are healthy"
        exit 0
    else
        echo "Unknown: Fan Status not found"
        exit 3
    fi

# Enclosure Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "enclosure" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.6.1.2 | tr -d '"'| tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.6.1.1 | tr -d '"' |  tr '\n' ' '))
    declare -a enc_status=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.6.1.4 | tr '\n' ' '))

    c=0
    if [ "$ids" = "No" ]
    then
        echo "Check not supported"
        exit 3
    fi

    crit=0
    ok=0

    for line in ${ids[@]}
        do
        if [[ ${enc_status[${c}]} -ne 1 ]]
        then
            status="CRIT"
            crit=1
            status_message="$status_message ENCL_${nums[c]}=$status"
        elif [[ ${enc_status[${c}]} -eq 1 ]]
        then
            status="OK"
            ok=1
        fi
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message"
        exit 2
    elif [[ $ok -eq 1 ]]
    then
        echo "OK: All (${#enc_status[@]}) Enclosures are healthy"
        exit 0
    else
        echo "Unknown: Fan Status not found"
        exit 3
    fi

# BBU Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "bbustatus" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.5.1.2 | tr -d '"' | tr '\n' ' '))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.5.1.1 | tr -d '"' |  tr '\n' ' '))
    declare -a bbu_status=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.5.1.3 | tr '\n' ' '))
    

    c=0
    if [ "$ids" = "No" ]
    then
        echo "Check not supported"
        exit 3
    fi

    crit=0
    ok=0

    for line in ${ids[@]}
        do
        if [[ ${bbu_status[${c}]} -ne 1 ]]
        then
            status="CRIT"
            crit=1
            status_message="$status_message BBU${ids[c]}=$status"
        elif [[ ${bbu_status[${c}]} -eq 1 ]]
        then
            status="OK"
            ok=1
        fi
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message"
        exit 2
    elif [[ $ok -eq 1 ]]
    then
        echo "OK: All (${#bbu_status[@]}) Back. Battery Units are healthy"
        exit 0
    else
        echo "Unknown: BBU Status not found"
        exit 3
    fi

# Uptime Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "uptime" ]; then
    UPTIME=$($snmpwalk_cmd .1.3.6.1.2.1.1.3.0)
    [ -n "$original_ifs" ] && original_ifs=$IFS
    IFS=':' read -r days hours minutes seconds <<< "$UPTIME"
    [ -n "$original_ifs" ] && IFS=$original_ifs || unset IFS
    # Get the current date and time
    current_time_s=$(date +%s)
    uptime_s=$(echo "$days*86400 + $hours*3600 + $minutes*60 + $seconds" | bc)
    uptime_s=$(printf '%.0f' $uptime_s)
    start_time_s=$(echo "$current_time_s - $uptime_s" | bc)
    # Calculate the start time by subtracting the uptime from the current time
    start_time=$(date -d "@$start_time_s" +"%Y-%m-%d %H:%M:%S")
    # Format the uptime duration
    uptime_str="${days} days ${hours} hours ${minutes} minutes"

    # Print the result
    echo "Up since $start_time, Uptime: $uptime_str"
    exit 0

# Memory Usage ---------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "memuse" ]; then
    declare -a nums=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.2.1.5 | tr -d '"' ))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.2.1.1 | tr -d '"' | tr '\n' ' '))
    declare -a memusage=($($snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.5.2.1.9 ))
    
    c=0
    if [ "$ids" = "No" ]
    then
        echo "Unknown: Check not supported"
        exit 3
    fi

    status_message=""
    crit=0
    warn=0
    ok=0

    for line in ${ids[@]}
        do
        perfdata="$perfdata MEM_${ids[c]}=$memusage;$strWarning;$strCritical"
        if [[ ${cpu[${c}]} -gt $strCritical  ]]
        then
            status="CRIT"
            crit=1
        elif [[ ${cpu[${c}]} -gt $strWarning  ]]
        then
            status="WARN"
            warn=1
        else
            status="OK"
            ok=1
        fi
        status_message="$status_message $status: Memory Ctrl ${ids[c]} ${memusage[${c}]}% used;"
        let c++
    done

    if [[ $crit -eq 1 ]]
    then
        echo "Critical:$status_message |$perfdata"
        exit 2
    elif [[ $warn -eq 1 ]]
    then
        echo "Warning:$status_message |$perfdata"
        exit 1
    elif [[ $ok -eq 1 ]]
    then
        echo "OK:$status_message |$perfdata"
        exit 0
    else
        echo "Unknown: Memory Status not found"
        exit 3
    fi

# IOPS Status ----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "iops" ]; then
    declare -a luns=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.23.4.8.1.2 | tr -d '"' | tr '\n' ' ' | sed 's/\"/ /g'))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.21.4.1.1 | tr -d '"' | tr '\n' ' '))
    declare -a ios=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.21.4.1.3 | tr '\n' ' '))
    
    c=0
    for line in ${ids[@]}
    do
        perfdata="$perfdata ${luns[c]}=${ios[c]};$strWarning;$strCritical"
        sum=$((sum+${ios[c]}))
        let c++
    done
    echo "IOPS: $sum|All=$sum $perfdata"
    exit 0

# Traffic Status (per LUN) ----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "luntraffic" ]; then
    declare -a luns=($(eval $snmpwalk_cmd  .1.3.6.1.4.1.34774.4.1.23.4.8.1.2 | tr -d '"' | tr '\n' ' ' | sed 's/\"/ /g'))
    declare -a ids=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.21.3.1.1 | tr '\n' ' '))
    declare -a traf=($(eval $snmpwalk_cmd .1.3.6.1.4.1.34774.4.1.21.3.1.8 | tr '\n' ' '))
    c=0
    for line in ${ids[@]}
    do
        perfdata="$perfdata ${luns[c]}=${traf[c]}"
        sum=$((sum+${traf[c]}))
        let c++
    done
    echo "Agg. Traffic: $sum MB/s|All=$sum $perfdata"
    exit 0

# Latencystatus ----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "latency" ]; then
    declare -a luns=($(eval $snmpwalk_cmd   .1.3.6.1.4.1.34774.4.1.23.4.8.1.2 | tr '\n' ' ' | sed 's/\"/ /g'))
    declare -a ids=($(eval $snmpwalk_cmd  .1.3.6.1.4.1.34774.4.1.21.4.1.1 | tr '\n' ' '))
    declare -a lat=($(eval $snmpwalk_cmd    .1.3.6.1.4.1.34774.4.1.21.4.1.13 | tr '\n' ' '))
    c=0
    for line in ${ids[@]}
        do
        perfdata="$perfdata ${luns[c]}=${lat[c]};$strWarning;$strCritical"
        if [[ ${lat[${c}]} -gt $strCritical  ]]
        then
        status="CRIT"
        crit="$crit ${luns[c]} ${lat[c]}µs"
        elif [[ ${lat[${c}]} -gt $strWarning  ]]
        then
        status="WARN"
        warn="$warn ${luns[c]} ${lat[c]}µs"
        else
        status="OK"
        ok="$ok ${luns[c]} ${lat[c]}µs"
        fi
    let c++
    done
    if [ "$status" == "CRIT" ]
    then
    echo "Critical: $crit|$perfdata"
    exit 2
    elif [ "$status" == "WARN" ]
    then
    echo "Warning: $warn|$perfdata"
    exit 1
    elif [ "$status" == "OK" ]
    then
    echo "OK|$perfdata"
    exit 0
    else
    echo "No Performance Data"
    exit 0
    fi

#----------------------------------------------------------------------------------------------------------------------------------------------------
else
        echo -e "\nUnknown Part!" && exit "3"
fi
exit 0

