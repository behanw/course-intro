#!/bin/bash
# Copyright (c) 2020 Behan Webster <behanw@converseincode.com>
# License: GPL
#
# The following packages need installing:
#      bash, curl, ghostscript, jq, make, miller, pdfgrep, sed, texlive
# The following packages are recommended:
#      aspell, evince

set -e
set -u

VERSION=1.5

#===============================================================================
CMD="$(basename "$0")"
CONFIGDIR="$HOME/.config/${CMD%.sh}"
CONF="$CONFIGDIR/settings.conf"
MYPID="$$"

#===============================================================================
BITLY_TOKEN=
COPY=
COMPANY=
COURSE=
CURL="curl -s"
DATE=
DEBUG=
DESKTOPDIR="$HOME/Desktop"
EMAIL=
EVAL=
FILE=
INPERSON=
JSON="https://training.linuxfoundation.org/cm/prep/data/ready-for.json"
KEY=
LOCATION=
NAME=
OPENENROL=
QUIET=
REVISION=
ROSTER=
SHOW=
TEMPLATE=
TEST=
TIME=
TITLE=
VERBOSE=
ZONE=

#===============================================================================
RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
#BLUE="\e[0;34m"
BACK="\e[0m"

################################################################################
metadata() {
	info "Name:      '$NAME'"
	info "Email:     '$EMAIL'"
	info "OpenEnrol: '${OPENENROL:-n}'"
	info "InPerson:  '${INPERSON:-n}'"
	info "Course:    '$COURSE'"
	info "Title:     '$TITLE'"
	info "Revision:  '$REVISION'"
	info "Time:      '$TIME'"
	info "TimeZone:  '$ZONE'"
	info "Key:       '$KEY'"
	info "Eval:      '$EVAL'"
}

################################################################################
debug() {
	[[ -z $DEBUG ]] || echo -e "${CYAN}D:" "$@" "$BACK" >&2
}

################################################################################
info() {
	[[ -n $QUIET ]] || echo -e "${GREEN}I:" "$@" "$BACK" >&2
}

################################################################################
warn() {
	echo -e "${YELLOW}W:" "$@" "$BACK" >&2
}

################################################################################
error() {
	echo -e "${RED}E:" "$@" "$BACK" >&2
	kill -9 "$MYPID"
	exit 1
}

################################################################################
getjson() {
	$CURL "$JSON" | jq --raw-output "$@"
}

################################################################################
gettitle() {
	local STR=$1

	if [[ -z $TITLE ]] ; then
		TITLE="$(ready-for.sh -l 2>/dev/null \
			| grep "$STR" | sed -r -e "s/ *$STR - //")"
	fi
	if [[ -z $TITLE ]] ; then
		TITLE="$(getjson ".activities | .$COURSE | .title")"
	fi
}

################################################################################
getcourse() {
	local STR=$1

	[[ -n $COURSE ]] || COURSE="$(sed -r 's/^.*(LF[A-Z][0-9]+).*$/\1/' <<<"$STR")"
	gettitle "$COURSE"
}

################################################################################
getrevision() {
	local STR=$1 REV

	REV="$(sed -r 's/^.*(v[0-9.]+).*$/\1/' <<<"$STR")"
	if [[ -n $REV ]] ; then
		REVISION=$REV
	fi
	REVISION="$(sed -e 's/^v//I' -e 's/^/V/' <<<"$REVISION")"
}

################################################################################
getcm() {
	getjson ".activities | .$COURSE | .materials | .[]"
}

################################################################################
getkey() {
	local STR=$1 CODE

	CODE="$(sed -r 's/^.*: *//' <<<"$STR")"
	debug "getkey: $STR -> $CODE"
	if [[ -n $CODE && $CODE =~ ^[0-9A-Za-z]+$ ]] ; then
		KEY="$CODE"
	fi
}

################################################################################
getbitly() {
	local URL=$1 API AUTH TYPE DATA
	[[ -n $BITLY_TOKEN ]] || error "No BITLY_TOKEN specified in $CONF"
	[[ -n $URL ]] || error "No evaluation URL specified for $COURSE"
	API='https://api-ssl.bitly.com/v4/shorten'
	AUTH="Authorization: Bearer $BITLY_TOKEN"
	TYPE="Content-Type: application/json"
	DATA="{\"long_url\":\"$URL\"}"
	if [[ -n $TEST ]] ; then
		echo "$CURL -H \"$AUTH\" -H \"$TYPE\" -X POST \"$API\" -d \"$DATA\"" >&2
	else
		$CURL -H "$AUTH" -H "$TYPE" -X POST "$API" -d "$DATA" | jq .id
	fi
}

################################################################################
getevaluation() {
	local STR=$1

	EVAL="$(sed -r 's/^.*http/http/' <<<"$STR")"
	[[ $EVAL =~ https?:// ]] || error "Invalid eval URL: $EVAL"
}

################################################################################
getdata_dir() {
	local NAME CORP LOC OTHER
	NAME="$(basename "$(pwd)")"
	# shellcheck disable=SC2034
	local NDATE NCOURSE CORP LOC OTHER <<<"$NAME"
	IFS=- read -r NDATE NCOURSE CORP LOC OTHER <<<"$NAME"

	debug "getdata: DATE:$DATE COURSE:$COURSE KEY:$KEY EVAL:$EVAL OTHER:$OTHER"

	#-----------------------------------------------------------------------
	if [[ -z $DATE && $NDATE =~ ^[0-9]{2} ]] ; then
		info "Reading info from '$NAME'"
		DATE="$NDATE"
		warn "  Detecting date as $DATE"
	fi

	#-----------------------------------------------------------------------
	if [[ -z $COURSE && -n $NCOURSE ]] ; then
		COURSE="$NCOURSE"
	fi
	[[ -n $COURSE ]] || return 0
	gettitle "$COURSE"

	#-----------------------------------------------------------------------
	if [[ -z $OPENENROL && -n $CORP ]] ; then
		COMPANY="$CORP"
		if [[ $CORP == "OE" ]] ; then
			OPENENROL=y
			warn "  Detecting Open Enrolment class"
		else
			OPENENROL=n
			warn "  Detecting Corporate class for $CORP"
		fi
	fi

	#-----------------------------------------------------------------------
	if [[ -z $INPERSON && -n $LOC ]] ; then
		LOCATION="$LOC"
		if [[ $LOC = "Virtual" ]] ; then
			INPERSON=n
			warn "  Detecting Virtual class"
		else
			INPERSON=y
			warn "  Detecting In-person class in $LOC"
		fi
	fi
}

################################################################################
save_json() {
	local DIR=$1 CSV=$2 MDY=$3 CORP
	local META="$DIR/meta.json"
	local NEW="$DIR/meta-new.json"
	local TMP="$DIR/meta-new.json.tmp"

	mlr --c2j --jlistwrap cat <<<"$(tr -d '"' <"$CSV")" \
		| jq ".[] | select(.\"Session Start Date\" | contains(\"$MDY\"))" \
		>"$NEW"
	if [[ ! -s $NEW ]] ; then
		rm -f "$NEW"
	elif [[ -e $META ]] ; then
		CORP="$(jq '.Company' "$META")"
		if [[ $CORP != null ]] ; then
			COMPANY="$CORP"
			jq ".Company=$CORP" "$NEW" > "$TMP"
			if [[ -s $TMP ]] ; then
				mv "$TMP" "$NEW"
			else
				warn "$TMP is empty"
				rm -f "$TMP"
			fi
		fi
		if cmp --quiet "$META" "$NEW" ; then
			rm -f "$NEW"
		else
			diff -u "$META" "$NEW"
		fi
	else
		mv "$NEW" "$META"
	fi
}

################################################################################
ymd_to_mdy() {
	local DATE=$1 Y M D MDY
	[[ -n $DATE ]] || error "No date found"
	if [[ $DATE =~ \. ]] ; then
		IFS=. read -r Y M D <<<"$DATE"
	elif [[ $DATE =~ - ]] ; then
		IFS=- read -r Y M D <<<"$DATE"
	elif [[ $DATE =~ / ]] ; then
		IFS=- read -r M D Y <<<"$DATE"
	elif [[ $DATE =~ 20[0-9]{6} ]] ; then
		IFS=- read -r Y M D <<<"$(sed -re 's/([0-9]{4})([0-9]{2})([0-9]{2})/\1-\2-\3/' <<<"$DATE")"
	fi
	[[ -n $D ]] || error "Date format not recognized: $DATE"
	MDY="${M#0}/${D#0}/$Y"
	debug "ymd_to_mdy: DATE:$DATE Y:$Y M:$M D:$D MDY:$MDY"
	echo "$MDY"
}

################################################################################
getdata_csv() {
	local FILE="${1:-$ROSTER}" MDY
	[[ $FILE =~ csv$ && -f $FILE ]] || return 0
	warn "Reading info from '$FILE'"

	MDY="$(ymd_to_mdy "$DATE")"

	save_json "$(pwd)" "$FILE" "$MDY"

	local D R K E
	IFS=, read -r D R K E <<<"$(mlr --csv cut -f \
		'"Session Start Date","Session Course Material Version","Session Class Key","Survey URL"' \
		<<<"$(tr -d '"' <"$FILE")" | grep "^$MDY")"

	[[ -n $REVISION ]] || getrevision "$R"
	[[ -n $KEY ]] || getkey "$K"
	[[ -n $EVAL ]] || getevaluation "$E"
}

DATECMD="$(command -v gdate)" || DATECMD="$(command -v date)" || error "No date found"

################################################################################
read_json() {
	local JSON=$1 NAME=$2 META=${3:-} DATA

	DATA="$(jq --raw-output ".\"$NAME\"" "$JSON")"

	case "$META" in
		Date) [[ ! $DATA =~ / ]] || DATA="$($DATECMD -d "$DATA" "+%Y.%m.%d")";;
	esac

	echo "$DATA"
}

################################################################################
getdata_json() {
	local JSON="meta.json" CORP LOC

	[[ -f "$JSON" ]] || return 0
	warn "Reading info from '$JSON'"

	[[ -n $DATE ]] || DATE="$(read_json "$JSON" "Session Start Date" "Date")"
	[[ -n $COURSE ]] || getcourse "$(read_json "$JSON" "Session Course Code")"
	[[ -n $REVISION ]] || getrevision "$(read_json "$JSON" "Session Course Material Version")"
	[[ -n $KEY ]] || getkey "$(read_json "$JSON" "Session Class Key")"
	[[ -n $EVAL ]] || getevaluation "$(read_json "$JSON" "Survey URL")"

	CORP="$(read_json "$JSON" "Company")"
	if [[ $CORP != null ]] ; then
		COMPANY="$CORP"
		if [[ $CORP == "OE" ]] ; then
			OPENENROL=y
		else
			OPENENROL=n
		fi
	fi

	LOC="$(read_json "$JSON" "Session Location")"
	if [[ $LOC != null ]] ; then
		LOCATION="$LOC"
		if [[ $LOC = "Virtual" ]] ; then
			INPERSON=n
		else
			INPERSON=y
		fi
	fi
}

################################################################################
getdata_pdf() {
	local FILE=$1 LINE
	local FILE="${1:-Code.pdf}" LINE
	[[ $FILE =~ pdf$ && -f $FILE ]] || return 0
	warn "Reading info from '$FILE'"

	while read -r LINE ; do
		case "$LINE" in
			*Subject:*LF*) getcourse "$LINE";;
			*Book:*v[0-9]*) getrevision "$LINE";;
			*Version:*v[0-9]*) getrevision "$LINE";;
			*Reg*:*) getkey "$LINE";;
			*Survey*:*) getevaluation "$LINE";;
			*Evaluation:*) getevaluation "$LINE";;
		esac
	done <<<"$(pdfgrep . "$FILE")"
}

################################################################################
printdata() {
	local BITLY FILE

	[[ -n $COURSE ]] || error "No course found"
	[[ -n $TITLE ]] || error "No title found"
	[[ -n $REVISION ]] || error "No version found"
	[[ -n $KEY ]] || error "No registration key found"
	[[ -n $EVAL ]] || error "No evaluation url found"

	#shellcheck disable=SC2028
	[[ -z $TIME ]] || echo "\\renewcommand{\\myclasstime}{$TIME}"
	#shellcheck disable=SC2028
	[[ -z $ZONE ]] || echo "\\renewcommand{\\myclasstz}{$ZONE}"
	#shellcheck disable=SC2028
	[[ -z $NAME ]] || echo "\\renewcommand{\\myname}{$NAME}"
	#shellcheck disable=SC2028
	[[ -z $EMAIL ]] || echo "\\renewcommand{\\myemail}{$EMAIL}"

	#shellcheck disable=SC2028
	echo "\\renewcommand{\\mycourse}{$COURSE}"
	#shellcheck disable=SC2028
	echo "\\renewcommand{\\mytitle}{$TITLE}"
	#shellcheck disable=SC2028
	echo "\\renewcommand{\\myversion}{$REVISION}"
	#shellcheck disable=SC2028
	echo "\\renewcommand{\\mykey}{$KEY}"
	#shellcheck disable=SC2028
	echo "\\renewcommand{\\myevaluation}{$EVAL}"

	#-----------------------------------------------------------------------
	if [[ -z $BITLY_TOKEN ]] ; then
		warn "No BITLY_TOKEN specified in $CONF"
		warn "Disabling bit.ly links for evals"
		echo '\BITLYfalse{}'
	else
		BITLY="$(getbitly "$EVAL" | sed -r 's/\"//g' )"
		if [[ -n $BITLY && $BITLY != null ]] ; then
			#shellcheck disable=SC2028
			echo "\\renewcommand{\\myeval}{$BITLY}"
		else
			warn "No bit.ly link generated. Disabling short links for eval"
			echo '\BITLYfalse{}'
		fi
	fi

	#-----------------------------------------------------------------------
	if [[ $OPENENROL == y ]] ; then
		info "Building Open Enrolment $COURSE"
		#shellcheck disable=SC2028
		echo '\CORPfalse{}'
	else
		warn "Building Corporate $COURSE (Add --oe to change)"
	fi

	#-----------------------------------------------------------------------
	if [[ $INPERSON == y ]] ; then
		info "Building In-person $COURSE"
		#shellcheck disable=SC2028
		echo '\VIRTUALfalse{}'
	else
		warn "Building Virtual $COURSE (add --inperson to change)"
	fi

	#-----------------------------------------------------------------------
	for FILE in $(getcm) ; do
		#shellcheck disable=SC2028
		FILE="$(sed -r -e "s/V[0-9.]+/$REVISION/;" -e 's/_/\\_/g' <<<"$FILE")"
		#shellcheck disable=SC2028
		case "$FILE" in
			*SOLUTIONS*) echo "\\renewcommand{\\solutions}{\\item $FILE}";;
			*RESOURCES*) echo "\\renewcommand{\\resources}{\\item $FILE}";;
		esac
	done
}

################################################################################
usage() {
	if [[ $# -gt 0 ]] ; then
		echo -e "${RED}E: Invalid argument:" "$@" "$BACK"
	fi
	cat <<-HELP
	Version v$VERSION
	Usage: $CMD [options]
	    -c --course <course>
	    -d --date <YYYY.MM.DD>
	    -e --evaluation <evaluation url>
	    -f --file <file>
	    -i --inperson
	    -k --key <key>
	    -m --mail <email>
	    -n --name <name>
	    -o --oe-course
	    -r --revision <revision>
	    -s --time <start-end times>
	    -t --title "<title>"
	    -z --timezone <TZ>
	    -C --copy
	    -D --debug
	    -h --help
	    -q --quiet
	    -S --show
	    -T --test
	    -R --trace
	    -v --verbose
	    -V --version
	HELP
	exit 1
}

################################################################################
parse_args() {
	while [[ $# -gt 0 ]] ; do
		case "$1" in
			-c|--cou*) shift; COURSE="$1";;
			-C|--copy) COPY=y;;
			-d|--date*) shift; DATE="$1";;
			-D|--debug) DEBUG=y;;
			-e|--eval*) shift; EVAL="$1";;
			-f|--file*) shift; FILE="$1";;
			-i|--in*) INPERSON=y;;
			-k|--key*) shift; KEY="$1";;
			-m|--mail) shift; EMAIL="$1";;
			-n|--name) shift; NAME="$1";;
			-o|--oe*) OPENENROL=y;;
			-q|--quiet) QUIET=y;;
			-r|--rev*) shift; getrevision "$1";;
			-s|--start*|--time) shift; TIME="$1";;
			-S|--show) SHOW=y;;
			-t|--tit*) shift; TITLE="$1";;
			-R|--trace) set -x ;;
			-T|--test) TEST="echo";;
			-z|--tz|--timezone|--zone) shift; ZONE="$1";;
			-v|--verbose) VERBOSE="-v";;
			-V|--version) echo "$CMD v$VERSION"; exit 0;;
			-h|--help) usage ;;
			*) usage "$1" ;;
		esac
		shift
	done
}

################################################################################
if [[ -e $CONF ]] ; then
	# shellcheck disable=SC1090
	source "$CONF"
fi
[[ -n $TEMPLATE ]] || error "No TEMPLATE specified in $CONF"
TEXFILE="${TEXFILE:-$TEMPLATE/course.tex}"
PDFFILE="${PDFFILE:-$TEMPLATE/course-intro.pdf}"
SETTINGS="${SETTINGS:-settings.tex}"
if [[ ! -e "$TEMPLATE/$SETTINGS" ]] ; then
	warn "Creating $TEMPLATE/$SETTINGS"
	rm -f "$TEMPLATE/$SETTINGS"
	ln -s "$CONFIGDIR/$SETTINGS" "$TEMPLATE/settings.tex"
fi

################################################################################
parse_args "$@"
getdata_json
getdata_dir
getdata_pdf "$FILE"
getdata_csv "$FILE"
LOCALCONF="intro.conf"
if [[ -e $LOCALCONF ]] ; then
	warn "Reading info from '$LOCALCONF'"
	# shellcheck disable=SC1090
	source "$LOCALCONF"
fi
[[ -n $QUIET ]] || metadata

################################################################################
if [[ -n $DEBUG ]] ; then
	printdata
else
	rm -f "$TEXFILE"
	printdata > "$TEXFILE"

	if [[ -n $VERBOSE ]] ; then
		make -C "$TEMPLATE" clean all
	else
		make -s -C "$TEMPLATE" clean spell
		make -s -C "$TEMPLATE" >/dev/null
	fi
	cp $VERBOSE "$PDFFILE" .
	[[ -z $COPY && -n $DESKTOPDIR ]] || cp -v "$PDFFILE" \
		"$DESKTOPDIR/course-intro-$DATE-$COURSE-$REVISION-$COMPANY-$LOCATION.pdf"
	info "Created ${PDFFILE##*/}"
	[[ -z $SHOW ]] || (nohup evince "${PDFFILE##*/}" >/dev/null 2>&1 &)
fi
