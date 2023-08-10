#!/usr/bin/env bash
################################################################################
# This script provides access the server api for interacting with the
# VMware infrastructure.
#
# Written by Matt Fiscus <m@fisc.us>
# Date: 6/8/2012
# Last Update: 7/17/2013
################################################################################


### define global variables

# script name must be defined prior to sourcing in json library
[ -z "${SCRIPT}" ] && export SCRIPT=${0##*/}


# get library path
[ -z "${LIBDIR}" ] && export LIBDIR=$( dirname ${0} )


# specify library file
[ -z "${LIBFILE}" ] && readonly LIBFILE="JSONlib.sh"


# look for library (should be in same directory as this script)
[ -z "${LIBRARY}" ] && readonly LIBRARY=$( type -p ${LIBDIR}/${LIBFILE} )


# require the json library
[ -s "${LIBRARY}" ] && source ${LIBRARY}


# get process identifier
[ -z "${PID}" ] && export PID=${$}


# work around for vMA 4.1.0/CentOS release 5.3 arrow keymap bug
# setting TERM to xterm applies keymap that enables arrow keys in dialog
[[ ${TERM} != "xterm" ]] && export TERM=xterm


# get logname
[ -z "${LOGNAME}" ] && readonly LOGNAME=$( logname )


# api key used to identify client application
[ -z "${APIKEY}" ] && readonly APIKEY="UGhhcm1hY3kgU3VwcG9ydAo="


# api server hostname
[ -z "${APIHOST}" ] && readonly APIHOST="api.fisc.us"


# tcp port that api is running on
[ -z "${APIPORT}" ] && readonly APIPORT="443"


# application branding
[ -z "${BRAND}" ] && readonly BRAND="fisc.us"


# application name
[ -z "${APPNAME}" ] && readonly APPNAME="Server Tools Utility"


# ssl certificate file
[ -z "${CERTIFICATE}" ] && readonly CERTIFICATE=$( mktemp -t cert-XXXXXXXX )


# function to clean up prior to exit
function postRun() {
    [ -a "${CERTIFICATE}" ] && rm -f ${CERTIFICATE}
    [ -z "${toolarg}" ] && dialog --clear
    
}


# trap SIGHUP/SIGINT/SIGKILL/SIGTERM
trap "postRun && exec 'kill -ABRT ${PID}' 1>/dev/null 2>&1" HUP INT KILL TERM


# function to catch error messages
# $1 = error message
# $2 = exit code
function throwError() {
    # validate arguments
    if [ $# -eq 2 ]; then
        # clean up
        postRun
        
        # log error messsage to syslog and write to STDERR
        logger -s -t ${SCRIPT}"["${LOGNAME}"]" -- ${1}
        
        # exit with provided code
        exit ${2}
        
    else
        # clean up
        postRun
        
        # log error messsage to syslog and write to STDERR
        logger -s -t ${SCRIPT}"["${LOGNAME}"]" -- "an unknown error occured"
        exit 255
        
    fi
    
}


# function to delete object
function deleteObject() {
    # declare variables local to this function
    local delete
    
    # delete api object
    for delete in ``items()``; do
        unset $delete
        
    done
    
}


# function to log api interactions
# $1 = object
function eventLog() {
    if [ $# -eq 1 ]; then
        # declare variables local to this function
        local message property
        
        # delete original object and parse new one
        deleteObject && tickParse "${1}"
        
        # serialize object properties
        for property in ``items()``; do
            # ignore date property
            [[ ${property} != "__tick_data_date" ]] && message=${message}$( echo ${property}" => '" | sed s/__tick_data_//g )${!property}"', "
            
        done
        
        # strip trailing comma
        message=$( echo ${message} | sed 's/,*$//' )
        
        # log event to syslog
        logger -t ${SCRIPT}"["${LOGNAME}"]" -- ${message}
        
    fi
    
}


# function to display result
# $1 = post result
function displayResult() {
    # validate argument
    if [ $# -eq 1 ]; then
        # Do not display dialog if command-line arguments are provided
        if [ ! ${toolarg} ]; then
            dialog \
                --shadow \
                --clear \
                --backtitle "${BRAND} ${APPNAME}" \
                --msgbox "Result:\n\n${1}" 14 40
            
        else
            echo ${1}
            
        fi
    else
        return 1
        
    fi
    
}


# function to confirm selection
# $1 = object
function confirmAction() {
    # validate argument
    if [ $# -eq 1 ]; then
        # declare variables local to this function
        local message property confirmation c choice choiceCount=0
        
        # delete original object and parse new one
        deleteObject && tickParse "${1}"
        
        # serialize object properties
        for property in ``items()``; do
            # ignore date property
            [[ ${property} != "__tick_data_date" ]] && message=${message}$( echo ${property}": " | sed s/__tick_data_//g )${!property}"\n"
            
        done
        
        # strip trailing comma
        message=$( echo ${message} | sed 's/\\n*$//' )
        
        confirmation="
            dialog \\
                --shadow \\
                --clear \\
                --cancel-label \"Cancel\" \\
                --backtitle \""${BRAND}" "${APPNAME}"\" \\
                --inputbox \"You have chosen:\n\n"${message}"\n\nType CONFIRM: \" 14 40"
        
        
        # launch dialog and split output into an array
        for c in $( eval "${confirmation}" 3>&2 2>&1 1>&3; echo ", "${?} ); do
            choice[${choiceCount}]=$( echo ${c} | sed 's/,*$//' )
            let choiceCount++
            
        done
        
        # case insensitivity CONFIRM=confirm=CoNfIrM
        shopt -s nocasematch
        
        # case return value
        case "${choice[0]}" in
            "CONFIRM") # positive confirmation
                # just in case the object has a null property
                if [ -n "${choice[0]}" ]; then
                    # return true
                    return 0
                    
                else
                    # this shouldn't happen unless the api is broken
                    throwError "undefined object property" 1
                    
                fi
                ;;
                
            *)  # negative confirmation
                # return to the main menu
                dialog \
                    --shadow \
                    --clear \
                    --sleep 1 \
                    --backtitle "${BRAND} ${APPNAME}" \
                    --infobox "Canceling request" 3 22
                
                deleteObject || throwError "unable to delete object" 1 \
                && getObject "${APIHOST}" "${APIPORT}" || throwError "could not establish connection to "${APIHOST} 1 \
                && getTools || throwError "unable to traverse api object" 1 \
                && mainMenu || throwError "could not load main menu" 1
                return 1
                ;;
                
        esac
        
    fi
    
}


# function to display wait message
# $1 = object
function pleaseWait() {
    dialog \
        --shadow \
        --backtitle "${BRAND} ${APPNAME}" \
        --infobox "Processing request" 3 23
        
}


# function to extract payload
function extractCertificate() {
    # declare variables local to this function
    local match payload
    
    # find the embedded certificate
    match=$( grep --text --line-number '^CERTIFICATE:$' $( type -p ${LIBDIR}/${SCRIPT} ) | cut -d ':' -f 1 )
    payload=$(( match + 1 ))
    
    # decode and extract the certificate to /tmp
    tail -n +${payload} $( type -p ${LIBDIR}/${SCRIPT} ) | uudecode > ${CERTIFICATE}
    
}


# function to download object
# $1 = hostname
# $2 = port
function getObject() {
    # validate arguments
    if [ $# -eq 2 ]; then
        # check to make we can open a tcp connection to the api server
        if portScan "${1}" "${2}"; then
            [ ! -s ${CERTIFICATE} ] && extractCertificate
            
            # url of the api
            local url="https://"${1}":"${2}"/"
            
            # download and parse the json object
            tickParse "$( curl --silent --cacert ${CERTIFICATE} --insecure --data key=${APIKEY} ${url} 2>/dev/null )"
            
        else
            return ${?}
            
        fi
        
    else
        return 1
        
    fi
    
}


# function to scan port on specified host
# $1 = hostname
# $2 = port
function portScan() {
    if [ $# -eq 2 ]; then
        ( >/dev/tcp/${1}/${2} ) >/dev/null 2>&1
        return ${?}
        
    else
        return 1
        
    fi

}


# function to get info from json object
# $1 = tool
# $2 = name/description/parameters
function getInfo() {
    # validate arguments
    if [ $# -eq 2 ]; then
        # declare variables local to this function
        local info
        
        for info in ``items()``; do
            [[ `echo ${info} | grep -c _$1_$2` != 0 ]] && echo "${!info}"
            
        done
        
    else
        return 1
        
    fi
    
}


# function to get tool commands
function getTools() {
    # declare variables local to this function
    local count=0 tool
    
    for tool in ``tool.items()``; do
        if [[ `echo ${tool} | grep -c _name` != 0 ]]; then
            tools[${count}]=$( echo ${tool} | sed s/__tick_data_tool_//g | sed s/_name//g )
            let count++
            
        fi
        
    done
    
}


# function to get tool parameters
# $1 = tool
function getParameters() {
    # validate argument
    if [ $# -eq 1 ]; then
        # declare variables local to this function
        local parameterCount=1 i parameters=( $(getInfo "${1}" "parameters") ) options j parameterOptions k parameterOptionCount c choice choiceCount
        
        for i in "${!parameters[@]}"; do
            local options="
                dialog \\
                    --shadow \\
                    --clear \\
                    --cancel-label \"Back\" \\
                    --backtitle \""${BRAND}" "${APPNAME}"\" \\"
                
            for j in "${parameters[i]}"; do
                parameterOptions=$( getParameterOptions "${j}" )
                
                # generate radio list for any parameter options
                if [ -n "${parameterOptions}" ]; then
                    options=${options}"
                    --radiolist \"Select an option:\" 14 22 7 \\"
                    
                    parameterOptionCount=0
                    for k in ${parameterOptions}; do
                        # select first radiolist option by default
                        [[ ${parameterOptionCount} == 0 ]] && selected="ON" || selected="OFF"
                        options=${options}"
                        \""${k}"\" \"\" \""${selected}"\" \\"
                        let parameterOptionCount++
                        
                    done
                    
                else
                    options=${options}"
                    --inputbox \"Please enter: "${parameters[$i]}"\" 8 32"
                    
                fi
                
            done
            
            
            # launch menu and split output into an array
            choiceCount=0
            for c in $( eval "${options}" 3>&2 2>&1 1>&3; echo ", "${?} ); do
                choice[${choiceCount}]=$( echo ${c} | sed 's/,*$//' )
                let choiceCount++
                
            done
            
            
            # case return value
            case "${choice[1]}" in
                0)  # OK
                    # just in case the object has a null property
                    if [ -n "${choice[0]}" ]; then
                        # populate arrays used to assemble object
                        questions[${parameterCount}]=${parameters[$i]}
                        answers[${parameterCount}]=${choice[0]}
                        
                    else
                        # this shouldn't happen unless the api is broken
                        throwError "undefined object property" 1
                        break
                        
                    fi
                    ;;
                    
                1)  # Back
                    # return to the main menu
                    mainMenu
                    break
                    ;;
                    
                255)# ESC
                    # return to the main menu
                    mainMenu
                    break
                    ;;
                    
                *)  # oops, fell through
                    # return to the main menu
                    mainMenu
                    break
                    ;;
                    
            esac
            
            let parameterCount++
            unset options choice
            
        done
        
    else
        return 1
        
    fi
    
}


# function to get parameter options
# $1 = option name
function getParameterOptions() {
    # validate argument
    if [ $# -eq 1 ]; then
        # declare variables local to this function
        local count=0 option options=( $( getInfo "options" "${1}" ) )
        
        for option in ``options.items()``; do
            if [[ `echo ${option} | grep -c ${1}` != 0 ]]; then
                options[$count]=$(echo ${1} | sed s/__tick_data_options_//g)
                echo ${!option}
                let count++
                
            fi
            
        done
        
    else
        return 1
        
    fi
    
}


# function to encode object to base64
# $1 = object
function encodeObject() {
    # validate argument
    if [ $# -eq 1 ]; then
        echo $( echo "${1}" | uuencode -m - | tail -n +2 | head -n -1 ) | tr -d ' '
        
    else
        return 1
        
    fi
    
}


# function to assemble object
function assembleObject() {
    # validate argument
    if [ $# -eq 1 ]; then
        # declare variables local to this function
        local apiObj x
        
        apiObj="
            {
            \"tool\":\""${1}"\",
            "
        
        for x in "${!answers[@]}"; do
            apiObj=${apiObj}"
                \""${questions[$x]}"\":\""${answers[$x]}"\",
            "
            
        done
        
        # append date property for expiration
        apiObj=${apiObj}"
                \"date\":\""$( date +%s )"\"
            "
        
        apiObj=${apiObj}"
            }
        "
        
        # return the encoded object
        echo "${apiObj}"
        
    else
        return 1
        
    fi
    
}


# function to post ojbect to api
# $1 = hostname
# $2 = port
# $3 = object
function postObject() {
    # validate arguments
    if [ $# -eq 3 ]; then
        # url of the api
        local url="https://"${1}":"${2}"/"
        
        # make sure ssl certificate is available
        [ ! -s ${CERTIFICATE} ] && extractCertificate
        
        # post command object back to api
        echo -e $( curl --cacert ${CERTIFICATE} --insecure --data key=${APIKEY} --data tool="${3}" ${url} 2>/dev/null )
        
    else
        return 1
        
    fi
    
}


# function for displaying main menu
# $1 = dialog
function mainMenu() {
    # declare variables local to this function
    local dialog i gauge response responseCount=0 r
    
    local dialog="
        dialog \\
            --no-shadow \\
            --backtitle \""${BRAND}" "${APPNAME}"\" \\
            --cancel-label \"Quit\" \\
            --extra-button \\
            --extra-label \"Refresh\" \\
            --menu \"Select a tool:\" 20 78 13 \\"
    
    
    for i in "${!tools[@]}"; do
        gauge=$( awk -v STEP="${i}" -v COUNT="${#tools[@]}" 'BEGIN {printf "%d\n", ((STEP / (COUNT -1)) * 100)}' )
        echo ${gauge} | dialog --backtitle "${BRAND} ${APPNAME}" --gauge "Querying api for latest available tools" 6 45 0
        dialog=${dialog}"
                \""${tools[$i]}"\" \""$(getInfo ${tools[$i]} 'description')"\" \\"
        
    done
    
    # launch menu and split output into an array
    for r in $( eval "${dialog}" 3>&2 2>&1 1>&3; echo ", "${?} ); do
        response[${responseCount}]=$( echo ${r} | sed 's/,*$//' )
        let responseCount++
        
    done
    
    # case return value
    case "${response[1]}" in
        0)  # OK
            # just in case the object returns an undefined property
            if [ -n "${response[0]}" ]; then
                # get additional parameters, assemble object, post object
                getParameters "${response[0]}" || throwError "could not get parameters for "${response[0]} 1 \
                && confirmAction "$( assembleObject "${response[0]}" )" || return 0 \
                && eventLog "$( assembleObject "${response[0]}" )" || throwError "could not log action" 1 \
                && pleaseWait || return 0 \
                && displayResult "$( postObject "${APIHOST}" "${APIPORT}" "$( encodeObject "$(assembleObject "${response[0]}" )" )" )" || throwError "could not post object to api" 1 \
                && getObject "${APIHOST}" "${APIPORT}" || throwError "could not establish connection to "${APIHOST} 1 \
                && getTools || throwError "unable to traverse api object" 1 \
                && mainMenu || throwError "could not load main menu" 1
                
            else
                # this shouldn't happen unless the api is broken
                throwError "undefined object property" 1
                
            fi
            ;;
            
        1)  # Quit
            postRun
            exit ${response[1]}
            ;;
            
        3)  # Refresh
            getObject "${APIHOST}" "${APIPORT}" || throwError "could not establish connection to "${APIHOST} 1 \
            && getTools || throwError "unable to traverse api object" 1 \
            && mainMenu || throwError "could not load main menu" 1
            ;;
            
        255)# ESC
            postRun
            exit ${response[1]}
            ;;
            
        *)  # oops, fell through
            postRun
            exit 1
            ;;
            
    esac
    
}


### Main program


# validate dependancies for portability
[ -z "${dependancies}" ] && readonly dependancies=( ${LIBRARY} 'awk' 'cat' 'clear' 'curl' 'cut' 'date' 'dialog' 'egrep' 'getopt' 'grep' 'head' 'kill' 'logger' 'logname' 'mktemp' 'printf' 'rm' 'sed' 'tail' 'tr' 'uudecode' 'uuencode' 'wc' )
for d in "${!dependancies[@]}"; do
    type ${dependancies[$d]} >/dev/null 2>&1 || throwError "'"${dependancies[$d]}"' required" 1
    
done


# parse command-line arguments
set -- `getopt -n ${SCRIPT} -u --longoptions="drivenumber:,hostnumber:,query-tools,scmnumber:,locationnumber:,switchnumber:,tool:,vmname:" "" "$@"` || throwError "Invalid argument" 1
#[ $# -eq 0 ] && exit 1
x=0
while [ $# -gt 0 ]; do
    case "${1}" in
        --drivenumber) readonly drivenumber=${2}; questions[${x}]="drivenumber"; answers[${x}]=${2}; let x++; shift 2;;
        --hostnumber) readonly hostnumber=${2}; questions[${x}]="hostnumber"; answers[${x}]=${2}; let x++; shift 2;;
        --query-tools) readonly querytools=1; shift;;
        --scmnumber) readonly scmnumber=${2}; questions[${x}]="scmnumber"; answers[${x}]=${2}; let x++; shift 2;;
        --locationnumber) readonly locationnumber=${2}; questions[${x}]="locationnumber"; answers[${x}]=${2}; let x++; shift 2;;
        --switchnumber) readonly switchnumber=${2}; questions[${x}]="switchnumber"; answers[${x}]=${2}; let x++; shift 2;;
        --tool) readonly toolarg=${2}; shift 2;;
        --vmname) readonly vmname=${2}; questions[${x}]="vmname"; answers[${x}]=${2}; let x++; shift 2;;
        --) shift; break;;
    esac
done


### Query API tools object
if [ -n "${querytools}" ]; then
    if getObject "${APIHOST}" "${APIPORT}" && getTools; then
        echo -e "\nThere are currently "${#tools[@]}" available tools\n"
        for i in "${!tools[@]}"; do
            echo ${tools[$i]}" => {"
            echo "    name => "$(getInfo ${tools[$i]} "name")
            echo "    description => "$( getInfo ${tools[$i]} "description" )
            echo "    parameters => {"
            
            for j in $(getInfo ${tools[$i]} "parameters"); do
                parameterOptions=$( getParameterOptions "${j}" )
                echo -e "        "$j"\c"
                if [[ ${parameterOptions} != "" ]]; then
                    echo " => {"
                    echo "            options => { "${parameterOptions}" }"
                    echo "        }"
                    
                else
                    echo -e ""
                    
                fi
                
            done
            
            echo "    }"
            echo -e "}\n"
            
        done
        
    fi

    postRun
    exit 0
    
fi

if [ -z "${toolarg}" ]; then
    # Load user interface
    getObject "${APIHOST}" "${APIPORT}" || throwError "could not establish connection to "${APIHOST} 1 \
    && getTools || throwError "unable to traverse api object" 1 \
    && mainMenu || throwError "could not load main menu" 1
    
else
    # Command-line arguments detected. Skipping UI
    eventLog "$( assembleObject "${toolarg}" )" || throwError "could not log action" 1 \
    && displayResult "$( postObject "${APIHOST}" "${APIPORT}" "$( encodeObject "$(assembleObject "${toolarg}" )" )" )" || throwError "could not post object to api" 1 \

fi

# Cleanup and exit
postRun
exit 0


### DO NOT EDIT BELOW THIS LINE ###

CERTIFICATE:
begin 664 -
N+2TM+2U"14=)3B!#15)4249)0T%412TM+2TM"DU)245"5$-#074R9T%W24)!
M9TE*04U61%(T2T)H5$MS34$P1T-3<4=326(S1%%%0D)!54%-24<T350X=U!1
M640*5E%11$5Z6EA95WAN8VU6;&)N36=5,FPP6E-"0F-M3F]A6%)L63-2,6-M
M56=5;3EV9$-"1%I82C!A5UIP63)&,`I:4T)"9%A2;V(S2G!D2&MX0WI!2D)G
M3E9"06=406ML34U1<W=#45E$5E%11T5W2E95>D5R34-K1T-3<4=326(S"D11
M14I!4EEC4VTY>F%(5FA,:VAL9$=X:&)M4D%D,D9S6C-*;%I7-7I,;4YV8E1%
M4TU"04=!,55%0VA-2E8R1G,*6C-*;%I7-7I-4F]W1T%91%9144Q%>$9485A2
M;$E%1GE9,FAP9$=6:F1(5GE:5$%E1G<P>$UJ03!-:E5W3D1%>0I-5&1A1G<P
M>$YZ03!-:E%W3D1%>4U49&%-24<T350X=U!1641645%$17I:6%E7>&YC;59L
M8FY-9U4R;#!:4T)""F-M3F]A6%)L63-2,6-M56=5;3EV9$-"1%I82C!A5UIP
M63)&,%I30D)D6%)O8C-*<&1(:WA#>D%*0F=.5D)!9U0*06ML34U1<W=#45E$
M5E%11T5W2E95>D5R34-K1T-3<4=326(S1%%%2D%266-3;3EZ84A6:$QK:&QD
M1WAH8FU200ID,D9S6C-*;%I7-7I,;4YV8E1%4TU"04=!,55%0VA-2E8R1G-:
M,TIL6E<U>DU2;W='05E$5E%13$5X1E1A6%)L"DE%1GE9,FAP9$=6:F1(5GE:
M5$-#05-)=T1164I+;UI):'9C3D%114)"44%$9V=%4$%$0T-!46]#9V=%0D%.
M<E<*,$MF64E2.&UZ9$-R>6EO-5)$,#0U:T%/1F1:,6QC4&UO04-R6C9B2VAU
M:&Q,0E)9<&1O5S!694$V-$%8,C9H9PIS2&]C<D)20EID;V\T5R]N,G!R<6UI
M1$U)<DY"=7='>5=)=%IR4SE8=GIZ34II3$Q2;CA&6#18-VY206U88F%O"DIC
M4S5D>4%R.&A0-TMW8G`S,%!#=71F1F-U>C-33TUC,F=R3W9H0D5.3TE(8W0K
M<C%H>7%39TY(=S1714XS:C8*."M#<3EU9F-I5W8K35E,=&U+:W5">4)G2FQN
M0C1U4W%:2&%F23A66E=Z1GA3,$-:1GA063AL>$)44G%"3VA)=`IL6%)*,D-E
M>$5#8E-&4&DU=VU253-08F%',59$1F%+-R\U=FM):VE63$0R.7@X9C5/0S9P
M>5DV:41F-V%+670X"GEK3'$K379L2F=N;$=J;5$O4F-#07=%04%A35%-031W
M1$%91%92,%1"055W07=%0B]Z04Y"9VMQ:&MI1SEW,$(*05%11D%!3T-!445!
M4EHP,E)O:'1A0S%Q.35-=2LW07)66E9'2#5'-V%M8F1Q1RM4,#,P,U9-0F$V
M45=H>&YE2@IC:&AC5'),6EE84TXX5&ME9F5V,"M1-C!K<%%'6&PV*TQ!8C(V
M2W5),VQ/57-!3D=T5$5V:WA!4T1&5#!O<E1J"EEH<F-A95)%835Y,%DS;VXQ
M42]156M">51*<%IU3V4X1VAD2%15*V9'44I443%946-F8E`V;V4Y>'AK;E=G
M4FH*95EP<'97,3@X-FQI:'-U04YL;&IN;4)1,7@K9&YF44@R8T@U;V8K2&QH
M0W$R4#5H,3-Q1VEZ4#9!9$]+6C(T;PI44'AG63=&5VA7>$]#45HV56QM,$5V
M8U9*,&0X<7-F>#(P=6Q5;W5W43-Y8V$O87E69THR:#54-EA9-6,W=$)$"DIB
M.2]'3D%S<W@Q.7-14WAZ;30R5%1';$LS>4<R24%J4V<]/0HM+2TM+45.1"!#
015)4249)0T%412TM+2TM"@``
`
end

