setopt nohup # recommended for bg'ing a proc
setopt nocheckjobs # recommended for bg'ing a proc
#setopt auto_continue # recommened for disown'ing a proc

local alwaysBackgroundPattern
alwaysBackgroundPattern=('firefox.*' 'thunderbird.*' 'urxvt.*')

function checkForXProc() {
    coproc isXWindow "$1" $(date +%s)
    disown %isXWindow
    return 0
}

preexec_functions+=(checkForXProc)

function disOwnProcess() {
    read -p disOwnProc 2>/dev/null

    if [ "${disOwnProc}" = "true" ]; then
        #disown %%
        bg %% # with bg proc stays in job table; with disown it is removed
    fi

    return 0;
}

precmd_functions+=(disOwnProcess)

# $1 = name of cmd; $2 = now in sec since epoc
function isXWindow() {
    CMD=$( echo ${1} | sed -e 's/ \{1,\}/ /g' | cut -d ' ' -f 1 )
    NOW=${2}

    for pat in $alwaysBackgroundPattern; do
        if [[ ${CMD} =~ $pat ]]; then
            sendToBackground ${CMD}
            return 0;
        fi
    done

    cmdbin=$(whence ${CMD})
    if [ -z "${cmdbin}" -o ! "${cmdbin[1]}" = "/" ]; then return 0; fi

    # from grep (1):
    # Portable shell scripts should avoid both -q and -s  and  should  redirect
    # standard  and  error output  to  /dev/null instead.
    echo $(ldd ${cmdbin} 2>/dev/null) | grep X11 2>&1 >/dev/null
    # exit 0 => match; 1 => nomatch
    if [ $? -eq 0 ]; then
        sendToBackground ${CMD}
        return 0;
    fi

    return 0;
}

function sendToBackground() {
    CMD=${1}
    # -le 2 -> wait 2 seconds
    t=0; while [ $t -le 30 ]; do
        t=$(($t+1))
        # unfortunately i suck a lot at sed & awk
        # i'm exited about the case when this breaks..
        psstring="$(ps -t $TTY -o comm,pid,lstart --sort start \
            | sed -r -e '/((-|)zsh|sed|ps|cut|grep|tail|<defunct>)/d; s/ {1,}/ /g')"

        comm=$(echo -e "${psstring}" | tail -1 | grep "${CMD}" | cut -d ' ' -f 1)
        pid=$(echo -e "${psstring}" | tail -1 | grep "${CMD}" | cut -d ' ' -f 2)
        start=$(echo -e "${psstring}" | tail -1 | grep "${CMD}" | cut -d ' ' -f 3-)

        if [[ -n "${start}" && $(date -d "${start}" +%s) -ge ${NOW} ]]; then
            # background only processes with a window
            xdotool search --onlyvisible --limit 1 --pid ${pid} --name ".*${comm}.*" 1>/dev/null 2>/dev/null
            if [[ $? -eq 0 && ${comm} =~ "${CMD}.*" ]]; then
                print true # as coproc print true to the reading (read -p) process
                kill -SIGTSTP ${pid}
                return 0;
            else
                sleep 0.1s
                continue
            fi
        else
            sleep 0.1s
            continue
        fi
    done
}
