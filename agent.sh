#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
version="0.0.1"
if [ -f /etc/execute_autoheal/token.conf ]
then
	auth=($(cat /etc/execute_autoheal/token.conf))
else
	echo "Error: File /etc/execute_autoheal/token.conf is missing."
	exit 1
fi
API_ENDPOINT=""

function prep ()
{
	echo "$1" | sed -e 's/^ *//g' -e 's/ *$//g' | sed -n '1 p'
}
function base ()
{
	echo "$1" | tr -d '\n' | base64 | tr -d '=' | tr -d '\n' | sed 's/\//%2F/g' | sed 's/\+/%2B/g'
}
function int ()
{
	echo ${1/\.*}
}
function num ()
{
	case $1 in
	    ''|*[!0-9\.]*) echo 0 ;;
	    *) echo $1 ;;
	esac
}
version=$(prep "$version")
uptime=$(prep $(int "$(cat /proc/uptime | awk '{ print $1 }')"))
sessions=$(prep "$(who | wc -l)")
processes=$(prep "$(ps axc | wc -l)")
processes_array="$(ps axc -o uname:12,pcpu,rss,cmd --sort=-pcpu,-rss --noheaders --width 120)"
processes_array="$(echo "$processes_array" | grep -v " ps$" | sed 's/ \+ / /g' | sed '/^$/d' | tr "\n" ";")"
file_handles=$(prep $(num "$(cat /proc/sys/fs/file-nr | awk '{ print $1 }')"))
file_handles_limit=$(prep $(num "$(cat /proc/sys/fs/file-nr | awk '{ print $3 }')"))
os_kernel=$(prep "$(uname -r)")

if ls /etc/*release > /dev/null 2>&1
then
	os_name=$(prep "$(cat /etc/*release | grep '^PRETTY_NAME=\|^NAME=\|^DISTRIB_ID=' | awk -F\= '{ print $2 }' | tr -d '"' | tac)")
fi

if [ -z "$os_name" ]
then
	if [ -e /etc/redhat-release ]
	then
		os_name=$(prep "$(cat /etc/redhat-release)")
	elif [ -e /etc/debian_version ]
	then
		os_name=$(prep "Debian $(cat /etc/debian_version)")
	fi

	if [ -z "$os_name" ]
	then
		os_name=$(prep "$(uname -s)")
	fi
fi
case $(uname -m) in
x86_64)
	os_arch=$(prep "x64")
	;;
i*86)
	os_arch=$(prep "x86")
	;;
*)
	os_arch=$(prep "$(uname -m)")
	;;
esac
cpu_name=$(prep "$(cat /proc/cpuinfo | grep 'model name' | awk -F\: '{ print $2 }')")
cpu_cores=$(prep "$(($(cat /proc/cpuinfo | grep 'model name' | awk -F\: '{ print $2 }' | sed -e :a -e '$!N;s/\n/\|/;ta' | tr -cd \| | wc -c)+1))")

if [ -z "$cpu_name" ]
then
	cpu_name=$(prep "$(cat /proc/cpuinfo | grep 'vendor_id' | awk -F\: '{ print $2 } END { if (!NR) print "N/A" }')")
	cpu_cores=$(prep "$(($(cat /proc/cpuinfo | grep 'vendor_id' | awk -F\: '{ print $2 }' | sed -e :a -e '$!N;s/\n/\|/;ta' | tr -cd \| | wc -c)+1))")
fi

cpu_freq=$(prep "$(cat /proc/cpuinfo | grep 'cpu MHz' | awk -F\: '{ print $2 }')")

if [ -z "$cpu_freq" ]
then
	cpu_freq=$(prep $(num "$(lscpu | grep 'CPU MHz' | awk -F\: '{ print $2 }' | sed -e 's/^ *//g' -e 's/ *$//g')"))
fi
ram_total=$(prep $(num "$(cat /proc/meminfo | grep ^MemTotal: | awk '{ print $2 }')"))
ram_free=$(prep $(num "$(cat /proc/meminfo | grep ^MemFree: | awk '{ print $2 }')"))
ram_cached=$(prep $(num "$(cat /proc/meminfo | grep ^Cached: | awk '{ print $2 }')"))
ram_buffers=$(prep $(num "$(cat /proc/meminfo | grep ^Buffers: | awk '{ print $2 }')"))
ram_usage=$((($ram_total-($ram_free+$ram_cached+$ram_buffers))*1024))
ram_total=$(($ram_total*1024))
swap_total=$(prep $(num "$(cat /proc/meminfo | grep ^SwapTotal: | awk '{ print $2 }')"))
swap_free=$(prep $(num "$(cat /proc/meminfo | grep ^SwapFree: | awk '{ print $2 }')"))
swap_usage=$((($swap_total-$swap_free)*1024))
swap_total=$(($swap_total*1024))
disk_total=$(prep $(num "$(($(df -P -B 1 | grep '^/' | awk '{ print $2 }' | sed -e :a -e '$!N;s/\n/+/;ta')))"))
disk_usage=$(prep $(num "$(($(df -P -B 1 | grep '^/' | awk '{ print $3 }' | sed -e :a -e '$!N;s/\n/+/;ta')))"))
disk_array=$(prep "$(df -P -B 1 | grep '^/' | awk '{ print $1" "$2" "$3";" }' | sed -e :a -e '$!N;s/\n/ /;ta' | awk '{ print $0 } END { if (!NR) print "N/A" }')")
if [ -n "$(command -v ss)" ]
then
	connections=$(prep $(num "$(ss -tun | tail -n +2 | wc -l)"))
else
	connections=$(prep $(num "$(netstat -tun | tail -n +3 | wc -l)"))
fi
nic=$(prep "$(ip route get 8.8.8.8 | grep dev | awk -F'dev' '{ print $2 }' | awk '{ print $1 }')")
if [ -z $nic ]
then
	nic=$(prep "$(ip link show | grep 'eth[0-9]' | awk '{ print $2 }' | tr -d ':')")
fi
ipv4=$(prep "$(ip addr show $nic | grep 'inet ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^127' | awk '{ print $0 } END { if (!NR) print "N/A" }')")
ipv6=$(prep "$(ip addr show $nic | grep 'inet6 ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^::' | grep -v '^0000:' | grep -v '^fe80:' | awk '{ print $0 } END { if (!NR) print "N/A" }')")
if [ -d /sys/class/net/$nic/statistics ]
then
	rx=$(prep $(num "$(cat /sys/class/net/$nic/statistics/rx_bytes)"))
	tx=$(prep $(num "$(cat /sys/class/net/$nic/statistics/tx_bytes)"))
else
	rx=$(prep $(num "$(ip -s link show $nic | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '1 p')"))
	tx=$(prep $(num "$(ip -s link show $nic | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '2 p')"))
fi
load=$(prep "$(cat /proc/loadavg | awk '{ print $1" "$2" "$3 }')")
time=$(date +%s)
stat=($(cat /proc/stat | head -n1 | sed 's/[^0-9 ]*//g' | sed 's/^ *//'))
cpu=$((${stat[0]}+${stat[1]}+${stat[2]}+${stat[3]}))
io=$((${stat[3]}+${stat[4]}))
idle=${stat[3]}

if [ -e /etc/execute_autoheal/cache ]
then
	data=($(cat /etc/execute_autoheal/cache))
	interval=$(($time-${data[0]}))
	cpu_gap=$(($cpu-${data[1]}))
	io_gap=$(($io-${data[2]}))
	idle_gap=$(($idle-${data[3]}))

	if [[ $cpu_gap > "0" ]]
	then
		load_cpu=$(((1000*($cpu_gap-$idle_gap)/$cpu_gap+5)/10))
	fi

	if [[ $io_gap > "0" ]]
	then
		load_io=$(((1000*($io_gap-$idle_gap)/$io_gap+5)/10))
	fi

	if [[ $rx > ${data[4]} ]]
	then
		rx_gap=$(($rx-${data[4]}))
	fi

	if [[ $tx > ${data[5]} ]]
	then
		tx_gap=$(($tx-${data[5]}))
	fi
fi
echo "$time $cpu $io $idle $rx $tx" > /etc/execute_autoheal/cache
rx_gap=$(prep $(num "$rx_gap"))
tx_gap=$(prep $(num "$tx_gap"))
load_cpu=$(prep $(num "$load_cpu"))
load_io=$(prep $(num "$load_io"))
ping_eu=$(prep $(num "$(ping -c 2 -w 2 ping-eu.netweak.com | grep rtt | cut -d'/' -f4 | awk '{ print $3 }')"))
ping_us=$(prep $(num "$(ping -c 2 -w 2 ping-us.netweak.com | grep rtt | cut -d'/' -f4 | awk '{ print $3 }')"))
ping_as=$(prep $(num "$(ping -c 2 -w 2 ping-as.netweak.com | grep rtt | cut -d'/' -f4 | awk '{ print $3 }')"))
if [ -f /var/log/mongodb/mongod.log ]; then
    logs=$(tail -n 100 /var/log/mongodb/mongod.log)
fi
if [ ! -f sent_logs.txt ]; then
    touch sent_logs.txt
fi
new_logs=$(grep -Fxv -f sent_logs.txt <<< "$logs")
data_post="{
    \"token\": \"${auth[0]}\",
    \"data\": {
        \"version\": \"$version\",
        \"uptime\": \"$uptime\",
        \"sessions\": \"$sessions\",
        \"processes\": \"$processes\",
        \"processes_array\": \"$processes_array\",
        \"file_handles\": \"$file_handles\",
        \"file_handles_limit\": \"$file_handles_limit\",
        \"os_kernel\": \"$os_kernel\",
        \"os_name\": \"$os_name\",
        \"os_arch\": \"$os_arch\",
        \"cpu_name\": \"$cpu_name\",
        \"cpu_cores\": \"$cpu_cores\",
        \"cpu_freq\": \"$cpu_freq\",
        \"ram_total\": \"$ram_total\",
        \"ram_usage\": \"$ram_usage\",
        \"swap_total\": \"$swap_total\",
        \"swap_usage\": \"$swap_usage\",
        \"disk_array\": \"$disk_array\",
        \"disk_total\": \"$disk_total\",
        \"disk_usage\": \"$disk_usage\",
        \"connections\": \"$connections\",
        \"nic\": \"$nic\",
        \"ipv4\": \"$ipv4\",
        \"ipv6\": \"$ipv6\",
        \"rx\": \"$rx\",
        \"tx\": \"$tx\",
        \"rx_gap\": \"$rx_gap\",
        \"tx_gap\": \"$tx_gap\",
        \"load\": \"$load\",
        \"load_cpu\": \"$load_cpu\",
        \"load_io\": \"$load_io\",
        \"ping_eu\": \"$ping_eu\",
        \"ping_us\": \"$ping_us\",
        \"ping_as\": \"$ping_as\",
		\"logs\": \"$new_logs\"
    }
}"
if [ -n "$(command -v timeout)" ]
then
	timeout -s SIGKILL 30 wget -q -o /dev/null -O /etc/execute_autoheal/log/agent.log -T 25 --header "Content-Type: application/json" --post-data "$data_post" --no-check-certificate "$API_ENDPOINT/playground/report"
else
	wget -q -o /dev/null -O /etc/execute_autoheal/log/agent.log -T 25 --header='Content-Type: application/json' --post-data "$data_post" --no-check-certificate "$API_ENDPOINT/playground/report"
	wget_pid=$!
	wget_counter=0
	wget_timeout=30

	while kill -0 "$wget_pid" && (( wget_counter < wget_timeout ))
	do
	    sleep 1
	    (( wget_counter++ ))
	done

	kill -0 "$wget_pid" && kill -s SIGKILL "$wget_pid"
fi
exit 1

