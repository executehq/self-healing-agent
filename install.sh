#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
curl https://gist.githubusercontent.com/ayshptk/45f7d613d5d4ae0ea44a3a91ebf6d003/raw/6900c75786f4db35d2e21d5e80d384a6d35ddb7b/logo.txt
echo -e "|\n|   Execute Autoheal Installer\n|   ===================\n|"
if [ $(id -u) != "0" ];
then
	echo -e "|   Error: You need to be root to install the Execute Autoheal agent\n|"
	echo -e "|          The agent itself will NOT be running as root but instead under its own non-privileged user\n|"
	exit 1
fi

token={{ACCESS_TOKEN}}
playground_api_url=""

if [ -z "$token" ]
then
	echo -e "|   Error: Execute Autoheal agent token is required\n|"
	echo -e "|   Usage: bash $token 'token'\n|"
	exit 1
fi

curl -X POST "$playground_api_url/playground/verifyAgentInstallation" -H "Content-Type: application/json" -d '{"accessToken": "'"$token"'"}' > /dev/null 2>&1

if [ ! -n "$(command -v crontab)" ]
then
	echo "|" && read -p "|   Crontab is required and could not be found. Do you want to install it? [Y/n] " input_variable_install
	if [ -z $input_variable_install ] || [ $input_variable_install == "Y" ] || [ $input_variable_install == "y" ]
	then
		if [ -n "$(command -v apt-get)" ]
		then
			echo -e "|\n|   Notice: Installing required package 'cron' via 'apt-get'"
		    apt-get -y update
		    apt-get -y install cron
		elif [ -n "$(command -v yum)" ]
		then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'yum'"
		    yum -y install cronie
		    
		    if [ ! -n "$(command -v crontab)" ]
		    then
		    	echo -e "|\n|   Notice: Installing required package 'vixie-cron' via 'yum'"
		    	yum -y install vixie-cron
		    fi
		elif [ -n "$(command -v pacman)" ]
		then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'pacman'"
		    pacman -S --noconfirm cronie
		fi
	fi
	
	if [ ! -n "$(command -v crontab)" ]
	then
	    echo -e "|\n|   Error: Crontab is required and could not be installed\n|"
	    exit 1
	fi	
fi
if [ -z "$(ps -Al | grep cron | grep -v grep)" ]
then
	echo "|" && read -p "|   Cron is available but not running. Do you want to start it? [Y/n] " input_variable_service
	if [ -z $input_variable_service ] || [ $input_variable_service == "Y" ] || [ $input_variable_service == "y" ]
	then
		if [ -n "$(command -v apt-get)" ]
		then
			echo -e "|\n|   Notice: Starting 'cron' via 'service'"
			service cron start
		elif [ -n "$(command -v yum)" ]
		then
			echo -e "|\n|   Notice: Starting 'crond' via 'service'"
			chkconfig crond on
			service crond start
		elif [ -n "$(command -v pacman)" ]
		then
			echo -e "|\n|   Notice: Starting 'cronie' via 'systemctl'"
		    systemctl start cronie
		    systemctl enable cronie
		fi
	fi
	
	if [ -z "$(ps -Al | grep cron | grep -v grep)" ]
	then
		echo -e "|\n|   Error: Cron is available but could not be started\n|"
		exit 1
	fi
fi
if [ -f /etc/execute_autoheal/agent.sh ]
then
	rm -Rf /etc/execute_autoheal

	if id -u execute_autoheal >/dev/null 2>&1
	then
		(crontab -u execute_autoheal -l | grep -v "/etc/execute_autoheal/agent.sh") | crontab -u execute_autoheal - && userdel execute_autoheal
	else
		(crontab -u root -l | grep -v "/etc/execute_autoheal/agent.sh") | crontab -u root -
	fi
fi
mkdir -p /etc/execute_autoheal
mkdir -p /etc/execute_autoheal/log
echo -e "|   Downloading agent.sh to /etc/execute_autoheal\n|\n|   + $(wget -nv -o /dev/stdout -O /etc/execute_autoheal/agent.sh --no-check-certificate https://gist.githubusercontent.com/ayshptk/eeb2f32b9ff670a42d55231f8ddc15c0/raw/20670995c1d30a1a6bfdef5fd51ceabc30939d1d/agenst.sh)"
if [ -f /etc/execute_autoheal/agent.sh ]
then
	echo "$token" > /etc/execute_autoheal/token.conf
    if [ -f /etc/execute_autoheal/token.conf ]
    then
        auth=($(cat /etc/execute_autoheal/token.conf))
    else
        echo "Error: File /etc/execute_autoheal/token.conf is missing."
        exit 1
    fi
	useradd execute_autoheal -r -d /etc/execute_autoheal -s /bin/false
	chown -R execute_autoheal:execute_autoheal /etc/execute_autoheal && chmod -R 700 /etc/execute_autoheal
	chmod +s `type -p ping`
	crontab -u execute_autoheal -l 2>/dev/null | { cat; echo "* * * * * bash /etc/execute_autoheal/agent.sh > /etc/execute_autoheal/log/cron.log 2>&1"; } | crontab -u execute_autoheal -
	echo -e "|\n|   Success: The execute_autoheal agent has been installed\n|"
	if [ -f $0 ]
	then
		rm -f $0
	fi
else
	echo -e "|\n|   Error: The execute_autoheal agent could not be installed\n|"
fi