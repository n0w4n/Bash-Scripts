#!/usr/bin/env bash

# created by n0w4n

# Script to clean up installed packages after an exercise
# Handy for a system that is without VM snapshot ability
# The script will lookup a list of all the packages installed from a certain point
# Then it will purge some/all packages (after confirming with user)
# Feel free to use and alter this script

main () {
	# Creates an optionmenu
	echo -e "\nOptionsmenu"
	echo -e "-----------"
	PS3='Please enter your choice: '
	options=("Show list installed packages" "Remove a single package" "Remove all packages" "Quit")
	select opt in "${options[@]}"
	do
	    case $opt in
	    	"Show list installed packages")
				verification
				showList
				main
				;;
	        "Remove a single package")
				verification
	            optionRemoveSingle
	            main
	            ;;
	        "Remove all packages")
				verification
	            optionRemoveAll
	            main
	            ;;
	        "Quit")
	            cleanUp
	            exit 0
	            ;;
	        *) echo "invalid option $REPLY";;
	    esac
	done
}

verification () {
	# Check if there is a remaining list and cleaning before start operation (false positives)
	if [[ -f /tmp/verifiedPackages ]]; then
		rm -f /tmp/verifiedPackages
	fi

	# Create a variable with a list of newly installed packages
	listPackages=$(cat /var/log/apt/history.log | \grep 'Commandline: apt install' | grep -v '\./' | awk '{print $4}' | sort -u)

	# Verifies if package is truly installed on system
	for p in $listPackages
	do
		dpkg -s ${p} 2>/dev/null | \grep 'Status:.*installed' &>/dev/null
		if [[ $? -eq 0 ]]; then
			echo "${p}" >> /tmp/verifiedPackages
		fi
	done

	# Checks if there are new packages installed by user.
	# If none this will output so and end the script
	if [[ ! -f /tmp/verifiedPackages ]]; then
		echo -e "\n[!] There are no newly installed packages\n"
		sleep 2
		clear
		main
	fi
}

showList () {
	# Set a counter at one
	local count=1

	# List all newly installed packages by date
	clear
	echo -e "\nList of installed packages"
	echo -e "--------------------------"
	for p in $(cat /tmp/verifiedPackages)
	do
		dateInstall=$(cat /var/log/apt/history.log | \grep -B1 "Commandline: apt install ${p}" | \grep Start-Date | awk '{print $2}' | sort -u)
		echo -e "[$(( count ++ ))] Package ${p} is installed on ${dateInstall}"
	done
}

optionRemoveSingle () {
	# Set a counter at zero
	local count=0
	numberPackages=$(cat /tmp/verifiedPackages)
	numberItems=$(echo "$numberPackages" | wc -l)

	read -p 'Give number of package: ' givenOption
	if [[ $givenOption > $numberItems ]]; then
		echo "[!] Invalid option"
	else
		for p in $numberItems
		do
			(( count ++ ))
			echo "$count"
			if [[ $count == $numberPackage ]]; then
				sudo apt purge ${p} -y &>/dev/null
				echo "[-] Package '${p}' is uninstalled"
			else
				echo "[!] Invalid option"
				break
			fi
		done
	fi
	sleep 2
	clear
	showList
	main
}

optionRemoveAll () {
	for p in $(cat /tmp/verifiedPackages)
	do
		sudo apt purge ${p} -y &>/dev/null
		echo -e "[-] Package '${p}' is uninstalled"
	done
	sleep 2
	clear
	main
}

cleanUp () {
	# Clean up remaining objects
	echo -e "[-] Cleaning up"
	rm -f /tmp/verifiedPackages
	sudo apt autoremove -y &>/dev/null
	sudo apt clean &>/dev/null
	echo -e "[-] Done, exiting"
}

installTmp () {
	# For testing purposes only
  # This will install 3 linux calculators to test this script
	apps="calc tiemu xcas"
	for a in $apps
	do
		echo "[-] Installing ${a}"
		sudo apt install ${a} -y &>/dev/null
	done
	cleanUp
	exit 0
}

clear
#installTmp
main
