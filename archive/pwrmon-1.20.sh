#!/bin/sh
#
# PWRMON v1.20 - Asus-Merlin Tesla Powerwall Monitor by Viktor Jaep, 2022
#
# PWRMON is a shell script that provides near-realtime stats about your Tesla Powerwall/Solar environment. This utility
# will show all the current electrical loads being generated or consumed by your solar system, the grid, your home and
# your Powerwall(s). Electrical transmission flows are accurately being depicted using >> and << types of arrows, as
# electricity moves between your solar, to/from your batteries, to/from the grid and to your home. In the event of a
# electrical grid outage, PWRMON will calculate your estimated remaining runtime left on your batteries based on the
# amount of kW being consumed by your home. Weather has now been incorporated to give you a 3 day outlook on what kind
# of weather to expect for generation or off-grid consumption due to regional disasters or weather events.
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
Version=1.20
Beta=0
LOGFILE="/jffs/addons/pwrmon.d/pwrmon.log"          # Logfile path/name that captures important date/time events - change
APPPATH="/jffs/scripts/pwrmon.sh"                   # Path to the location of pwrmon.sh
CFGPATH="/jffs/addons/pwrmon.d/pwrmon.cfg"          # Path to the location of pwrmon.cfg
DLVERPATH="/jffs/addons/pwrmon.d/version.txt"       # Path to downloaded version from the source repository
cookie_file="/jffs/addons/pwrmon.d/pwrmon.cookies"  # Path to cookies file needed to log into the Powerwall Gateway
smtpbody="/jffs/addons/pwrmon.d/smtpbody.txt"       # Path to email message txt file used to send Powerwall notifications
WANwxforecast="/jffs/addons/pwrmon.d/WANwx.txt"     # Path to weather forecast JSON extract used for weather displays
NextPage=1
UpdateNotify=0
FromUI=0
griddown=0

#Default Values
Interval=10
email="user@domain.com"
password="ABCDE"
gatewayip="192.168.1.150"
numpowerwalls=2
maxsolargen=7
maxhomeelecload=24
emailalerts="Disabled"
smtpusername="defaultsender@gmail.com"
smtprecipient="recipient@gmail.com"
smtppassword="U2FsdGVkX19IDBTBl5wMrbyLkj4VspYb"
smtpserver="smtp.gmail.com"
smtpport="465"
alertsentdown="False"
alertsentsync="False"

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
  echo -e "   / ____/| |/ |/ / _, _/ /  / / /_/ / /|  /   ${CRed}(N)${CGreen}xt/${CRed}(P)${CGreen}rv Pg ($NextPage/3)${CYellow}"
  echo -e "  /_/     |__/|__/_/ |_/_/  /_/\____/_/ |_/    ${CRed}(W)${CGreen}eather${CClear} ${CRed}(E)${CGreen}xit${CClear}"
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

# Spinner is a script that provides a small indicator on the screen to show script activity
spinner() {

  i=0
  j=$((SPIN / 4))
  while [ $i -le $j ]; do
    for s in / - \\ \|; do
      printf "\r$s"
      sleep 1
    done
    i=$((i+1))
  done

  printf "\r"
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
      if [ $progr -le 60 ]; then
        printf "${InvGreen}${CWhite}$insertspc${CClear}${CGreen}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      elif [ $progr -gt 60 ] && [ $progr -le 85 ]; then
        printf "${InvYellow}${CBlack}$insertspc${CClear}${CYellow}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      else
        printf "${InvRed}${CWhite}$insertspc${CClear}${CRed}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      fi
    elif [ "$5" == "Reverse" ]; then
      if [ $progr -le 35 ]; then
        printf "${InvRed}${CWhite}$insertspc${CClear}${CRed}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      elif [ $progr -gt 35 ] && [ $progr -le 85 ]; then
        printf "${InvYellow}${CBlack}$insertspc${CClear}${CYellow}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      else
        printf "${InvGreen}${CWhite}$insertspc${CClear}${CGreen}${3} [%.${barch}s%.${barsp}s]${CClear} ${CWhite}${InvDkGray}$AltNum ${4} / ${progr}%%\r${CClear}" "$barchars" "$barspaces"
      fi
    fi
  fi
}

# -------------------------------------------------------------------------------------------------------------------------
# emailalert send a message to a predetermined email address to inform of major events
emailalert () {
# $1 is the status needing to be sent

if [ $emailalerts == "Enabled" ]; then

smtppasswordplaintxt=$(echo "${smtppassword}" | openssl enc -d -des3 -base64 -pass pass:*TB0c7ksKGWcw22P -pbkdf2)

  if [ $1 = "griddown" ] && [ $alertsentdown = "False" ]; then
    alertsentdown="True"
    { echo 'From: '$smtpusername '<'$smtpusername'>'
      echo 'To: '$smtprecipient '<'$smtprecipient'>'
      echo 'Subject: POWERWALL ALERT'
      echo 'Content-Type: text/plain'
      echo 'X-Priority: 1 (Highest)'
      echo 'X-MSMail-Priority: High'
      echo ''
      echo 'Grid Power is DOWN at site: '$sitename
      echo 'Event time: '$(date)
      echo 'Battery Status (%): '$battcapp
      echo 'Estimated Runtime (H): '$runtime
      echo ''
      echo ''
      echo 'Sent via PWRMON v'$Version
    } > $smtpbody

    curl --silent --url smtps://$smtpserver:$smtpport --ssl-reqd --mail-from $smtpusername --mail-rcpt $smtprecipient --user $smtpusername:$smtppasswordplaintxt --upload-file $smtpbody
    echo -e "$(date) - PWRMON ---------> GRID OUTAGE - Notification sent to $smtprecipient!" >> $LOGFILE
  fi

  if [ $1 = "sync" ] && [ $alertsentsync = "False" ]; then
    alertsentsync="True"
    { echo 'From: '$smtpusername '<'$smtpusername'>'
      echo 'To: '$smtprecipient '<'$smtprecipient'>'
      echo 'Subject: POWERWALL ALERT'
      echo 'Content-Type: text/plain'
      echo 'X-Priority: 1 (Highest)'
      echo 'X-MSMail-Priority: High'
      echo ''
      echo 'POWERWALL ALERT!!!'
      echo ''
      echo 'Grid Power is currently SYNCING at site: '$sitename
      echo 'Event time: '$(date)
      echo 'Battery Status (%): '$battcapp
      echo 'Estimated Runtime (H): '$runtime
      echo ''
      echo ''
      echo 'Sent via PWRMON v'$Version
    } > $smtpbody

    curl --silent --url smtps://$smtpserver:$smtpport --ssl-reqd --mail-from $smtpusername --mail-rcpt $smtprecipient --user $smtpusername:$smtppasswordplaintxt --upload-file $smtpbody
    echo -e "$(date) - PWRMON ---------> GRID SYNCING - Notification sent to $smtprecipient!" >> $LOGFILE
  fi

  if [ $1 = "normal" ]; then
    alertsentdown="False"
    alertsentsync="False"
    { echo 'From: '$smtpusername '<'$smtpusername'>'
      echo 'To: '$smtprecipient '<'$smtprecipient'>'
      echo 'Subject: POWERWALL ALERT'
      echo 'Content-Type: text/plain'
      echo 'X-Priority: 1 (Highest)'
      echo 'X-MSMail-Priority: High'
      echo ''
      echo 'POWERWALL ALERT!!!'
      echo ''
      echo 'Grid Power has returned to NORMAL at site: '$sitename
      echo 'Event time: '$(date)
      echo 'Battery Status (%): '$battcapp
      echo 'Estimated Runtime (H): '$runtime
      echo ''
      echo ''
      echo 'Sent via PWRMON v'$Version
    } > $smtpbody

    curl --silent --url smtps://$smtpserver:$smtpport --ssl-reqd --mail-from $smtpusername --mail-rcpt $smtprecipient --user $smtpusername:$smtppasswordplaintxt --upload-file $smtpbody
    echo -e "$(date) - PWRMON ---------> GRID BACK ONLINE - Notification sent to $smtprecipient!" >> $LOGFILE
  fi

  if [ $1 = "test" ]; then
    { echo 'From: '$smtpusername '<'$smtpusername'>'
      echo 'To: '$smtprecipient '<'$smtprecipient'>'
      echo 'Subject: POWERWALL ALERT (TEST)'
      echo 'Content-Type: text/plain'
      echo 'X-Priority: 1 (Highest)'
      echo 'X-MSMail-Priority: High'
      echo ''
      echo 'POWERWALL ALERT!!! (TEST)'
      echo ''
      echo 'Testing PWRMON Notifications'
      echo 'Event time: '$(date)
      echo ''
      echo 'This is a successful test of a PWRMON notification.'
      echo 'In the event of a true grid down situation, you will'
      echo 'be notified along with current Battery Status (%) and'
      echo 'Estimated Runtime (H) stats. You will receive one'
      echo 'final notification indicating when the grid comes'
      echo 'back online.'
      echo ''
      echo ''
      echo 'Sent via PWRMON v'$Version
    } > $smtpbody

    curl --silent --url smtps://$smtpserver:$smtpport --ssl-reqd --mail-from $smtpusername --mail-rcpt $smtprecipient --user $smtpusername:$smtppasswordplaintxt --upload-file $smtpbody
    echo -e "$(date) - PWRMON ---------> GRID TEST - Notification sent to $smtprecipient!" >> $LOGFILE
  fi

  # Clean up messagebody
  rm $smtpbody

fi

}

# -------------------------------------------------------------------------------------------------------------------------
# fontprinter takes current load numbers passed, and prints them in large 5x6char block fonts
fontprinter () {
# $1 is the electrical load passed for home, battery, grid and solar
# $2 is the inverse color being passed

# Fonts 5x6 blocks
Number1Line1="${CClear}  $2  ${CClear}  "
Number1Line2="${CClear} $2   ${CClear}  "
Number1Line3="${CClear}  $2  ${CClear}  "
Number1Line4="${CClear}  $2  ${CClear}  "
Number1Line5="${CClear}  $2  ${CClear}  "
Number2Line1="${CClear} $2    ${CClear} "
Number2Line2="${CClear}$2 ${CClear}   $2  ${CClear}"
Number2Line3="${CClear}   $2  ${CClear} "
Number2Line4="${CClear} $2  ${CClear}   "
Number2Line5="${CClear}$2      ${CClear}"
Number3Line1="${CClear}$2      ${CClear}"
Number3Line2="${CClear}    $2  ${CClear}"
Number3Line3="${CClear}  $2    ${CClear}"
Number3Line4="${CClear}    $2  ${CClear}"
Number3Line5="${CClear}$2      ${CClear}"
Number4Line1="${CClear}$2 ${CClear}  $2  ${CClear} "
Number4Line2="${CClear}$2 ${CClear}  $2  ${CClear} "
Number4Line3="${CClear}$2      ${CClear}"
Number4Line4="${CClear}   $2  ${CClear} "
Number4Line5="${CClear}   $2  ${CClear} "
Number5Line1="${CClear}$2      ${CClear}"
Number5Line2="${CClear}$2  ${CClear}    "
Number5Line3="${CClear}$2     ${CClear} "
Number5Line4="${CClear}    $2  ${CClear}"
Number5Line5="${CClear}$2     ${CClear} "
Number6Line1="${CClear}  $2  ${CClear}  "
Number6Line2="${CClear} $2  ${CClear}   "
Number6Line3="${CClear}$2     ${CClear} "
Number6Line4="${CClear}$2  ${CClear}  $2  ${CClear}"
Number6Line5="${CClear} $2    ${CClear} "
Number7Line1="${CClear}$2      ${CClear}"
Number7Line2="${CClear}    $2  ${CClear}"
Number7Line3="${CClear}   $2  ${CClear} "
Number7Line4="${CClear}  $2  ${CClear}  "
Number7Line5="${CClear} $2  ${CClear}   "
Number8Line1="${CClear} $2    ${CClear} "
Number8Line2="${CClear}$2  ${CClear}  $2  ${CClear}"
Number8Line3="${CClear} $2    ${CClear} "
Number8Line4="${CClear}$2  ${CClear}  $2  ${CClear}"
Number8Line5="${CClear} $2    ${CClear} "
Number9Line1="${CClear} $2    ${CClear} "
Number9Line2="${CClear}$2  ${CClear}  $2  ${CClear}"
Number9Line3="${CClear} $2     ${CClear}"
Number9Line4="${CClear}   $2  ${CClear} "
Number9Line5="${CClear}  $2  ${CClear}  "
Number0Line1="${CClear} $2    ${CClear} "
Number0Line2="${CClear}$2  ${CClear}  $2  ${CClear}"
Number0Line3="${CClear}$2  ${CClear}  $2  ${CClear}"
Number0Line4="${CClear}$2  ${CClear}  $2  ${CClear}"
Number0Line5="${CClear} $2    ${CClear} "
PositiveLine2="${CClear}  $2  ${CClear}  "
PositiveLine3="${CClear} $2    ${CClear} "
PositiveLine4="${CClear}  $2  ${CClear}  "
NegativeLine2="${CClear}      "
NegativeLine3="${CClear} $2    ${CClear} "
NegativeLine4="${CClear}      "
DecimalLine5="${CClear} $2  ${CClear} "
SolarLine1="${CBlack}${InvYellow}  SOLAR   ${CClear}"
SolarLine2="${CBlack}${InvYellow}  \|/____ ${CClear}"
SolarLine3="${CBlack}${InvYellow} --O///// ${CClear}"
SolarLine4="${CBlack}${InvYellow}  //////  ${CClear}"
SolarLine5="${CBlack}${InvYellow} //////   ${CClear}"
GridLine1="${CWhite}${InvDkGray}   GRID   ${CClear}"
GridLine2="${CWhite}${InvDkGray}   - | +  ${CClear}"
GridLine3="${CWhite}${InvDkGray} ===||=== ${CClear}"
GridLine4="${CWhite}${InvDkGray}     |    ${CClear}"
GridLine5="${CWhite}${InvDkGray} HI VOLTS ${CClear}"
HomeLine1="${CBlack}${InvCyan}   HOME   ${CClear}"
HomeLine2="${CBlack}${InvCyan}  /====\| ${CClear}"
HomeLine3="${CBlack}${InvCyan} /______\ ${CClear}"
HomeLine4="${CBlack}${InvCyan} | |[]| | ${CClear}"
HomeLine5="${CBlack}${InvCyan} ^^^^^^^^ ${CClear}"
BattLine1="${InvWhite}${CBlack}   BATT  ${InvDkGray}${CGreen}|${CClear}"
BattLine2="${InvWhite}${CBlack}   $battcapp3%%  ${InvDkGray}${CGreen}|${CClear}"
BattLine3="${InvWhite}         ${InvDkGray}${CGreen}|${CClear}"
BattLine4="${InvWhite}${CRed}  TESLA  ${InvDkGray}${CGreen}|${CClear}"
BattLine5="${InvWhite}         ${InvDkGray}${CGreen}|${CClear}"
GridOutLine1="${CWhite}${InvRed}   GRID   ${CClear}"
GridOutLine2="${CWhite}${InvRed}  X || X  ${CClear}"
GridOutLine3="${CWhite}${InvRed} == XX == ${CClear}"
GridOutLine4="${CWhite}${InvRed}  X || X  ${CClear}"
GridOutLine5="${CWhite}${InvRed}  OUTAGE  ${CClear}"
GridSyncLine1="${CWhite}${InvRed}   GRID   ${CClear}"
GridSyncLine2="${CWhite}${InvRed}  > || >  ${CClear}"
GridSyncLine3="${CWhite}${InvRed} == >> == ${CClear}"
GridSyncLine4="${CWhite}${InvRed}  < || <  ${CClear}"
GridSyncLine5="${CBlack}${InvYellow} >SYNCING ${CClear}"

posneg=$(echo $1 | cut -b 1 )
tens=$(echo $1 | cut -b 2 )
ones=$(echo $1 | cut -b 3 )
tenths=$(echo $1 | cut -b 5 )

if [ $posneg == "+" ]; then posneg="Positive"; else posneg="Negative"; fi

case $3 in

  "Solar")
  imageLine1=$SolarLine1
  imageLine2=$SolarLine2
  imageLine3=$SolarLine3
  imageLine4=$SolarLine4
  imageLine5=$SolarLine5
  ;;
  "Grid")
  if [ "$gridstatus" == "SystemIslandedActive" ]; then
    imageLine1=$GridOutLine1
    imageLine2=$GridOutLine2
    imageLine3=$GridOutLine3
    imageLine4=$GridOutLine4
    imageLine5=$GridOutLine5
  elif [ "$gridstatus" == "SystemTransitionToGrid" ]; then
    imageLine1=$GridSyncLine1
    imageLine2=$GridSyncLine2
    imageLine3=$GridSyncLine3
    imageLine4=$GridSyncLine4
    imageLine5=$GridSyncLine5
  else
    imageLine1=$GridLine1
    imageLine2=$GridLine2
    imageLine3=$GridLine3
    imageLine4=$GridLine4
    imageLine5=$GridLine5
  fi
  ;;
  "Home")
  imageLine1=$HomeLine1
  imageLine2=$HomeLine2
  imageLine3=$HomeLine3
  imageLine4=$HomeLine4
  imageLine5=$HomeLine5
  ;;
  "Battery")
  imageLine1=$BattLine1
  imageLine2=$BattLine2
  imageLine3=$BattLine3
  imageLine4=$BattLine4
  imageLine5=$BattLine5
  ;;

esac

case $posneg in

  "Positive")
   posnegLine2=$PositiveLine2
   posnegLine3=$PositiveLine3
   posnegLine4=$PositiveLine4
  ;;

  "Negative")
  posnegLine2=$NegativeLine2
  posnegLine3=$NegativeLine3
  posnegLine4=$NegativeLine4
  ;;

esac

case $tens in

  1) #Tens Digit
  tensLine1=$Number1Line1
  tensLine2=$Number1Line2
  tensLine3=$Number1Line3
  tensLine4=$Number1Line4
  tensLine5=$Number1Line5
  ;;
  2)
  tensLine1=$Number2Line1
  tensLine2=$Number2Line2
  tensLine3=$Number2Line3
  tensLine4=$Number2Line4
  tensLine5=$Number2Line5
  ;;
  3)
  tensLine1=$Number3Line1
  tensLine2=$Number3Line2
  tensLine3=$Number3Line3
  tensLine4=$Number3Line4
  tensLine5=$Number3Line5
  ;;
  4)
  tensLine1=$Number4Line1
  tensLine2=$Number4Line2
  tensLine3=$Number4Line3
  tensLine4=$Number4Line4
  tensLine5=$Number4Line5
  ;;
  5)
  tensLine1=$Number5Line1
  tensLine2=$Number5Line2
  tensLine3=$Number5Line3
  tensLine4=$Number5Line4
  tensLine5=$Number5Line5
  ;;
  6)
  tensLine1=$Number6Line1
  tensLine2=$Number6Line2
  tensLine3=$Number6Line3
  tensLine4=$Number6Line4
  tensLine5=$Number6Line5
  ;;
  7)
  tensLine1=$Number7Line1
  tensLine2=$Number7Line2
  tensLine3=$Number7Line3
  tensLine4=$Number7Line4
  tensLine5=$Number7Line5
  ;;
  8)
  tensLine1=$Number8Line1
  tensLine2=$Number8Line2
  tensLine3=$Number8Line3
  tensLine4=$Number8Line4
  tensLine5=$Number8Line5
  ;;
  9)
  tensLine1=$Number9Line1
  tensLine2=$Number9Line2
  tensLine3=$Number9Line3
  tensLine4=$Number9Line4
  tensLine5=$Number9Line5
  ;;
  0)
  tensLine1=$Number0Line1
  tensLine2=$Number0Line2
  tensLine3=$Number0Line3
  tensLine4=$Number0Line4
  tensLine5=$Number0Line5
  ;;

esac

case $ones in

  1)
  onesLine1=$Number1Line1
  onesLine2=$Number1Line2
  onesLine3=$Number1Line3
  onesLine4=$Number1Line4
  onesLine5=$Number1Line5
  ;;
  2)
  onesLine1=$Number2Line1
  onesLine2=$Number2Line2
  onesLine3=$Number2Line3
  onesLine4=$Number2Line4
  onesLine5=$Number2Line5
  ;;
  3)
  onesLine1=$Number3Line1
  onesLine2=$Number3Line2
  onesLine3=$Number3Line3
  onesLine4=$Number3Line4
  onesLine5=$Number3Line5
  ;;
  4)
  onesLine1=$Number4Line1
  onesLine2=$Number4Line2
  onesLine3=$Number4Line3
  onesLine4=$Number4Line4
  onesLine5=$Number4Line5
  ;;
  5)
  onesLine1=$Number5Line1
  onesLine2=$Number5Line2
  onesLine3=$Number5Line3
  onesLine4=$Number5Line4
  onesLine5=$Number5Line5
  ;;
  6)
  onesLine1=$Number6Line1
  onesLine2=$Number6Line2
  onesLine3=$Number6Line3
  onesLine4=$Number6Line4
  onesLine5=$Number6Line5
  ;;
  7)
  onesLine1=$Number7Line1
  onesLine2=$Number7Line2
  onesLine3=$Number7Line3
  onesLine4=$Number7Line4
  onesLine5=$Number7Line5
  ;;
  8)
  onesLine1=$Number8Line1
  onesLine2=$Number8Line2
  onesLine3=$Number8Line3
  onesLine4=$Number8Line4
  onesLine5=$Number8Line5
  ;;
  9)
  onesLine1=$Number9Line1
  onesLine2=$Number9Line2
  onesLine3=$Number9Line3
  onesLine4=$Number9Line4
  onesLine5=$Number9Line5
  ;;
  0)
  onesLine1=$Number0Line1
  onesLine2=$Number0Line2
  onesLine3=$Number0Line3
  onesLine4=$Number0Line4
  onesLine5=$Number0Line5
  ;;

esac

case $tenths in

  1)
  tenthsLine1=$Number1Line1
  tenthsLine2=$Number1Line2
  tenthsLine3=$Number1Line3
  tenthsLine4=$Number1Line4
  tenthsLine5=$Number1Line5
  ;;
  2)
  tenthsLine1=$Number2Line1
  tenthsLine2=$Number2Line2
  tenthsLine3=$Number2Line3
  tenthsLine4=$Number2Line4
  tenthsLine5=$Number2Line5
  ;;
  3)
  tenthsLine1=$Number3Line1
  tenthsLine2=$Number3Line2
  tenthsLine3=$Number3Line3
  tenthsLine4=$Number3Line4
  tenthsLine5=$Number3Line5
  ;;
  4) #Tenths Digit
  tenthsLine1=$Number4Line1
  tenthsLine2=$Number4Line2
  tenthsLine3=$Number4Line3
  tenthsLine4=$Number4Line4
  tenthsLine5=$Number4Line5
  ;;
  5)
  tenthsLine1=$Number5Line1
  tenthsLine2=$Number5Line2
  tenthsLine3=$Number5Line3
  tenthsLine4=$Number5Line4
  tenthsLine5=$Number5Line5
  ;;
  6)
  tenthsLine1=$Number6Line1
  tenthsLine2=$Number6Line2
  tenthsLine3=$Number6Line3
  tenthsLine4=$Number6Line4
  tenthsLine5=$Number6Line5
  ;;
  7)
  tenthsLine1=$Number7Line1
  tenthsLine2=$Number7Line2
  tenthsLine3=$Number7Line3
  tenthsLine4=$Number7Line4
  tenthsLine5=$Number7Line5
  ;;
  8)
  tenthsLine1=$Number8Line1
  tenthsLine2=$Number8Line2
  tenthsLine3=$Number8Line3
  tenthsLine4=$Number8Line4
  tenthsLine5=$Number8Line5
  ;;
  9)
  tenthsLine1=$Number9Line1
  tenthsLine2=$Number9Line2
  tenthsLine3=$Number9Line3
  tenthsLine4=$Number9Line4
  tenthsLine5=$Number9Line5
  ;;
  0)
  tenthsLine1=$Number0Line1
  tenthsLine2=$Number0Line2
  tenthsLine3=$Number0Line3
  tenthsLine4=$Number0Line4
  tenthsLine5=$Number0Line5
  ;;

esac

printf "            ${imageLine1}        ${tensLine1} ${onesLine1}    ${tenthsLine1}\n"
printf "            ${imageLine2} ${posnegLine2} ${tensLine2} ${onesLine2}    ${tenthsLine2}\n"
printf "            ${imageLine3} ${posnegLine3} ${tensLine3} ${onesLine3}    ${tenthsLine3}\n"
printf "            ${imageLine4} ${posnegLine4} ${tensLine4} ${onesLine4}    ${tenthsLine4}\n"
printf "            ${imageLine5}        ${tensLine5} ${onesLine5}${DecimalLine5}${tenthsLine5}\n"

}

# -------------------------------------------------------------------------------------------------------------------------

# This function was "borrowed" graciously from @dave14305 from his FlexQoS script to determine the active WAN connection.
# Thanks much for your troubleshooting help as we tackled how to best derive the active WAN interface, Dave!

get_wan_setting() {
  local varname varval
  varname="${1}"
  prefixes="wan0_ wan1_"

  if [ "$($timeoutcmd$timeoutsec nvram get wans_mode)" = "lb" ] ; then
      for prefix in $prefixes; do
          state="$($timeoutcmd$timeoutsec nvram get "${prefix}"state_t)"
          sbstate="$($timeoutcmd$timeoutsec nvram get "${prefix}"sbstate_t)"
          auxstate="$($timeoutcmd$timeoutsec nvram get "${prefix}"auxstate_t)"

          # is_wan_connect()
          [ "${state}" = "2" ] || continue
          [ "${sbstate}" = "0" ] || continue
          [ "${auxstate}" = "0" ] || [ "${auxstate}" = "2" ] || continue

          # get_wan_ifname()
          proto="$($timeoutcmd$timeoutsec nvram get "${prefix}"proto)"
          if [ "${proto}" = "pppoe" ] || [ "${proto}" = "pptp" ] || [ "${proto}" = "l2tp" ] ; then
              varval="$($timeoutcmd$timeoutsec nvram get "${prefix}"pppoe_"${varname}")"
          else
              varval="$($timeoutcmd$timeoutsec nvram get "${prefix}""${varname}")"
          fi
      done
  else
      for prefix in $prefixes; do
          primary="$($timeoutcmd$timeoutsec nvram get "${prefix}"primary)"
          [ "${primary}" = "1" ] && break
      done

      proto="$($timeoutcmd$timeoutsec nvram get "${prefix}"proto)"
      if [ "${proto}" = "pppoe" ] || [ "${proto}" = "pptp" ] || [ "${proto}" = "l2tp" ] ; then
          varval="$($timeoutcmd$timeoutsec nvram get "${prefix}"pppoe_"${varname}")"
      else
          varval="$($timeoutcmd$timeoutsec nvram get "${prefix}""${varname}")"
      fi
  fi
  printf "%s" "${varval}"
} # get_wan_setting

# -------------------------------------------------------------------------------------------------------------------------
# weathercheck is a function that downloads the latest weather for your WAN IP location
weathercheck () {

  # Get the WAN interface in order to check for the public WAN IP address
  WANIFNAME=$(get_wan_setting ifname)
  WANIP=$(curl --silent --fail --interface $WANIFNAME --request GET --url https://ipv4.icanhazip.com)
  WANCITY=$(curl --silent --retry 3 --request GET --url http://ip-api.com/json/$WANIP | jq --raw-output .city)

  # Get the latitute/longitude of the public WAN IP address
  WANlat=$(curl --silent --retry 3 --request GET --url http://ip-api.com/json/$WANIP | jq --raw-output .lat)
  WANlon=$(curl --silent --retry 3 --request GET --url http://ip-api.com/json/$WANIP | jq --raw-output .lon)

  # Get the Weather grid for the latitude/longitude
  WANgridurl=$(curl --silent --retry 3 --request GET --url https://api.weather.gov/points/$WANlat,$WANlon | jq --raw-output .properties.forecast)

  # Extract the weather JSON to a text file in order to query from it with JQ
  curl --silent --retry 3 --request GET --url $WANgridurl | jq . --raw-output > $WANwxforecast
  LINES=$(cat $WANwxforecast | wc -l) #Check to see how many lines are in this file

  if [ $LINES -eq 0 ] #If there are no lines, error out
  then
    echo -e "\n${CRed} [Error: Unable to download weather data. Try again later...]\n${CClear}"
    echo -e "$(date) - PWRMON ----------> ERROR: Unable to fetch weather data. May be a temporary issue. Try again later." >> $LOGFILE
    sleep 3
    exit 0
  else
    # Display the city, lat and long
    #WANCITY="Your City"
    #WANlat=32.3321
    #WANlon=-64.7660
    clear
    logo
    if [ "$UpdateNotify" != "0" ]; then
      echo -e "${CRed}  $UpdateNotify${CClear}"
      echo -e "${CGreen} ________${CClear}"
    else
      echo -e "${CGreen} ________${CClear}"
    fi
    echo -e "${CGreen}/${CRed}Location${CClear}${CGreen}\_________________________________________________________${CClear}"
    echo ""
    echo -e "${InvGreen} ${CClear}${CGreen} City: ${CCyan}$WANCITY ${CGreen}-- Latitude: ${CCyan}$WANlat ${CGreen}-- Longitude: ${CCyan}$WANlon"
    echo -e "${CGreen} ________${CClear}"
    echo -e "${CGreen}/${CRed}Forecast${CClear}${CGreen}\_________________________________________________________${CClear}"
    echo ""

    # Loop through the forecasts and display them
    i=0
    while [ $i -ne 6 ]
      do

        WANwxName=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].name')
        WANwxTemp=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].temperature')
        WANwxTempUnit=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].temperatureUnit')
        WANwxWind=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].windSpeed')
        WANwxWindDir=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].windDirection')
        WANwxShort=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].shortForecast')
        WANwxDetail=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].detailedForecast')
        WANwxShortTrim=$(echo $WANwxShort | sed -e 's/.\{50\} /&\n/g')
        WANwxDetailTrim=$(echo $WANwxDetail | sed -e 's/.\{50\} /&\n/g')

    echo -e "${InvGreen} ${CClear}${CGreen} Day: ${CCyan}$WANwxName ${CGreen}-- Temp: ${CCyan}$WANwxTemp$WANwxTempUnit ${CGreen}-- Wind: ${CCyan}$WANwxWind from $WANwxWindDir"
    echo -e "${InvGreen} ${CClear}${CGreen} Conditions: ${CCyan}$WANwxShortTrim"
    echo ""

    i=$(($i+1))

  done

  echo -en "${CRed}(M)${CGreen}ore Detail, ${CRed}(C)${CGreen}lose?"
  while true; do
   read -p ": " -n 1 -r WxPrompt
     case $WxPrompt in
       [Mm]) weathercheckext; exit 0;;
       [Cc]) echo -e "${CGreen}\r  [Returning to the Main UI momentarily]                                   "; exit 0;;
       "" ) echo -e "\nValid Choices [Mm / Cc]";;
       * ) echo -e "\nValid Choices [Mm / Cc]";;
     esac
  done
fi
}

# -------------------------------------------------------------------------------------------------------------------------
# weathercheckext is a function that displays the latest extended weather forecast for your WAN IP location
weathercheckext () {

  clear
  logo
  if [ "$UpdateNotify" != "0" ]; then
    echo -e "${CRed}  $UpdateNotify${CClear}"
    echo -e "${CGreen} _________________${CClear}"
  else
    echo -e "${CGreen} _________________${CClear}"
  fi
  echo -e "${CGreen}/${CRed}Extended Forecast${CClear}${CGreen}\________________________________________________${CClear}"
  echo ""

  # Loop through the forecasts and display them
  i=0
  while [ $i -ne 6 ]
    do

      WANwxName=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].name')
      WANwxDetail=$(cat $WANwxforecast | jq -r '.properties.periods['$i'].detailedForecast')
      WANwxDetailTrim=$(echo $WANwxDetail | sed -e 's/.\{57\} /&\n/g')

  echo -e "${InvGreen} ${CClear}${CGreen} Day: ${CCyan}$WANwxName"
  echo -e "${CCyan}$WANwxDetailTrim"
  echo ""

  i=$(($i+1))

done

echo -en "${CRed}(C)${CGreen}lose?"
while true; do
 read -p ": " -n 1 -r WxPromptExt
   case $WxPromptExt in
     [Cc]) weathercheck; exit 0;;
     "" ) echo -e "\nValid Choices [Cc]";;
     * ) echo -e "\nValid Choices [Cc]";;
   esac
done

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
      echo -e "${InvDkGray}${CWhite} 8 ${CClear}${CCyan}: Enable Email Alerts?        :"${CGreen}$emailalerts
      if [ "$emailalerts" == "Enabled" ]; then
        echo -e "${InvDkGray}${CWhite} |-${CClear}${CCyan}-  Email Address FROM:        :"${CGreen}$smtpusername
        echo -e "${InvDkGray}${CWhite} |-${CClear}${CCyan}-  Email Address Acct Pwd:    :${CGreen}[ENCRYPTED]"
        echo -e "${InvDkGray}${CWhite} |-${CClear}${CCyan}-  Email Address RCPT TO:     :"${CGreen}$smtprecipient
        echo -e "${InvDkGray}${CWhite} |-${CClear}${CCyan}-  SMTP Server Name:          :"${CGreen}$smtpserver
        echo -e "${InvDkGray}${CWhite} |-${CClear}${CCyan}-  SMTP Server Port:          :"${CGreen}$smtpport
      else
        echo -e "${InvDkGray}${CWhite} | ${CClear}${CDkGray}-  Email Address FROM:        :"${CDkGray}$smtpusername
        echo -e "${InvDkGray}${CWhite} | ${CClear}${CDkGray}-  Email Address Acct Pwd:    :${CDkGray}$[ENCRYPTED]"
        echo -e "${InvDkGray}${CWhite} | ${CClear}${CDkGray}-  Email Address RCPT TO:     :"${CDkGray}$smtprecipient
        echo -e "${InvDkGray}${CWhite} | ${CClear}${CDkGray}-  SMTP Server Name:          :"${CDkGray}$smtpserver
        echo -e "${InvDkGray}${CWhite} | ${CClear}${CDkGray}-  SMTP Server Port:          :"${CDkGray}$smtpport
      fi
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
              echo -e "${CCyan}example, if your main breaker is 200a @ 120v = 24,000w (24kW),"
              echo -e "${CCyan}or, if your main breaker is 200a @ 240v = 48,000w (48kW)."
              echo -e "${CYellow}(Default = 48)${CClear}"
              read -p 'Max Home Power: ' maxhomeelecload1
              maxhomeelecload=$maxhomeelecload1
            ;;

            8) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}8. Would you like to enable email notifications for major"
              echo -e "${CCyan}grid events? (Grid Down, Grid Syncing, Grid returning back"
              echo -e "${CCyan}to Normal). This will require you to enter in your email"
              echo -e "${CCyan}address, app password/email account password, smtp server"
              echo -e "${CCyan}address, smtp server port, and the recipient address the"
              echo -e "${CCyan}alert is going to. ${CYellow}Recommendation: Utilize a secure SSL"
              echo -e "${CYellow}SMTP server such as: smtp.gmail.com -- using port 465"
              echo -e "${CYellow}(Default = No)${CClear}"
              if promptyn "Enable Notifications? (y/n): "; then
                emailalerts="Enabled"
                echo ""
                echo ""
                echo -e "${CGreen}NOTE: Press ENTER at the prompt to use your previously"
                echo -e "${CGreen}saved entry.  You will have the opportunity to test your"
                echo -e "${CGreen}email settings and receive a test email at the end of this"
                echo -e "${CGreen}short list of questions.${CClear}"
                echo ""
                read -p 'Enter FROM Email Address: ' smtpusername1
                if [ ! -z "$smtpusername1" ]; then smtpusername=$smtpusername1; fi
                echo -e "${CGreen}Using: $smtpusername${CClear}"
                echo ""
                read -p 'Enter FROM Email Address Password: ' smtppassword1
                smtppassword=$(echo "${smtppassword}" | openssl enc -d -des3 -base64 -pass pass:*TB0c7ksKGWcw22P -pbkdf2)
                if [ ! -z "$smtppassword1" ]; then smtppassword=$smtppassword1; fi
                echo -e "${CGreen}Using: $smtppassword${CClear}"
                secretpwd=$(echo $smtppassword | openssl enc -e -des3 -base64 -salt -pass pass:*TB0c7ksKGWcw22P -pbkdf2)
                smtppassword=$secretpwd
                echo ""
                read -p 'Enter RCPT TO Email Address: ' smtprecipient1
                if [ ! -z "$smtprecipient1" ]; then smtprecipient=$smtprecipient1; fi
                echo -e "${CGreen}Using: $smtprecipient${CClear}"
                echo ""
                read -p 'Enter SMTP Server Address: ' smtpserver1
                if [ ! -z "$smtpserver1" ]; then smtpserver=$smtpserver1; fi
                echo -e "${CGreen}Using: $smtpserver${CClear}"
                echo ""
                read -p 'Enter SMTP Server Port: ' smtpport1
                if [ ! -z "$smtpport1" ]; then smtpport=$smtpport1; fi
                echo -e "${CGreen}Using: $smtpport${CClear}"
                echo ""
                echo -e "${CCyan}Would you like to test your settings and receive a test email?${CClear}"
                if promptyn "Test email notification settings? (y/n): "; then
                  emailalert test
                  echo ""
                  echo -e "${CGreen}Email sent.  Please check your inbox/junk mail folder!"
                  sleep 3
                fi
              else
                emailalerts="Disabled"
              fi
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
                echo 'emailalerts="'"$emailalerts"'"'
                echo 'smtpusername="'"$smtpusername"'"'
                echo 'smtprecipient="'"$smtprecipient"'"'
                echo 'smtppassword="'"$smtppassword"'"'
                echo 'smtpserver="'"$smtpserver"'"'
                echo 'smtpport='$smtpport
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
        echo 'maxhomeelecload=48'
        echo 'emailalerts="Disabled"'
        echo 'smtpusername="defaultsender@gmail.com"'
        echo 'smtprecipient="recipient@gmail.com"'
        echo 'smtppassword="U2FsdGVkX19IDBTBl5wMrbyLkj4VspYb"'
        echo 'smtpserver="smtp.gmail.com"'
        echo 'smtpport=465'
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
            if [ -f "/opt/bin/timeout" ] && [ -f "/opt/sbin/screen" ] && [ -f "/opt/bin/jq" ]; then
              vconfig
            else
              logoNM
              echo -e "${CYellow}Installing PWRMON Dependencies...${CClear}"
              echo ""
              echo -e "${CCyan}PWRMON has some dependencies in order to function correctly, namely,${CClear}"
              echo -e "${CCyan}CoreUtils-Timeout, JQuery and the Screen utility. These utilities ${CClear}"
              echo -e "${CCyan}require you to have Entware already installed using the AMTM tool. If${CClear}"
              echo -e "${CCyan}Entware is present, the Timeout, JQ and Screen utilities will ${CClear}"
              echo -e "${CCyan}automatically be downloaded and installed during this setup process.${CClear}"
              echo ""
              echo -e "${CGreen}CoreUtils-Timeout${CCyan} is a utility that provides more stability for${CClear}"
              echo -e "${CCyan}certain routers (like the RT-AC86U) which has a tendency to randomly${CClear}"
              echo -e "${CCyan}hang scripts running on this router model.${CClear}"
              echo ""
              echo -e "${CGreen}Screen${CCyan} is a utility that allows you to run SSH scripts in a standalone${CClear}"
              echo -e "${CCyan}environment directly on the router itself, instead of running your${CClear}"
              echo -e "${CCyan}commands or a script from a network-attached SSH client. This can${CClear}"
              echo -e "${CCyan}provide greater stability due to it running on the router itself.${CClear}"
              echo ""
              echo -e "${CGreen}JQuery${CCyan} is a utility for querying data locally or across the${CClear}"
              echo -e "${CCyan}internet through the means of APIs for the purposes of interacting${CClear}"
              echo -e "${CCyan}with your Tesla Powerwall Gateway to extract current power stats.${CClear}"
              echo ""
              [ -z "$(nvram get odmpid)" ] && RouterModel="$(nvram get productid)" || RouterModel="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic
              echo -e "${CCyan}Your router model is: ${CYellow}$RouterModel"
              echo ""
              echo -e "${CCyan}Ready to install?${CClear}"
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
                    echo ""
                    echo -e "${CGreen}Installing Entware Screen Package...${CClear}"
                    echo ""
                    opkg install screen
                    echo ""
                    echo -e "${CGreen}Installing Entware JQuery Package...${CClear}"
                    echo ""
                    opkg install jq
                    echo ""
                    echo -e "${CGreen}Install completed...${CClear}"
                    echo ""
                    read -rsp $'Press any key to continue...\n' -n1 key
                    echo ""
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
            echo -e "${CYellow}Force Re-installing PWRMON Dependencies...${CClear}"
            echo ""
            echo -e "${CCyan}Would you like to re-install the CoreUtils-Timeout, JQuery and the${CClear}"
            echo -e "${CCyan}Screen utility? These utilities require you to have Entware already${CClear}"
            echo -e "${CCyan}installed using the AMTM tool. If Entware is present, the Timeout,${CClear}"
            echo -e "${CCyan}JQ, and Screen utilities will be uninstalled, downloaded and${CClear}"
            echo -e "${CCyan}re-installed during this setup process.${CClear}"
            echo ""
            echo -e "${CGreen}CoreUtils-Timeout${CCyan} is a utility that provides more stability for${CClear}"
            echo -e "${CCyan}certain routers (like the RT-AC86U) which has a tendency to randomly${CClear}"
            echo -e "${CCyan}hang scripts running on this router model.${CClear}"
            echo ""
            echo -e "${CGreen}Screen${CCyan} is a utility that allows you to run SSH scripts in a standalone${CClear}"
            echo -e "${CCyan}environment directly on the router itself, instead of running your${CClear}"
            echo -e "${CCyan}commands or a script from a network-attached SSH client. This can${CClear}"
            echo -e "${CCyan}provide greater stability due to it running on the router itself.${CClear}"
            echo ""
            echo -e "${CGreen}JQuery${CCyan} is a utility for querying data locally or across the${CClear}"
            echo -e "${CCyan}internet through the means of APIs for the purposes of interacting${CClear}"
            echo -e "${CCyan}with your Tesla Powerwall Gateway to extract current power stats.${CClear}"
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
                  echo ""
                  echo -e "${CGreen}Force Re-installing Entware Screen Package...${CClear}"
                  echo ""
                  opkg install --force-reinstall screen
                  echo ""
                  echo -e "${CGreen}Force Re-installing Entware JQuery Package...${CClear}"
                  echo ""
                  opkg install --force-reinstall jq
                  echo ""
                  echo -e "${CGreen}Re-install completed...${CClear}"
                  echo ""
                  read -rsp $'Press any key to continue...\n' -n1 key
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

{ echo ""
} > $cookie_file

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

  #---testing---
  #sitename="My Tesla Site Name"

  clear
  logo
  if [ "$UpdateNotify" != "0" ]; then
    echo -e "${CRed}  $UpdateNotify${CClear}"
    echo -e "${CGreen} _______________${CClear}"
  else
    echo -e "${CGreen} _______________${CClear}"
  fi
  echo -e "${CGreen}/${CRed}Power Flow View${CClear}${CGreen}\__________________________________________________${CClear}"
  echo -e "                                                                      "
  echo -e "${CBlack}                             ${InvYellow}  SOLAR   ${CClear}    ${CGreen}SITENAME:${CClear}"
  echo -e "${CYellow}                              $solar kW     ${CClear}${CWhite}$sitename"
  echo -e "${CBlack}                             ${InvYellow}  \|/____ ${CClear}"
  echo -e "${CBlack}                             ${InvYellow} --O///// ${CClear}"
  echo -e "${CBlack}                             ${InvYellow}  //////  ${CClear}"
  echo -e "${CBlack}                             ${InvYellow} //////   ${CClear}"
  echo -e "${CYellow}                                $solarshowline${CClear}"
  echo -e "${CYellow}                                $solarshowline${CClear}"
  echo -e "         ${CWhite}${InvDkGray}   GRID   ${CClear}             ${CYellow}$solarshowline             ${CBlack}${InvCyan}   HOME   ${CClear}"
  echo -e "          $grid kW              ${CYellow}$solardirection1           ${CCyan}   $home kW${CClear}"
  echo -e "         ${CWhite}${InvDkGray}   - | +  ${CClear}             ${CYellow}$solardirection2             ${CBlack}${InvCyan}  /====\| ${CClear}"
  echo -e "         ${CWhite}${InvDkGray} ===||=== ${CClear}$gridshowlines${CBlack}${InvWhite}[GW]${CClear}$homeshowlines${CBlack}${InvCyan} /______\ ${CClear}"
  echo -e "         ${CWhite}${InvDkGray}     |    ${CClear}             ${CGreen}$batterydirection1             ${CBlack}${InvCyan} | |[]| | ${CClear}"
  echo -e "         ${CWhite}${InvDkGray} HI VOLTS ${CClear}             ${CGreen}$batterydirection2             ${CBlack}${InvCyan} ^^^^^^^^ ${CClear}"
  echo -e "                                ${CGreen}$batterydirection3               ${CClear}"
  echo -e "                                ${CGreen}$batterydirection4               ${CClear}"
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear} ${InvGreen}${CBlack} CONFIG ${CClear}"
  echo -e "                         ${InvWhite}${CBlack}    $battery kW      ${InvDkGray}${CGreen}|${CClear} ${InvDkGray}${CWhite} CHARGE:${CClear}${CWhite} $battcapp%${CClear}"
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear} ${InvDkGray}${CWhite} ALERTS:${CClear}${CWhite} $emailalerts${CClear}"
  echo -e "                         ${InvWhite}${CRed}    T E S L A     ${InvDkGray}${CGreen}|${CClear} ${InvDkGray}${CWhite}        ${CClear}"
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear} ${InvDkGray}${CWhite}        ${CClear}"
  if [ "$remaining" != "0" ]; then
  echo -e "                         ${InvWhite}${CRed}  $remaining/h runtime ${InvDkGray}${CGreen}|${CClear} ${InvDkGray}${CWhite}PW MODE:${CClear}${CWhite} $realmode${CClear}"
  else
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear} ${InvDkGray}${CWhite}PW MODE:${CClear}${CWhite} $realmode${CClear}"
  fi
  echo -e "                         ${InvWhite}                  ${InvDkGray}${CGreen}|${CClear} ${InvDkGray}${CWhite}RESERVE:${CClear}${CWhite} $backupreserve%${CClear}"
  echo -e "                         ${InvDkGray}${CWhite}  $numberpowerwalls POWERWALL(S)  ${CClear}"
  echo -e "${CGreen}___________________________________________________________________${CClear}"
  echo ""
}

# -------------------------------------------------------------------------------------------------------------------------

DisplayPage2 () {

  clear
  logo
  if [ "$UpdateNotify" != "0" ]; then
    echo -e "${CRed}  $UpdateNotify${CClear}"
    echo -e "${CYellow} _____${CClear}"
  else
    echo -e "${CYellow} _____${CClear}"
  fi
  echo -e "${CYellow}/${CBlack}${InvYellow}SOLAR${CClear}${CYellow}\____________________________________________________________${CClear}"
  echo -e ""

  solardisplay=$(echo $solar | awk '{printf "%f\n", $1}' | cut -d . -f 1)
  #echo $solardisplay
  if [ $solardisplay -gt $maxsolargen ]; then solardisplay=$maxsolargen; fi
  if [ $solardisplay -gt 0 ]; then
    preparebar 34 "|"
    progressbar $solardisplay $maxsolargen " Generated   " "kW" "Reverse" $solar
  else
    preparebar 34 "|"
    progressbar 0 $maxsolargen " Generated   " "kW" "Reverse" $solar
  fi
  echo ""
  echo -e "${CDkGray} ____${CClear}"
  echo -e "${CDkGray}/${CWhite}${InvDkGray}GRID${CClear}${CDkGray}\_____________________________________________________________${CClear}"
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

  echo -e "${CCyan} ____${CClear}"
  echo -e "${CCyan}/${CBlack}${InvCyan}HOME${CClear}${CCyan}\_____________________________________________________________${CClear}"
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
  echo -e "${CWhite} _______${CClear}"
  echo -e "${CWhite}/${CBlack}${InvWhite}BATTERY${CClear}${CWhite}\__________________________________________________________${CClear}"
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
  if [ $battdisplay -gt $battelecload ]; then battdisplay=$battelecload; fi
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
    battdisplay=$(echo $battery | awk '{printf "%f\n", $1*-1}' | cut -d . -f 1)
    if [ $battdisplay -gt $battelecload ]; then battdisplay=$battelecload; fi
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

DisplayPage3 () {

  clear
  logo
  if [ "$UpdateNotify" != "0" ]; then
    echo -e "${CRed}  $UpdateNotify${CClear}"
    echo -e "${CGreen} _________${CClear}"
  else
    echo -e "${CGreen} _________${CClear}"
  fi
  echo -e "${CGreen}/${CRed}Dashboard${CClear}${CGreen}\________________________________________________________${CClear}"
  echo ""
  fontprinter $solar "${InvYellow}" "Solar"
  echo ""
  fontprinter $grid "${InvDkGray}" "Grid"
  echo ""
  fontprinter $home "${InvCyan}" "Home"
  echo ""
  fontprinter $battery "${InvWhite}" "Battery"
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
        echo -e "${CCyan}IMPORTANT:${CClear}"
        echo -e "${CCyan}In order to keep PWRMON running in the background,${CClear}"
        echo -e "${CCyan}properly exit the SCREEN session by using: CTRL-A + D${CClear}"
        echo ""
        screen -wipe >/dev/null 2>&1 # Kill any dead screen sessions
        sleep 1
        screen -dmS "pwrmon" $APPPATH -monitor
        sleep 2
        echo -e "${CGreen}Switching to the SCREEN session in T-5 sec...${CClear}"
        echo -e "${CClear}"
        SPIN=5
        spinner
        screen -r pwrmon
        exit 0
      else
        clear
        echo -e "${CGreen}Connecting to existing PWRMON SCREEN session...${CClear}"
        echo ""
        echo -e "${CCyan}IMPORTANT:${CClear}"
        echo -e "${CCyan}In order to keep PWRMON running in the background,${CClear}"
        echo -e "${CCyan}properly exit the SCREEN session by using: CTRL-A + D${CClear}"
        echo ""
        echo -e "${CGreen}Switching to the SCREEN session in T-5 sec...${CClear}"
        echo -e "${CClear}"
        SPIN=5
        spinner
        screen -dr $ScreenSess
        exit 0
      fi
  fi

  # Check to see if the monitor option is being called and run operations normally
  if [ "$1" == "-monitor" ]
    then
      clear
      if [ -f $CFGPATH ] && [ -f "/opt/bin/timeout" ] && [ -f "/opt/sbin/screen" ] && [ -f "/opt/bin/jq" ]; then
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
        echo -e "$(date) - PWRMON ----------> ERROR: PWRMON is not configured. Please run the setup tool." >> $LOGFILE
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
  battcapp3=$(awk "BEGIN {printf \"%03.f\",${battcapp}}")
  battmult=$(awk "BEGIN {printf \"%.2f\",${battcapp}/100}")
  battelecload=$(awk "BEGIN {printf \"%.0f\",${numpowerwalls}*5}")

  status=$(curl -s -S -k -b "$cookie_file" "https://$gatewayip/api/system_status/grid_status")
  gridstatus=$(echo $status | jq '.grid_status' | tr -d '"')

  pwstatus=$(curl -s -S -k -b "$cookie_file" "https://192.168.86.63/api/operation")
  realmode=$(echo $pwstatus | jq '.real_mode' | tr -d '"')
  backupreserve=$(echo $pwstatus | jq '.backup_reserve_percent' | cut -d . -f 1)
  if [ $realmode == "self_consumption" ]; then
    realmode="Self-Powered"
  elif [ $realmode == "backup"]; then
    realmode="Backup"
  elif [ $realmode == "autonomous"]; then
    realmode="Time-Based"
  else
    realmode="Unknown"
  fi

  numberpowerwalls=$(awk "BEGIN {printf \"%02.f\",${numpowerwalls}}")

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

  #---testing---
  #gridstatus="SystemIslandedActive"
  if [ "$gridstatus" == "SystemIslandedActive" ]; then
    gridshowlines="${CRed}XX${CWhite}${InvRed}|OUTAGE|${CClear}   "
    echo -e "$(date) - PWRMON ---------> GRID OUTAGE - Providing power from battery! $battcapp% remaining!" >> $LOGFILE
    griddown=1
    emailalert griddown

  elif [ "$gridstatus" == "SystemTransitionToGrid" ]; then
    gridshowlines="${CYellow}>>${CBlack}${InvYellow}|SYNCING|${CClear}  "
    echo -e "$(date) - PWRMON ---------> GRID SYNCING - Powerwalls and Gateway are Syncing!" >> $LOGFILE
    griddown=1
    emailalert sync
  fi

  if [ "$gridstatus" != "SystemIslandedActive" ] && [ "$gridstatus" != "SystemTransitionToGrid" ] && [ "$griddown" == "1" ]; then
    echo -e "$(date) - PWRMON ---------> GRID ONLINE - Powerwalls and Gateway returning to normal operations at $battcapp% remaining!" >> $LOGFILE
    griddown=0
    emailalert normal
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
              [Nn]) if [ "$NextPage" == "1" ]; then NextPage=2; clear; DisplayPage2; elif [ "$NextPage" == "2" ]; then NextPage=3; clear; DisplayPage3; elif [ "$NextPage" == "3" ]; then NextPage=1; clear; DisplayPage1; fi;;
              [Pp]) if [ "$NextPage" == "1" ]; then NextPage=3; clear; DisplayPage3; elif [ "$NextPage" == "2" ]; then NextPage=1; clear; DisplayPage1; elif [ "$NextPage" == "3" ]; then NextPage=2; clear; DisplayPage2; fi;;
              [Ww]) (weathercheck);;
              [Ee]) echo -e "${CClear}"; exit 0;;
          esac
      fi
  done

#read -rsp $'Press any key to continue...\n' -n1 key

done

exit 0
