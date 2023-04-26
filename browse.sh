#!/bin/bash  
#
# Copyright 2019-2023 Red Tuby PE1RRR
#
# browse.sh is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# LinBPQ/BPQ32 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with browse.sh.  If not, see http://www.gnu.org/licenses

Version="0.3.5 by PE1RRR updated Wednesday 2023-04-26"
#
# Configuration
# 
LynxBin="/usr/bin/lynx"  # sudo apt install lynx
CurlBin="/usr/bin/curl"  # sudo apt install curl

# Do you want to log requests? 1=Yes 0=No
LogRequests=1

# Logfile location
WebLogFile="/var/log/bpq-browser.log" 

# Ensure this location is owned & writable by the user running this script. i.e:
#   sudo touch /var/log/bpq-browser.log
#   sudo chown pi:pi /var/log/bpq-browser.log
# Change 'pi' to your whichever username and group the script runs with..

# Link to your start page
PortalURL="http://matrix.ehvairport.com/~bpq/"

# It is recommended to set up a proxy server locally to handle the requests from this script
# it adds a level of control over which content can and cannot be requested, squid proxy is
# utilized for this, but if you do not want to use it, comment the 3 lines out below.
# I have set up my squid proxy to use alternate DNS servers of OpenDNS FamilyShield.

myproxy="http://127.0.0.1:3128"
export http_proxy=$myproxy
export https_proxy=$myproxy
# 
# Usage & Installation
#
# For simplicity, I use openbsd's inetd which is available for Debian/Raspbian with sudo apt install openbsd-inetd
# 
# Add the following line to /etc/inetd.conf
# 
# browse		stream	tcp	nowait	bpq		/full/path/to/your/packet-scriptlets/browse.sh client ax25
# 
# The word 'bpq' above refers to the userid that this process will run under.
#
# Add the following line to /etc/services and make a note of the port number you choose. Make sure the one you pick does
# not exist and is within the range of ports available.
#
# browse		63004/tcp   # Browser
# 
# Enable inetd: sudo systemctl enable inetd
#               sudo service inetd start
#
# In bpq32.cfg add the port specified above (63004) to the BPQ Telnet port list, CMDPORT= 
#
# Note the port's position offset in the list as that will be referenced in the APPLICATION line next.
# The first port in the CMDPORT= line is position 0 (zero), the next would be 1, then 2 and so on.
#
# Locate your APPLICATION line definitions in bpq32.cfg and another one next in the sequence. Make
# sure it has a unique <app number> between 1-32.
#
# Syntax: 
# APPLICATION <app number 1-32>,<node command>,<node instruction>
#
# APPLICATION 25,WEB,C 10 HOST 1 S
#
# <node instruction> is where the command 'web' is told to use BPQ port 10 (the telnet port, yours may be different!)
# HOST is a command to tell BPQ to look at the BPQ Telnet CMDPORT= list, and '1' is to pick offset position 1, that
# in turn resolves to TCP port 63004. The 'S' tells the node to return the user back to the node when they exit
# the web portal instead of disconnecting them, it refers to the word 'Stay'.

# Further config is at the bottom of the file for customization of the menu options as well as welcome message.
##### End of Config - Do not change anything below here.
#
# Global Vars
LinkRegex='https?:\/\/|[-a-zA-Z0-9@:%._\+\-~#=]{1,256}\.[a-zA-Z0-9()]{1,7}\b([-a-zA-Z0-9()@:%_\+.~#\?\&//=]*)'
NewLinkRegex='(^n\ )((https?:\/\/|)[-a-zA-Z0-9@:%._\+\-~#=]{1,256}\.[a-zA-Z0-9()]{1,7}\b([-a-zA-Z0-9()@:%_\+.~#\?\&//=]*))$'
QuitCommandRegex='^(0|q|b)$'
MenuCommandRegex='^(m)$' 
ListCommandRegex='^(l)$'
BackCommandRegex='^(p)$'
FullCommandRegex='^(f)$'
OptionPagingRegex='^(op)(\ )([0-9]{1,2})$'
SearchRegex='^(s)(\ )([a-zA-Z0-9@:%\._\+~#=].+)'
RedisplayCommandRegex='^(r)$'
HelpCommandRegex='^(h|\?)$'
WarningLimit=15
Referrer="none"
UserAgent="Packet Radio Portal $Version L_y_n_x"
#CurlUserAgent="Mozilla/5.0 (X11; U; Linux armv7l like Android; en-us) AppleWebKit/531.2+ (KHTML, like Gecko) Version/5.0 Safari/533.2+ Kindle/3.0+"
declare -A GlobalLinkArray # I'm an associative array!
GlobalTextString=""

set -e
trap 'catch $? $LINENO' EXIT
catch() {
	if [ "$1" != "0" ]; 
	then
		# error handling goes here
		echo "Unexpected Error! Restarting..."
		Prompt "${PortalURL}"
		exit
      	fi
}




function CheckURLSanity() {
	local CheckURL=$1
	local ContentType
	local ContentTypeRegex

	# Ignore case with ,, below
	if ! [[ ${CheckURL,,} =~ $LinkRegex ]]
	then 
	    ReturnVal="Error: Not a valid URL"
	    return 1
	fi

	# Ignore case with ,, below
	if [[ ${CheckURL,,} =~ ^(gopher:|mailto:|ftp:|file:).*$ ]]
	then
		ReturnVal="Error: Only http or https."
		return 1
	fi

	if $CurlBin -H "${UserAgent}" --output /dev/null --silent --connect-timeout 5 --head --fail "${CheckURL}"; then
		ContentType=$($CurlBin -H "${UserAgent}" -s -L -I --connect-timeout 5 --head -XGET "${CheckURL}" --output /dev/null -w '%{content_type}\n')
		#echo "Content: $ContentType"
		ContentTypeRegex='^(text\/html|text\/plain).*$'
		if  ! [[ $ContentType =~ $ContentTypeRegex ]] 
		then
			ReturnVal="Error: Not text."
			return 1
		fi
		return 0
 	else
		ReturnVal="Error: Page not found"
		return 1
	fi	

}

function Quit() {
	echo "Exiting... Bye!"
	exit
}

function OptionPaging() {
	local PageSize
	local PageSizeClean
	local Referrer

	PageSize=$1
	Referrer=$2
	PageSizeClean=${PageSize//[$'\t\r\n']} && PageSize=${PageSize%%*( )}

	[[ $PageSizeClean =~ $OptionPagingRegex ]] && WarningLimit=`echo  ${BASH_REMATCH[3]}`
	echo "Paging is $WarningLimit lines per page"
	Prompt "${Referrer}"
}


function Search() {
	local Query
	local QueryURL
	local Referrer
	Referrer="$1"

	[[ $ChoiceClean =~ $SearchRegex ]] && Query=`echo  ${BASH_REMATCH[3]}`
	echo "Wikipedia Search. Note: All queries are logged"
	echo "Processing: $Query. Please wait."
	
	Query=`echo $Query | sed -e 's/ /%20/g'` 
	Query=`echo $Query | sed -e 's/\"/%22/g'` 
	Query=`echo $Query | sed -e 's/\&/%26/g'` 
	#QueryURL="http://lite.duckduckgo.com/lite/?&q=${Query}"
	QueryURL="https://en.m.wikipedia.org/w/index.php?title=Special:Search&ns0=1&search=${Query}"

	FetchPage "${QueryURL}" "${QueryURL}"

	# Prompt Menu
	Prompt "$Referrer" 
}

function NewLink() {
	local Address
	local Referrer
	local URL
	local URLFix
	local Text

	local Query
	local QueryURL
	 [[ $ChoiceClean =~ $NewLinkRegex ]] && Address=`echo  ${BASH_REMATCH[2]}`
	
	# Trim Input
	URLFix=${Address//[$'\t\r\n']} && Address=${Address%%*( )}

	# If entered URL doesnt have a http/https prefix
	if [[ $URLFix =~ ^https?:\/\/ ]]
	then
		URL="${URLFix}"
	else
		# Default to http
		URL="http://${URLFix}"
	fi

	echo "Processing ${URL}..."

	# Update Last Page Global

	LogUser "${Address}"
	FetchPage "${URL}" "${Referrer}"
}

function FetchPage() {
	# Menu->[FetchPage->DownloadPage]->DisplayPage
	echo "Wait..."
	local URL
	local Referrer
	local Links

	URL=$1
	Referrer=$2

	# Fetch Page and populate Global arrays.
	DownloadPage "${URL}" "${Referrer}"

	# Display The Page
	LineCount=0
	PageBytes=`echo -n "${GlobalTextArray[@]}" | wc -c`
	LineCount=${#GlobalTextArray[*]}

	if [ $LineCount -gt $WarningLimit ]
	then
		echo "Display ${LineCount} lines (${PageBytes} Bytes), continue? (y/N)"
			unset AskThem
			local AskThem
			read AskThem
			AskThem=`echo $AskThem | tr '[:upper:]' '[:lower:]'`
			AskThemClean=${AskThem//[$'\t\r\n']} && AskThem=${AskThem%%*( )}
			if ! [[ $AskThemClean =~ ^(y).*$ ]]
			then
				echo "Use [R] if you change your mind... (Redisplay)"
				Prompt "${Referrer}"
			fi
	fi

	DisplayPage "${URL}" "${Referrer}" 
}

function DisplayPage() {
	# Menu->FetchPage->[DisplayPage]
	local OldIFS
	local OutCount
        local AbortState
        local AbortStateClean
	local TotalCount
	local Output
	local CancelPaging
	local URL
	local Referrer

	URL=$1
	Referrer=$2

#	echo -e "Displaying ${URL}"

	OutCount=0
	TotalCount=0
	if [[ ${FetchFullText} == "1" ]]
	then
		echo -e "$GlobalFullTextString"

	else
	OldIFS=$IFS
	IFS=$'\n'
	for Output in "${GlobalTextArray[@]}"
	do
		if [ $OutCount -eq $WarningLimit ] && [ "$CancelPaging" != "1" ]
		then
			echo "ENTER = continue, A = Abort, C = Cancel Paging, [Line ${TotalCount}/${LineCount}]"
			#echo "OP <1-99> = Set Pagesize."
			read AbortState
			AbortState=`echo $AbortState | tr '[:upper:]' '[:lower:]'`
			AbortStateClean=${AbortState//[$'\t\r\n']} && AbortState=${AbortState%%*( )}
			if [[ $AbortStateClean =~ ^(a|q)$ ]]
			then
				echo "Output Aborted!"
				Prompt "${Referrer}"
			elif [[ $AbortStateClean =~ ^(n)$ ]]
			then
				OutCount=0
			elif [[ $AbortStateClean =~ ^(c)$ ]]
			then
				echo "Cancelled paging... displaying rest of page"
				CancelPaging=1
				continue
			elif [[ $AbortStateClean =~ $OptionPagingRegex ]]
			then
				OptionPaging "${AbortStateClean}" "${Referrer}"
				OutCount=0
			elif [[ $AbortStateClean =~ ^([0-9]{1,4})$ ]]
			then
				# Load a page directly from the paged list
				LoadPage "${AbortStateClean}" "${Referrer}"
			else
				# Treat anything else, like Enter, as a nope.
				OutCount=0
			fi
		fi
		echo "$Output"
		OutCount=$((OutCount+1))
		TotalCount=$((TotalCount+1))
	done
	fi

	CancelPaging=0
	IFS=$OldIFS
	Prompt "${Referrer}"
}

function LogUser() {
	local URL
	local Date

	URL=$1
	Date=`date`

	if [ ${LogRequests} == "1" ]
	then
		if ! [ -e ${WebLogFile} ]
		then
			touch ${WebLogFile}
		fi
		echo "${Date}: ${Callsign} requested ${URL}" >> ${WebLogFile}
	fi
}

function DownloadPage() {
	local URL
	local Referrer
	local OldIFS
        local Text
	local TextLine
	local Links
	local IndexRegex
	local HttpRegex
	local IndexID

	URL=$1
	Referrer=$2

	# Sanity Check the URL
	if ! CheckURLSanity "${URL}"
	then 
		echo $ReturnVal
		unset ReturnVal
		Prompt "${Referrer}}"
	fi


	# Inits
	GlobalTextArray=()
	OldIFS=$IFS
	IFS=$'\n'

	Text=`$LynxBin -selective -useragent=${UserAgent}  -connect_timeout=10 -unique_urls -number_links -hiddenlinks=ignore -nolist -nomore -justify -dump  ${URL}`

	GlobalFullTextString="$Text"
	GlobalTextString=""
	for TextLine in ${Text}
	do
		# Array Method
		GlobalTextArray+=($TextLine)
		# String Method
		GlobalTextString+="$TextLine"
	done

	# Clean up any previous data
	GlobalLinkArray=()
	GlobalLinkString=""
	IndexID=""

	# Fetch Link List
 	Links=`${LynxBin} -selective -useragent=${UserAgent}  -connect_timeout=10 -hiddenlinks=ignore -dump -unique_urls -listonly ${URL}`

	# SOME Pages will return links that Lynx will skip over yet still increments the Lynx link number displayed...
	# This logic sets the links into an array where the index of the array is identical to the link number Lynx displayed.

	for LinkLine in ${Links}
	do
		IndexRegex='^((\ )+|)+([0-9]+)' # Bleugh, scrape away text formatting to get ID 
		HttpRegex='(https?.*)' # Barf
		[[ $LinkLine =~ $IndexRegex ]] && IndexID=`echo ${BASH_REMATCH[0]} | xargs`  # Trim the whitepaces
		if  [ -z $IndexID ]; then 
			# There's always one, grrr. Lynx returns a line "References" before the link list...
			# Skip anything that doesn't start with a sane index number
			continue
		fi
		[[ $LinkLine =~ $HttpRegex ]] && HttpURL=${BASH_REMATCH[0]} # It's an URL baby.
		HttpURL=`echo $HttpURL | sed -e 's/ /%20/g'` # Fix for URL item with spaces

		# Hacks for specific sites- DuckDuckGo
		#HttpURL=`echo $HttpURL | sed -e 's/https:\/\/duckduckgo.com\/l\/?uddg=//g'` # Fudge search results to stop redirects polluting the link list
		#HttpURL=`echo $HttpURL | sed -e 's/\&rut=.*//g'` # Fudge search results to stop redirects polluting the link list

		# Associative Array Method
		GlobalLinkArray[$IndexID]=$HttpURL
		# Build the human readable list of links
		GlobalLinkString+="$IndexID = $HttpURL|"
	done
	IFS=$OldIFS
}

function Prompt() {
	local Referrer

	Referrer=$1

	# Prompt
	local Choice
	echo "[H] for Help -->"
	read Choice
	Choice=`echo $Choice | tr '[:upper:]' '[:lower:]'`

	# Trim Input
	local ChoiceClean
	ChoiceClean=${Choice//[$'\t\r\n']} && Choice=${Choice%%*( )}

	# Handle Link Choice
	local ChoiceRegex
	ChoiceRegex='^([0-9]{1,4})$' 
#
	if [[ $ChoiceClean =~ $QuitCommandRegex ]] 
	then
		Quit
	elif [[ $ChoiceClean =~ $FullCommandRegex ]] 
	then
		FullText
	elif [[ $ChoiceClean =~ ^(op)$ ]]
	then
		echo "Lines Per Page: $WarningLimit"
		Prompt
	elif [[ $ChoiceClean =~ $ListCommandRegex ]] 
	then
		LinkList
	elif [[ $ChoiceClean =~ $NewLinkRegex ]] 
	then
		GlobalLinkArray=()
		GlobalTextArray=()
		NewLink
	elif [[ $ChoiceClean =~ $SearchRegex ]] 
	then
		GlobalLinkArray=()
		GlobalTextArray=()
		Search
	elif [[ $ChoiceClean =~ $RedisplayCommandRegex ]] 
	then
		echo -e "Redisplaying Page..."
		DisplayPage "${Referrer}"
	elif [[ $ChoiceClean =~ $OptionPagingRegex ]] 
	then
		OptionPaging "$ChoiceClean"
	elif [[ $ChoiceClean =~ $HelpCommandRegex ]] 
	then
		Help "${Referrer}"
	elif [[ $ChoiceClean =~ $MenuCommandRegex ]] 
	then
		GlobalLinkArray=()
		GlobalTextArray=()
		Initialize
	elif [[ $ChoiceClean =~ $BackCommandRegex ]]
	then
		if [[ ${Referrer} == "" ]]
		then
			echo "Error: We can't go there!"
			Prompt "${PortalURL}" 
			exit
		else
			GlobalLinkArray=()
			GlobalTextArray=()
			FetchPage "${Referrer}" "${Referrer}"
		fi
	elif  [[ $ChoiceClean =~ $ChoiceRegex ]] 
	then
		# So an actual link ID has been requested...
		LoadPage "${ChoiceClean}" "${Referrer}"
	else

		echo "Error: Oops! Try H for Help"
		Prompt "${Referrer}" # Again
		exit
	fi

}

function FullText() {
		if [[ $FetchFullText == "1" ]]
	       	then
			FetchFullText=0
			echo "Paged Mode Set"
		else
			FetchFullText="1"
			echo "Fully Formatted Full Page Mode Set"
		fi

		Prompt
}

function Help() {
	local Referrer
	Referrer=$1

		echo -e "Navigate pages using the number highlighted between [ ]"
		echo -e "To view a particular page, enter just the page number."
		echo -e ""
		echo -e "If the page is longer than ${WarningLimit} lines, you"
		echo -e "will be prompted with the choice to continue or not."
		echo -e ""
		echo -e "Commands:"
		echo -e "F - Toggled between Formatted Full Page and Paged"
		echo -e "    Note: Paged (default) is also fully condensed"
		echo -e "H - This text"
		echo -e "L - List hyperlinks associated with the numbers"
		echo -e "N <url> - Open <url>"
		echo -e "M - Main Menu"
		echo -e "OP <1-99> - Set Lines Per Page. OP<enter> shows."
		echo -e "S <text> - Search Wikipedia* for <text>"
		echo -e "Q/B - Quit/Bye"
		echo -e ""
		echo -e "*Unstable/work in progress"
		echo -e ""
		Prompt "${Referrer}"
}

function LoadPage() {
	local LinkURL
	local Referrer
	Position=$1
	Referrer=$2

	LinkURL="${GlobalLinkArray[${Position}]}"


	if ! [[ $LinkURL =~ $LinkRegex ]]
	then 
		echo "Error: Sorry, ${LinkURL} cannot be accessed via this portal."
		Prompt "${Referrer}" # Again
	fi
	
	LogUser "${LinkURL}"
	FetchPage "${LinkURL}" "${Referrer}"
}


function LinkList() {
	local OutCount
	local LineCount
	local TotalCount
	local CancelPaging
	
	LineCount=${#GlobalLinkArray[*]}
	echo "Displaying ${LineCount} hyperlinks"
	OutCount=0
	TotalCount=0
	OldIFS=$IFS
	IFS=$'|'
	for Output in $GlobalLinkString
	do
		if [ $OutCount -eq $WarningLimit ] && [ "$CancelPaging" != "1" ]
		then
			echo "ENTER = continue, A = Abort, C = Cancel Paging. [Line ${TotalCount}/${LineCount}]"
			#echo "OP <1-99> = Set Pagesize."
			read AbortState
			AbortState=`echo $AbortState | tr '[:upper:]' '[:lower:]'`
			AbortStateClean=${AbortState//[$'\t\r\n']} && AbortState=${AbortState%%*( )}
			if [[ $AbortStateClean =~ ^(a|q)$ ]]
			then
				echo "Output Aborted!"
				Prompt "${Referrer}"
			elif [[ $AbortStateClean =~ ^(n)$ ]]
			then
				OutCount=0
			elif [[ $AbortStateClean =~ ^(c)$ ]]
			then
				echo "Cancelled paging... displaying rest of page"
				CancelPaging=1
				continue
			elif [[ $AbortStateClean =~ $OptionPagingRegex ]]
			then
				OptionPaging "${AbortStateClean}"
				OutCount=0
			elif [[ $AbortStateClean =~ ^([0-9]{1,4})$ ]]
			then
				# Load a page directly from the paged list
				LoadPage "${AbortStateClean}" "${Referrer}"
			else
				# Treat anything else, like Enter, as a nope.
				OutCount=0
			fi
		fi
		echo $Output
		OutCount=$((OutCount+1))
		TotalCount=$((TotalCount+1))
	done
	CancelPaging=0
	IFS=$OldIFS	
	Prompt ${Referrer}
}

function Initialize() {
	        local Referrer	
		Referrer=$PortalURL
		GlobalLinkString=""
		GlobalLinkArray=()
		GlobalTextArray=()
		FetchPage "${PortalURL}" "${Referrer}"
}

function WelcomeMsg() {
	local Callsign
	Callsign=$1
	echo "Hi ${Callsign}, WWW V${Version}"
	echo "Page navigation numbers are highlighted with [ ]"
	return 0
}

function CheckCallsign() {
	local Call
	local CallsignRegex

	Call=$1
	CallsignRegex="[a-zA-Z0-9]{1,3}[0123456789][a-zA-Z0-9]{0,3}[a-zA-Z]"

	if [[ $Call =~ $CallsignRegex ]] 
	then
		return 0
	else
		return 1
	fi
}


# Inetd Connectivity- BPQ Node Connect and Telnet IP connect are handled differently.
Client=$1
if [ -z $Client ] 
then
	echo "Misconfigured, please ensure this script is called with the 'client <ip/ax25>' argument from inetd"
	exit
	fi

if [ ${Client} == "ip" ]
then
	# Connection from 2nd param of inetd after 'client' on 'ip' port so standard telnet user is prompted for a callsign.
	echo "Please enter your callsign:"
	read CallsignIn
elif	[ ${Client} == "ax25" ]
then
	# Connection came from a linbpq client on 'ax25' port which by default sends callsign on connect.
	read CallsignIn
fi

# Trim BPQ-Term added CRs and Newlines.
Callsign=${CallsignIn//[$'\t\r\n']} && CallsignIn=${CallsignIn%%*( )}
# Get rid of SSIDs
CallsignNOSSID=`echo ${Callsign} | cut -d'-' -f1`


# Check Validity of callsign
if ! CheckCallsign "${CallsignNOSSID}"
then
	echo "Error: Invalid Callsign..."
	Quit
	exit
fi

WelcomeMsg "${CallsignNOSSID}"
Initialize
