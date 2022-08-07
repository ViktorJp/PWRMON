#!/bin/sh
#
# PWRMON v0.1b3 - Asus-Merlin Tesla Powerwall Monitor by Viktor Jaep, 2022
#
# PWRMON is a shell script that provides near-realtime stats about your Tesla Powerwall/Solar environment. This utility
# will show all the current electrical loads being generated or consumed by your solar system, the grid, your home and
# your Powerwall(s). Electrical transmission flows are accurately being depicted using >> and << types of arrows, as
# electricity moves between your solar, to/from your batteries, to/from the grid and to your home. In the event of a
# electrical grid outage, PWRMON will calculate your estimated remaining runtime left on your batteries based on the
# amount of kW being consumed by your home.
#
# Instead of having to find this information on various different web pages or apps, this tool was built to bring all this
# info together in one stat dashboard.  Having a 'system' dashboard showing current solar, grid, home and powerwall stats
# would compliment other dashboard-like scripts greatly (like RTRMON or VPNMON-R2), sitting side-by-side in their own SSH
# windows to give you everything you need to know with a glance at your screen.
#
# Please use the 'pwrmon.sh -setup' to configure the necessary parameters that match your environment the best!
#
# -------------------------------------------------------------------------------------------------------------------------
# Shellcheck exclusions
# -------------------------------------------------------------------------------------------------------------------------
# shellcheck disable=SC2034
# shellcheck disable=SC3037
# shellcheck disable=SC2162
# shellcheck disable=SC3045
# shellcheck disable=SC2183
# shellcheck disable=SC2086
# shellcheck disable=SC3014
# shellcheck disable=SC2059
# shellcheck disable=SC2002
# shellcheck disable=SC2004
# shellcheck disable=SC3028
# shellcheck disable=SC2140
# shellcheck disable=SC3046
# shellcheck disable=SC1090
#
# -------------------------------------------------------------------------------------------------------------------------
# System Variables (Do not change beyond this point or this may change the programs ability to function correctly)
# -------------------------------------------------------------------------------------------------------------------------
Version=0.1b3
Beta=1
LOGFILE="/jffs/addons/pwrmon.d/pwrmon.log"          # Logfile path/name that captures important date/time events - change
APPPATH="/jffs/scripts/pwrmon.sh"                   # Path to the location of pwrmon.sh
CFGPATH="/jffs/addons/pwrmon.d/pwrmon.cfg"          # Path to the location of pwrmon.cfg
DLVERPATH="/jffs/addons/pwrmon.d/version.txt"       # Path to downloaded version from the source repository
cookie_file="/jffs/scripts/pwrmon.cookies"
NextPage=1
UpdateNotify=0
FromUI=0

#Default Values
Interval=10
email="user@domain.com"
password="ABCDE"
gatewayip="192.168.1.150"
numpowerwalls=2
maxsolargen=7
maxhomeelecload=24

# Color variables
CBlack="\e[1;30m"
InvBlack="\e[1;40m"
CRed="\e[1;31m"
InvRed="\e[1;41m"
CGreen="\e[1;32m"
InvGreen="\e[1;42m"
CDkGray="\e[1;90m"
InvDkGray="\e[1;100m"
InvLtGray="\e[1;47m"
CYellow="\e[1;33m"
InvYellow="\e[1;43m"
CBlue="\e[1;34m"
InvBlue="\e[1;44m"
CMagenta="\e[1;35m"
CCyan="\e[1;36m"
InvCyan="\e[1;46m"
CWhite="\e[1;37m"
InvWhite="\e[1;107m"
CClear="\e[0m"

# -------------------------------------------------------------------------------------------------------------------------
# Functions
# -------------------------------------------------------------------------------------------------------------------------

# Logo is a function that displays the PWRMON script name in a cool ASCII font
logo () {
  echo -e "${CYellow}      ____ _       ______  __  _______  _   __"
  echo -e "     / __ \ |     / / __ \/  |/  / __ \/ | / /  ${CGreen}v$Version${CYellow}"
  echo -e "    / /_/ / | /| / / /_/ / /|_/ / / / /  |/ /  ${CRed}(S)${CGreen}etup${CYellow}"
  echo -e "   / ____/| |/ |/ / _, _/ /  / / /_/ / /|  /   ${CRed}(N)${CGreen}ext Page ($NextPage/2)${CYellow}"
  echo -e "  /_/     |__/|__/_/ |_/_/  /_/\____/_/ |_/    ${CRed}(E)${CGreen}xit${CClear}"
}

# -------------------------------------------------------------------------------------------------------------------------

# LogoNM is a function that displays the PWRMON script name in a cool ASCII font sans menu
logoNM () {
  echo -e "${CYellow}      ____ _       ______  __  _______  _   __"
  echo -e "     / __ \ |     / / __ \/  |/  / __ \/ | / /  ${CGreen}v$Version${CYellow}"
  echo -e "    / /_/ / | /| / / /_/ / /|_/ / / / /  |/ /"
  echo -e "   / ____/| |/ |/ / _, _/ /  / / /_/ / /|  /"
  echo -e "  /_/     |__/|__/_/ |_/_/  /_/\____/_/ |_/"
}

# -------------------------------------------------------------------------------------------------------------------------

# promptyn takes input for Y/N questions
promptyn () {   # No defaults, just y or n
  while true; do
    read -p "[y/n]? " -n 1 -r yn
      case "${yn}" in
        [Yy]* ) return 0 ;;
        [Nn]* ) return 1 ;;
        * ) echo -e "\nPlease answer y or n.";;
      esac
  done
}

# -------------------------------------------------------------------------------------------------------------------------

# Preparebar and Progressbar is a script that provides a nice progressbar to show script activity
preparebar() {
  # $1 - bar length
  # $2 - bar char
  #printf "\n"
  barlen=$1
  barspaces=$(printf "%*s" "$1")
  barchars=$(printf "%*s" "$1" | tr ' ' "$2")
}

# Had to make some mods to the variables being passed, and created an inverse colored progress bar
progressbar() {
  # $1 - number (-1 for clearing the bar)
  # $2 - max number
  # $3 - system name
  # $4 - measurement
  # $5 - standard/reverse progressbar
  # $6 - alternate display values
  insertspc=" "

  if [ $1 -eq -1 ]; then
    printf "\r  $barspaces\r"
  else
    barch=$(($1*barlen/$2))
    barsp=$((barlen-barch))
    progr=$((100*$1/$2))

    if [ ! -z $6 ]; then AltNum=$6; else AltNum=$1; fi

    if [ "$5" == "Standard" ]; then
      if [ $progr -lt 60 ]; then
        printf "${InvGreen}${CWhite}$insertspc${CClear}${CGreen}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      elif [ $progr -gt 59 ] && [ $progr -lt 85 ]; then
        printf "${InvYellow}${CBlack}$insertspc${CClear}${CYellow}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      else
        printf "${InvRed}${CWhite}$insertspc${CClear}${CRed}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      fi
    elif [ "$5" == "Reverse" ]; then
      if [ $progr -lt 35 ]; then
        printf "${InvRed}${CWhite}$insertspc${CClear}${CRed}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      elif [ $progr -gt 35 ] && [ $progr -lt 85 ]; then
        printf "${InvYellow}${CBlack}$insertspc${CClear}${CYellow}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      else
        printf "${InvGreen}${CWhite}$insertspc${CClear}${CGreen}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      fi
    fi
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# updatecheck is a function that downloads the latest update version file, and compares it with what's currently installed
updatecheck () {

  # Download the latest version file from the source repository
  curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/PWRMON/master/version.txt" -o "/jffs/addons/pwrmon.d/version.txt"

  if [ -f $DLVERPATH ]
    then
      # Read in its contents for the current version file
      DLVersion=$(cat $DLVERPATH)

      # Compare the new version with the old version and log it
      if [ "$Beta" == "1" ]; then   # Check if Dev/Beta Mode is enabled and disable notification message
        UpdateNotify=0
      elif [ "$DLVersion" != "$Version" ]; then
        UpdateNotify="Update available: v$Version -> v$DLVersion"
        echo -e "$(date) - PWRMON - A new update (v$DLVersion) is available to download" >> $LOGFILE
      else
        UpdateNotify=0
      fi
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vlogs is a function that calls the nano text editor to view the PWRMON log file
vlogs() {

export TERM=linux
nano $LOGFILE

}

# -------------------------------------------------------------------------------------------------------------------------

# vconfig is a function that guides you through the various configuration options for PWRMON
vconfig () {

  if [ -f $CFGPATH ]; then #Making sure file exists before proceeding
    source $CFGPATH

    while true; do
      clear
      logoNM
      echo ""
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${CGreen}Configuration Utility Options"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${InvDkGray}${CWhite} 1 ${CClear}${CCyan}: Refresh Interval (sec)      :"${CGreen}$Interval
      echo -e "${InvDkGray}${CWhite} 2 ${CClear}${CCyan}: Tesla Gateway Email Address :"${CGreen}$email
      echo -e "${InvDkGray}${CWhite} 3 ${CClear}${CCyan}: Tesla Gateway Password      :"${CGreen}$password
      echo -e "${InvDkGray}${CWhite} 4 ${CClear}${CCyan}: Tesla Gateway IP Address    :"${CGreen}$gatewayip
      echo -e "${InvDkGray}${CWhite} 5 ${CClear}${CCyan}: Total # of Powerwalls       :"${CGreen}$numpowerwalls
      echo -e "${InvDkGray}${CWhite} 6 ${CClear}${CCyan}: Max Solar Generation (kW)   :"${CGreen}$maxsolargen
      echo -e "${InvDkGray}${CWhite} 7 ${CClear}${CCyan}: Max Home Elec Load (kW)     :"${CGreen}$maxhomeelecload
      echo -e "${InvDkGray}${CWhite} | ${CClear}"
      echo -e "${InvDkGray}${CWhite} s ${CClear}${CCyan}: Save & Exit"
      echo -e "${InvDkGray}${CWhite} e ${CClear}${CCyan}: Exit & Discard Changes"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo ""
      printf "Selection: "
      read -r ConfigSelection

      # Execute chosen selections
          case "$ConfigSelection" in

            1) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}1. How many seconds would you like to use to refresh your PW stats?"
              echo -e "${CYellow}(Default = 10)${CClear}"
              read -p 'Interval (seconds): ' Interval1
              Interval=$Interval1
            ;;

            2) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}2. What is your Tesla Gateway Customer Email Address?"
              echo -e "${CYellow}(format required: name@domain.com)${CClear}"
              read -p 'Email Address: ' email1
              email=$email1
            ;;

            3) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}3. What is your Tesla Gateway Customer Password? Please note, this"
              echo -e "${CCyan}password is typically a 5-character upper-case alpha password that"
              echo -e "${CCyan}can be found using the last 5 characters of your Gateway Serial"
              echo -e "${CCyan}Number located behind the front cover of your unit."
              echo -e "${CYellow}(Locate your Tesla Gateway password)${CClear}"
              read -p 'Password: ' password1
              password=$password1
            ;;

            4) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}4. What is the local IP address of your Telsa Gateway?"
              echo -e "${CYellow}(format required = #.#.#.#, ex: 192.168.45.22)${CClear}"
              read -p 'Local IP Address: ' gatewayip1
              gatewayip=$gatewayip1
            ;;

            5) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}5. How many Tesla Powerwalls do you currently have configured?"
              echo -e "${CYellow}(Default = 2)${CClear}"
              read -p 'Number of Powerwalls: ' numpowerwalls1
              numpowerwalls=$numpowerwalls1
            ;;

            6) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}6. What is the maximum power (kW) your solar panels generate?"
              echo -e "${CCyan}Please round up or down to the nearest whole number."
              echo -e "${CYellow}(Default = 7)${CClear}"
              read -p 'Max Solar Power: ' maxsolargen1
              maxsolargen=$maxsolargen1
            ;;

            7) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}7. What is the maximum power load that your home can consume?"
              echo -e "${CCyan}This is calculated by looking at your home breaker size, for"
              echo -e "${CCyan}example, if your main breaker is 200a x 120v = 24,000w (24kW)"
              echo -e "${CYellow}(Default = 24)${CClear}"
              read -p 'Max Home Power: ' maxhomeelecload1
              maxhomeelecload=$maxhomeelecload1
            ;;

            [Ss]) # -----------------------------------------------------------------------------------------
              echo ""
              { echo 'Interval='$Interval
                echo 'email="'"$email"'"'
                echo 'password="'"$password"'"'
                echo 'gatewayip="'"$gatewayip"'"'
                echo 'numpowerwalls='$numpowerwalls
                echo 'maxsolargen='$maxsolargen
                echo 'maxhomeelecload='$maxhomeelecload
              } > $CFGPATH
              echo ""
              echo -e "${CGreen}Please restart PWRMON to apply your changes..."
              echo -e "$(date) - PWRMON - Successfully wrote a new config file" >> $LOGFILE
              sleep 3
              return
            ;;

            [Ee]) # -----------------------------------------------------------------------------------------
              return
            ;;

          esac
    done

  else
      #Create a new config file with default values to get it to a basic running state
      { echo 'Interval=10'
        echo 'email="user@domain.com"'
        echo 'password="ABCDE"'
        echo 'gatewayip="192.168.1.150"'
        echo 'numpowerwalls=2'
        echo 'maxsolargen=7'
        echo 'maxhomeelecload=24'
      } > $CFGPATH

      #Re-run pwrmon -config to restart setup process
      vconfig

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# vuninstall is a function that uninstalls and removes all traces of PWRMON from your router...
vuninstall () {
  clear
  logoNM
  echo ""
  echo -e "${CYellow}Uninstall Utility${CClear}"
  echo ""
  echo -e "${CCyan}You are about to uninstall PWRMON!  This action is irreversible."
  echo -e "${CCyan}Do you wish to proceed?${CClear}"
  if promptyn "(y/n): "; then
    echo ""
    echo -e "\n${CCyan}Are you sure? Please type 'Y' to validate you want to proceed.${CClear}"
      if promptyn "(y/n): "; then
        clear
        rm -r /jffs/addons/pwrmon.d
        rm /jffs/scripts/pwrmon.sh
        echo ""
        echo -e "\n${CGreen}PWRMON has been uninstalled...${CClear}"
        echo ""
        exit 0
      else
        echo ""
        echo -e "\n${CGreen}Exiting Uninstall Utility...${CClear}"
        sleep 1
        return
      fi
  else
    echo ""
    echo -e "\n${CGreen}Exiting Uninstall Utility...${CClear}"
    sleep 1
    return
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vupdate is a function that provides a UI to check for script updates and allows you to install the latest version...
vupdate () {
  updatecheck # Check for the latest version from source repository
  clear
  logoNM
  echo ""
  echo -e "${CYellow}Update Utility${CClear}"
  echo ""
  echo -e "${CCyan}Current Version: ${CYellow}$Version${CClear}"
  echo -e "${CCyan}Updated Version: ${CYellow}$DLVersion${CClear}"
  echo ""
  if [ "$Version" == "$DLVersion" ]
    then
      echo -e "${CGreen}No update available.  You are on the latest version!${CClear}"
      echo ""
      read -rsp $'Press any key to continue...\n' -n1 key
      return
    else
      echo -e "${CCyan}Would you like to update to the latest version?${CClear}"
      if promptyn "(y/n): "; then
        echo ""
        echo -e "${CCyan}Updating PWRMON to ${CYellow}v$DLVersion${CClear}"
        curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/PWRMON/master/pwrmon-$DLVersion.sh" -o "/jffs/scripts/pwrmon.sh" && chmod a+rx "/jffs/scripts/pwrmon.sh"
        echo ""
        echo -e "${CCyan}Update successful!${CClear}"
        echo -e "$(date) - PWRMON - Successfully updated PWRMON from v$Version to v$DLVersion" >> $LOGFILE
        echo ""
        echo -e "${CYellow}Please exit, restart and configure new options using: 'pwrmon.sh -config'.${CClear}"
        echo -e "${CYellow}NOTE: New features may have been added that require your input to take${CClear}"
        echo -e "${CYellow}advantage of its full functionality.${CClear}"
        echo ""
        read -rsp $'Press any key to continue...\n' -n1 key
        return
      else
        echo ""
        echo ""
        echo -e "${CGreen}Exiting Update Utility...${CClear}"
        sleep 1
        return
      fi
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vsetup is a function that sets up, confiures and allows you to launch PWRMON on your router...
vsetup () {

  # Check for and add an alias for PWRMON
  if ! grep -F "sh /jffs/scripts/pwrmon.sh" /jffs/configs/profile.add; then
		echo "alias pwrmon=\"sh /jffs/scripts/pwrmon.sh\" # PWRMON" >> /jffs/configs/profile.add
  fi

  while true; do
    clear
    logoNM
    echo ""
    echo -e "${CYellow}Setup Utility${CClear}" # Provide main setup menu
    echo ""
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${CGreen}Operations"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${InvDkGray}${CWhite} sc ${CClear}${CCyan}: Setup and Configure PWRMON"
    echo -e "${InvDkGray}${CWhite} fr ${CClear}${CCyan}: Force Re-install Entware Dependencies"
    echo -e "${InvDkGray}${CWhite} up ${CClear}${CCyan}: Check for latest updates"
    echo -e "${InvDkGray}${CWhite} vl ${CClear}${CCyan}: View logs"
    echo -e "${InvDkGray}${CWhite} un ${CClear}${CCyan}: Uninstall"
    echo -e "${InvDkGray}${CWhite}  e ${CClear}${CCyan}: Exit"
    echo -e "${CGreen}----------------------------------------------------------------"
    if [ "$FromUI" == "0" ]; then
      echo -e "${CGreen}Launch"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${InvDkGray}${CWhite} m1 ${CClear}${CCyan}: Launch PWRMON into Normal Monitoring Mode"
      echo -e "${InvDkGray}${CWhite} m2 ${CClear}${CCyan}: Launch PWRMON into Normal Monitoring Mode w/ Screen"
      echo -e "${CGreen}----------------------------------------------------------------"
    fi
    echo ""
    printf "Selection: "
    read -r InstallSelection

    # Execute chosen selections
        case "$InstallSelection" in

          sc) # Check for existence of entware, and if so proceed and install the timeout package, then run PWRMON -config
            clear
            if [ -f "/opt/bin/timeout" ] && [ -f "/opt/sbin/screen" ]; then
              vconfig
            else
              logoNM
              echo -e "${CYellow}Installing PWRMON...${CClear}"
              echo ""
              echo -e "${CCyan}Would you like to optionally install the CoreUtils-Timeout${CClear}"
              echo -e "${CCyan}and Screen utility? These utilities require you to have Entware${CClear}"
              echo -e "${CCyan}already installed using the AMTM tool. If Entware is present, the ${CClear}"
              echo -e "${CCyan}Timeout and Screen utilities will be downloaded and installed during${CClear}"
              echo -e "${CCyan}this setup process, and used by PWRMON.${CClear}"
              echo ""
              echo -e "${CGreen}CoreUtils-Timeout${CCyan} is a utility that provides more stability for${CClear}"
              echo -e "${CCyan}certain routers (like the RT-AC86U) which has a tendency to randomly${CClear}"
              echo -e "${CCyan}hang scripts running on this router model.${CClear}"
              echo ""
              echo -e "${CGreen}Screen${CCyan} is a utility that allows you to run SSH scripts in a standalone"
              echo -e "${CCyan}environment directly on the router itself, instead of running your"
              echo -e "${CCyan}commands or a script from a network-attached SSH client. This can"
              echo -e "${CCyan}provide greater stability due to it running from the router itself."
              echo ""
              [ -z "$(nvram get odmpid)" ] && RouterModel="$(nvram get productid)" || RouterModel="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic
              echo -e "${CCyan}Your router model is: ${CYellow}$RouterModel"
              echo ""
              echo -e "${CCyan}Install?${CClear}"
              if promptyn "(y/n): "
                then
                  if [ -d "/opt" ]; then # Does entware exist? If yes proceed, if no error out.
                    echo ""
                    echo -e "\n${CGreen}Updating Entware Packages...${CClear}"
                    echo ""
                    opkg update
                    echo ""
                    echo -e "${CGreen}Installing Entware CoreUtils-Timeout Package...${CClear}"
                    echo ""
                    opkg install coreutils-timeout
                    echo -e "${CGreen}Installing Entware Screen Package...${CClear}"
                    echo ""
                    opkg install screen
                    echo ""
                    sleep 1
                    echo -e "${CGreen}Executing PWRMON Configuration Utility...${CClear}"
                    sleep 2
                    vconfig
                  else
                    clear
                    echo -e "${CGreen}ERROR: Entware was not found on this router...${CClear}"
                    echo -e "${CGreen}Please install Entware using the AMTM utility before proceeding...${CClear}"
                    echo ""
                    sleep 3
                  fi
                else
                  echo ""
                  echo -e "\n${CGreen}Executing PWRMON Configuration Utility...${CClear}"
                  sleep 2
                  vconfig
              fi
            fi
          ;;


          fr) # Force re-install the CoreUtils timeout/screen package
            clear
            logoNM
            echo ""
            echo -e "${CYellow}Force Re-installing CoreUtils-Timeout/Screen Packages...${CClear}"
            echo ""
            echo -e "${CCyan}Would you like to optionally re-install the CoreUtils-Timeout${CClear}"
            echo -e "${CCyan}and Screen utility? These utilities require you to have Entware${CClear}"
            echo -e "${CCyan}already installed using the AMTM tool. If Entware is present, the ${CClear}"
            echo -e "${CCyan}Timeout and Screen utilities will be downloaded and installed during${CClear}"
            echo -e "${CCyan}this setup process, and used by PWRMON.${CClear}"
            echo ""
            echo -e "${CGreen}CoreUtils-Timeout${CCyan} is a utility that provides more stability for${CClear}"
            echo -e "${CCyan}certain routers (like the RT-AC86U) which has a tendency to randomly${CClear}"
            echo -e "${CCyan}hang scripts running on this router model.${CClear}"
            echo ""
            echo -e "${CGreen}Screen${CCyan} is a utility that allows you to run SSH scripts in a standalone"
            echo -e "${CCyan}environment directly on the router itself, instead of running your"
            echo -e "${CCyan}commands or a script from a network-attached SSH client. This can"
            echo -e "${CCyan}provide greater stability due to it running from the router itself."
            echo ""
            [ -z "$(nvram get odmpid)" ] && RouterModel="$(nvram get productid)" || RouterModel="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic
            echo -e "${CCyan}Your router model is: ${CYellow}$RouterModel"
            echo ""
            echo -e "${CCyan}Force Re-install?${CClear}"
            if promptyn "(y/n): "
              then
                if [ -d "/opt" ]; then # Does entware exist? If yes proceed, if no error out.
                  echo ""
                  echo -e "\n${CGreen}Updating Entware Packages...${CClear}"
                  echo ""
                  opkg update
                  echo ""
                  echo -e "${CGreen}Force Re-installing Entware CoreUtils-Timeout Package...${CClear}"
                  echo ""
                  opkg install --force-reinstall coreutils-timeout
                  echo -e "${CGreen}Force Re-installing Entware Screen Package...${CClear}"
                  echo ""
                  opkg install --force-reinstall screen
                  echo ""
                  echo -e "${CGreen}Re-install completed...${CClear}"
                  sleep 2
                else
                  clear
                  echo -e "${CGreen}ERROR: Entware was not found on this router...${CClear}"
                  echo -e "${CGreen}Please install Entware using the AMTM utility before proceeding...${CClear}"
                  echo ""
                  sleep 3
                fi
            fi
          ;;

          up)
            echo ""
            vupdate
          ;;

          m1)
            echo ""
            echo -e "\n${CGreen}Launching PWRMON into Monitor Mode...${CClear}"
            sleep 2
            sh $APPPATH -monitor
          ;;

          m2)
            echo ""
            echo -e "\n${CGreen}Launching PWRMON into Monitor Mode with Screen Utility...${CClear}"
            sleep 2
            sh $APPPATH -screen
          ;;

          vl)
            echo ""
            vlogs
          ;;

          un)
            echo ""
            vuninstall
          ;;

          [Ee])
            echo -e "${CClear}"
            exit 0
          ;;

          *)
            echo ""
            echo -e "${CRed}Invalid choice - Please enter a valid option...${CClear}"
            echo ""
            sleep 2
          ;;

        esac
  done
}

# -------------------------------------------------------------------------------------------------------------------------

do_login() {
  # Attempt to login and get an auth cookie to use

  request_json=$(jq -c -n --arg email "$email" --arg password "$password" '
    {
      "username": "customer",
      "email": $email,
      "password": $password,
      "force_sm_off": false
    }
  ')

  result=$(curl -s -k -c "$cookie_file" -X POST -H "Content-Type: application/json" -d "$request_json" "https://$gatewayip/api/login/Basic")

  auth_token=$(cat "$cookie_file" | awk '/AuthCookie/ {print $7}')
  if [ -z "$auth_token" ]; then
    echo -e "${CRed}Login failed: $result"
    echo ""
    echo -e "Please double-check your Tesla Gateway email address and password."
    echo -e "Ensure that your Tesla Gateway at: $gatewayip is on, visible and"
    echo -e "able to be reached on this network."
    echo ""
    exit 1
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

DisplayPage1 () {

#sitename="My Tesla Site Name"

  clear
  logo
  if [ "$UpdateNotify" != "0" ]; then
    echo -e "${CRed}  $UpdateNotify${CClear}"
    echo -e "${CGreen} _______________${CClear}"
  else
    echo -e "${CGreen} _______________${CClear}"
  fi
  echo -e "${CGreen}/${CRed}Tesla Powerwall${CClear}${CGreen}\__________________________________________________${CClear}"
  echo -e "                                                                      "
  echo -e "${CBlack}                             ${InvYellow}  SOLAR   ${CClear}    ${CGreen}$sitename"
  echo -e "${CYellow}                              $solar kW${CClear}"
  echo -e "${CBlack}                             ${InvYellow}  \|/____ ${CClear}"
  echo -e "${CBlack}                             ${InvYellow} --O///// ${CClear}"
  echo -e "${CBlack}                             ${InvYellow}  //////  ${CClear}"
  echo -e "${CBlack}                             ${InvYellow} //////   ${CClear}"
  echo -e "${CYellow}                                $solarshowline${CClear}"
  echo -e "${CYellow}                                $solarshowline${CClear}"
  echo -e "         ${CWhite}${InvDkGray}   GRID   ${CClear}             ${CYellow}$solarshowline             ${CBlack}${InvCyan}   HOME   ${CClear}"
  echo -e "          $grid kW              ${CYellow}$solardirection1           ${CCyan}   $home kW${CClear}"
  echo -e "         ${CWhite}${InvDkGray} _/====\_ ${CClear}             ${CYellow}$solardirection2             ${CBlack}${InvCyan}  /====\| ${CClear}"
  echo -e "         ${CWhite}${InvDkGray}  =\||/=  ${CClear}$gridshowlines${CBlack}${InvWhite}[GW]${CClear}$homeshowlines${CBlack}${InvCyan} /______\ ${CClear}"
  echo -e "         ${CWhite}${InvDkGray}    ||    ${CClear}             ${CGreen}$batterydirection1             ${CBlack}${InvCyan} | |[]| | ${CClear}"
  echo -e "         ${CWhite}${InvDkGray} ^^^^^^^^ ${CClear}             ${CGreen}$batterydirection2             ${CBlack}${InvCyan} ^^^^^^^^ ${CClear}"
  echo -e "                                ${CGreen}$batterydirection3               ${CClear}"
  echo -e "                                ${CGreen}$batterydirection4               ${CClear}"
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear}"
  echo -e "                         ${InvWhite}${CBlack}    $battery kW      ${InvDkGray}${CGreen}|${CClear}${CWhite} $battcapp %${CClear}"
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear}"
  echo -e "                         ${InvWhite}${CBlack}    T E S L A     ${InvDkGray}${CGreen}|${CClear}"
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear}"
  if [ "$remaining" != "0" ]; then
  echo -e "                         ${InvWhite}${CRed}  $remaining/h runtime ${InvDkGray}${CGreen}|${CClear}"
  else
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear}"
  fi
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear}"
  echo -e "                         ${InvDkGray}${CWhite}  $numpowerwalls POWERWALL(S)   ${CClear}"
  echo -e "${CGreen}___________________________________________________________________${CClear}"
  echo ""
}

# -------------------------------------------------------------------------------------------------------------------------

DisplayPage2 () {

  clear
  logo
  if [ "$UpdateNotify" != "0" ]; then
    echo -e "${CRed}  $UpdateNotify${CClear}"
    echo -e "${CGreen} _____${CClear}"
  else
    echo -e "${CGreen} _____${CClear}"
  fi
  echo -e "${CGreen}/${CYellow}Solar${CClear}${CGreen}\____________________________________________________________${CClear}"
  echo -e ""

  solardisplay=$(echo $solar | awk '{printf "%f\n", $1}' | cut -d . -f 1)
  #echo $solardisplay
  #if [ $solardisplay -gt $MaxSpeedInet ]; then SpdDownload=$MaxSpeedInet; fi
  if [ $solardisplay -gt $maxsolargen ]; then solardisplay=$maxsolargen; fi
  if [ $solardisplay -gt 0 ]; then
    preparebar 34 "|"
    progressbar $solardisplay $maxsolargen " Generated   " "kW" "Reverse" $solar
  else
    preparebar 34 "|"
    progressbar 0 $maxsolargen " Generated   " "kW" "Reverse" $solar
  fi
  echo ""
  echo -e "${CGreen} ____${CClear}"
  echo -e "${CGreen}/${CClear}Grid${CClear}${CGreen}\_____________________________________________________________${CClear}"
  echo -e ""

  griddisplay=$(echo $grid | awk '{printf "%f\n", $1}' | cut -d . -f 1)
  #echo $griddisplay
  if [ $griddisplay -gt $maxhomeelecload ]; then griddisplay=$maxhomeelecload; fi
  if [ $griddisplay -gt 0 ]; then
    #echo "positive: $griddisplay"
    preparebar 34 "|"
    progressbar $griddisplay $maxhomeelecload " Consumed    " "kW" "Standard" $grid
    echo ""
    preparebar 34 "|"
    progressbar 0 $maxsolargen " Generated   " "kW" "Reverse" $grid
    echo ""
  fi

  if [ $griddisplay -lt 0 ]; then
    griddisplay=$(echo $grid | awk '{printf "%f\n", $1*-1}' | cut -d . -f 1)
    if [ $griddisplay -gt $maxhomeelecload ]; then griddisplay=$maxhomeelecload; fi
    #echo "negative: $griddisplay"
    preparebar 34 "|"
    progressbar 0 $maxhomeelecload " Consumed    " "kW" "Standard" $grid
    echo ""
    preparebar 34 "|"
    progressbar $griddisplay $maxsolargen " Generated   " "kW" "Reverse" $grid
    echo ""
  fi

  if [ $griddisplay -eq 0 ]; then
    #echo "zero: $griddisplay"
    preparebar 34 "|"
    progressbar 0 $maxhomeelecload " Consumed    " "kW" "Standard" $grid
    echo ""
    preparebar 34 "|"
    progressbar 0 $maxsolargen " Generated   " "kW" "Reverse" $grid
    echo ""
  fi

  echo -e "${CGreen} ____${CClear}"
  echo -e "${CGreen}/${CCyan}Home${CClear}${CGreen}\_____________________________________________________________${CClear}"
  echo -e ""

  homedisplay=$(echo $home | awk '{printf "%f\n", $1}' | cut -d . -f 1)
  #echo $homedisplay
  if [ $homedisplay -gt $maxhomeelecload ]; then homedisplay=$maxhomeelecload; fi
  if [ $homedisplay -gt 0 ]; then
    preparebar 34 "|"
    progressbar $homedisplay $maxhomeelecload " Consumed    " "kW" "Standard" $home
    echo ""
    if [ $homedisplay -gt $battelecload ]; then homedisplay=$battelecload; fi
    preparebar 34 "|"
    progressbar $homedisplay $battelecload " PW Max Load " "kW" "Standard" $home
  else
    preparebar 34 "|"
    progressbar 0 $maxhomeelecload " Consumed    " "kW" "Standard" $home
  fi

  echo ""
  echo -e "${CGreen} _______${CClear}"
  echo -e "${CGreen}/${CWhite}Battery${CClear}${CGreen}\__________________________________________________________${CClear}"
  echo -e ""

  runtime=$(awk -v homeload=$home -v pwalls=$numpowerwalls -v pwcap=13.5 -v remain=$battmult 'BEGIN{printf "%+05.1f\n", pwalls*pwcap*remain/homeload}')
  echo -e "${InvCyan} ${CClear} ${CCyan}Runtime      ${CGreen}[            ${CCyan}$runtime/h${CGreen}               ]${CClear}"

  #echo "battcapp: $battcapp"
  preparebar 34 "|"
  progressbar $battcapp 100 " Charge %%    " "%%" "Reverse"
  echo ""
  echo ""

  battdisplay=$(echo $battery | awk '{printf "%f\n", $1}' | cut -d . -f 1)
  #echo $battdisplay
  if [ $battdisplay -gt $battelecload ]; then griddisplay=$battelecload; fi
  if [ $battdisplay -gt 0 ]; then
    #echo "positive: $battdisplay"
    preparebar 34 "|"
    progressbar $battdisplay $battelecload " Consumed    " "kW" "Standard" $battery
    echo ""
    preparebar 34 "|"
    progressbar 0 $battelecload " Generated   " "kW" "Reverse" $battery
    echo ""
  fi

  if [ $battdisplay -lt 0 ]; then
    battdisplay=$(echo $grid | awk '{printf "%f\n", $1*-1}' | cut -d . -f 1)
    if [ $battdisplay -gt $battelecload ]; then griddisplay=$battelecload; fi
    #echo "negative: $battdisplay"
    preparebar 34 "|"
    progressbar 0 $battelecload " Consumed    " "kW" "Standard" $battery
    echo ""
    preparebar 34 "|"
    progressbar $battdisplay $battelecload " Generated   " "kW" "Reverse" $battery
    echo ""
  fi

  if [ $battdisplay -eq 0 ]; then
    #echo "zero: $battdisplay"
    preparebar 34 "|"
    progressbar 0 $battelecload " Consumed    " "kW" "Standard" $battery
    echo ""
    preparebar 34 "|"
    progressbar 0 $battelecload " Generated   " "kW" "Reverse" $battery
    echo ""
  fi

  echo ""

}

# -------------------------------------------------------------------------------------------------------------------------
# Begin Commandline Argument Gatekeeper and Configuration Utility Functionality
# -------------------------------------------------------------------------------------------------------------------------

#DEBUG=; set -x # uncomment/comment to enable/disable debug mode
#{              # uncomment/comment to enable/disable debug mode

  # Create the necessary folder/file structure for PWRMON under /jffs/addons
  if [ ! -d "/jffs/addons/pwrmon.d" ]; then
		mkdir -p "/jffs/addons/pwrmon.d"
  fi

  # Check for Updates
  updatecheck

  # Check and see if any commandline option is being used
  if [ $# -eq 0 ]
    then
      clear
      echo ""
      echo "PWRMON v$Version"
      echo ""
      echo "Exiting due to missing commandline options!"
      echo "(run 'pwrmon.sh -h' for help)"
      echo ""
      echo -e "${CClear}"
      exit 0
  fi

  # Check and see if an invalid commandline option is being used
  if [ "$1" == "-h" ] || [ "$1" == "-help" ] || [ "$1" == "-config" ] || [ "$1" == "-monitor" ] || [ "$1" == "-log" ] || [ "$1" == "-update" ] || [ "$1" == "-setup" ] || [ "$1" == "-uninstall" ] || [ "$1" == "-screen" ]
    then
      clear
    else
      clear
      echo ""
      echo "PWRMON v$Version"
      echo ""
      echo "Exiting due to invalid commandline options!"
      echo "(run 'pwrmon.sh -h' for help)"
      echo ""
      echo -e "${CClear}"
      exit 0
  fi

  # Check to see if the help option is being called
  if [ "$1" == "-h" ] || [ "$1" == "-help" ]
    then
    clear
    echo ""
    echo "PWRMON v$Version Commandline Option Usage:"
    echo ""
    echo "pwrmon.sh -h | -help"
    echo "pwrmon.sh -log"
    echo "pwrmon.sh -config"
    echo "pwrmon.sh -update"
    echo "pwrmon.sh -setup"
    echo "pwrmon.sh -uninstall"
    echo "pwrmon.sh -screen"
    echo "pwrmon.sh -monitor"
    echo ""
    echo " -h | -help (this output)"
    echo " -log (display the current log contents)"
    echo " -config (configuration utility)"
    echo " -update (script update utility)"
    echo " -setup (setup/dependencies utility)"
    echo " -uninstall (uninstall utility)"
    echo " -screen (normal PW monitoring using the screen utility)"
    echo " -monitor (normal PW monitoring operations)"
    echo ""
    echo -e "${CClear}"
    exit 0
  fi

  # Check to see if the log option is being called, and display through nano
  if [ "$1" == "-log" ]
    then
      vlogs
      exit 0
  fi

  # Check to see if the configuration option is being called, and run through setup utility
  if [ "$1" == "-config" ]
    then
      vconfig
      echo -e "${CClear}"
      exit 0
  fi

  # Check to see if the update option is being called
  if [ "$1" == "-update" ]
    then
      vupdate
      echo -e "${CClear}"
      exit 0
  fi

  # Check to see if the install option is being called
  if [ "$1" == "-setup" ]
    then
      vsetup
  fi

  # Check to see if the uninstall option is being called
  if [ "$1" == "-uninstall" ]
    then
      vuninstall
      echo -e "${CClear}"
      exit 0
  fi

  # Check to see if the screen option is being called and run operations normally using the screen utility
  if [ "$1" == "-screen" ]
    then
      ScreenSess=$(screen -ls | grep "pwrmon" | awk '{print $1}' | cut -d . -f 1)
      if [ -z $ScreenSess ]; then
        clear
        echo -e "${CGreen}Executing PWRMON using the SCREEN utility...${CClear}"
        echo ""
        echo -e "${CGreen}Reconnect at any time using the command 'screen -r pwrmon'${CClear}"
        echo -e "${CGreen}To exit the SCREEN session, type: CTRL-A + D${CClear}"
        echo ""
        screen -dmS "pwrmon" $APPPATH -monitor
        sleep 2
        read -rsp $'Press any key to continue...\n' -n1 key
        echo -e "${CClear}"
        exit 0
      else
        clear
        echo -e "${CGreen}Another PWRMON Screen session is already running...${CClear}"
        echo -e "${CGreen}Would you like to attach to this session?${CClear}"
        if promptyn "(y/n): "; then
          screen -dr $ScreenSess
          sleep 2
          echo -e "${CClear}"
          exit 0
        else
          echo ""
          echo -e "\n${CGreen}Exiting...${CClear}"
          sleep 1
          return
        fi
      fi
  fi

  # Check to see if the monitor option is being called and run operations normally
  if [ "$1" == "-monitor" ]
    then
      clear
      if [ -f $CFGPATH ]; then
        source $CFGPATH

          if [ -f "/opt/bin/timeout" ] # If the timeout utility is available then use it and assign variables
            then
              timeoutcmd="timeout "
              timeoutsec="10"
              timeoutlng="60"
            else
              timeoutcmd=""
              timeoutsec=""
              timeoutlng=""
          fi
    else
      echo -e "${CRed}Error: PWRMON is not configured.  Please run 'pwrmon.sh -setup' to complete setup${CClear}"
      echo ""
      echo -e "$(date) - PWRMON ----------> ERROR: pwrmon.cfg was not found. Please run the setup tool." >> $LOGFILE
      kill 0
    fi
  fi

# -------------------------------------------------------------------------------------------------------------------------
# Begin Main Loop, pulling stats from Tesla Gateway
# -------------------------------------------------------------------------------------------------------------------------

  clear
  logoNM
  echo ""
  echo -e "  ${CGreen}[Initiating Boot Sequence - Connecting to Tesla Gateway...]"
  echo ""

  # create an empty file to hold a cookie file from the Telsa Powerwall Gateway
  { echo ''
  } > /jffs/scripts/pwrmon.cookies

  # attempt a login to the gateway and pull down some auth info for further API access
  do_login

while true; do

  remaining=0
  siteinfo=$(curl -s -S -k -b "$cookie_file" "https://$gatewayip/api/site_info")
  sitename=$(echo $siteinfo | jq '.site_name')

  agg=$(curl -s -S -k -b "$cookie_file" "https://$gatewayip/api/meters/aggregates")
  homeoutput=$(echo $agg | jq '.load.instant_power' | cut -d . -f 1)
  gridoutput=$(echo $agg | jq '.site.instant_power' | cut -d . -f 1)
  solaroutput=$(echo $agg | jq '.solar.instant_power' | cut -d . -f 1)
  batteryoutput=$(echo $agg | jq '.battery.instant_power' | cut -d . -f 1)

  capacity=$(curl -s -S -k -b "$cookie_file" "https://$gatewayip/api/system_status/soe")
  battcapp=$(echo $capacity | jq '.percentage' | cut -d . -f 1)
  battmult=$(awk "BEGIN {printf \"%.2f\",${battcapp}/100}")
  battelecload=$(awk "BEGIN {printf \"%.0f\",${numpowerwalls}*5}")

  #---testing---
  #batteryoutput=3500
  #solaroutput=1500
  #gridoutput=0
  #homeoutput=0

  solar=$(awk -v so=$solaroutput -v unit=1000 'BEGIN{printf "%+05.1f\n", so/unit}')
  battery=$(awk -v so=$batteryoutput -v unit=1000 'BEGIN{printf "%+05.1f\n", so/unit}')
  grid=$(awk -v so=$gridoutput -v unit=1000 'BEGIN{printf "%+05.1f\n", so/unit}')
  home=$(awk -v so=$homeoutput -v unit=1000 'BEGIN{printf "%+05.1f\n", so/unit}')

  if [ "$solaroutput" -ge "100" ]; then
    solarshowline="${CYellow} || "
    solardirection1="${CYellow}\||/"
    solardirection2="${CYellow} \\/ "
  elif [ "$solaroutput" -lt "100" ]; then
    solarshowline="    "
    solardirection1="    "
    solardirection2="    "
  else
    solarshowline="    "
    solardirection1="    "
    solardirection2="    "
  fi

  if [ "$batteryoutput" -ge "100" ]; then
    batterydirection1=" /\\ "
    batterydirection2="/||\\"
    batterydirection3=" || "
    batterydirection4=" || "

    remaining=$(awk -v battload=$battery -v pwalls=$numpowerwalls -v pwcap=13.5 -v remain=$battmult 'BEGIN{printf "%+05.1f\n", pwalls*pwcap*remain/battload}')

  elif [ "$batteryoutput" -le "-100" ]; then
    batterydirection1=" || "
    batterydirection2=" || "
    batterydirection3="\||/"
    batterydirection4=" \\/ "
  elif [ "$batteryoutput" -lt "100" ] && [ "$batteryoutput" -gt "-100" ]; then
    batterydirection1="    "
    batterydirection2="    "
    batterydirection3="    "
    batterydirection4="    "
  fi

  if [ "$gridoutput" -ge "100" ]; then
    gridshowlines="${CClear}>>>>>>>>>>>>>"
  elif [ "$gridoutput" -le "-100" ]; then
    gridshowlines="${CClear}<<<<<<<<<<<<<"
  elif [ "$gridoutput" -lt "100" ] && [ "$gridoutput" -gt "-100" ]; then
    gridshowlines="${CClear}             "
  fi

  if [ "$homeoutput" -ge "100" ]; then
    homeshowlines="${CCyan}>>>>>>>>>>>>>"
  elif [ "$homeoutput" -le "-100" ]; then
    homeshowlines="${CCyan}<<<<<<<<<<<<<"
  elif [ "$homeoutput" -lt "100" ] && [ "$homeoutput" -gt "-100" ]; then
    homeshowlines="${CClear}             "
  fi

  # -------------------------------------------------------------------------------------------------------------------------
  # Begin UI Functionality
  # -------------------------------------------------------------------------------------------------------------------------

  if [ "$NextPage" == "1" ]; then
    clear
    DisplayPage1
    #echo ""
  elif [ "$NextPage" == "2" ]; then
    clear
    DisplayPage2
    #echo ""
  elif [ "$NextPage" == "3" ]; then
    clear
    DisplayPage3
    #echo ""
  fi

  i=0
  while [ $i -ne $Interval ]
    do
      i=$(($i+1))
      preparebar 51 "|"
      progressbar $i $Interval "" "s" "Standard"

      # Borrowed this wonderful keypress capturing mechanism from @Eibgrad... thank you! :)
      key_press=''; read -rsn1 -t 1 key_press < "$(tty 0>&2)"

      if [ $key_press ]; then
          case $key_press in
              [Ss]) FromUI=1; (vsetup); echo -e "${CGreen}  [Returning to the Main UI momentarily]                                   "; FromUI=0;;
              [Nn]) if [ "$NextPage" == "1" ]; then NextPage=2; clear; DisplayPage2; elif [ "$NextPage" == "2" ]; then NextPage=1; clear; DisplayPage1; fi;; #elif [ "$NextPage" == "3" ]; then NextPage=1; clear; DisplayPage1; echo -e "\n"; fi;;
              [Ee]) echo -e "${CClear}"; exit 0;;
          esac
      fi
  done

#read -rsp $'Press any key to continue...\n' -n1 key

done

exit 0
