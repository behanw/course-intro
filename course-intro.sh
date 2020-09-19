#!/bin/bash
# Copyright (c) 2020 Behan Webster
# License: GPL
#
# The following packages need installing:
#      bash, curl, gawk, jq, make, sed, texlive
# The following packages are recommended:
#      aspell, evince

set -e
set -u

VERSION=1.4

#===============================================================================
CMD="$(basename "$0")"
CONFIGDIR="$HOME/.config/${CMD%.sh}"
CONF="$CONFIGDIR/settings.conf"
MYPID="$$"

#===============================================================================
BITLY_TOKEN=
COPY=
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
	metadata
	kill -9 "$MYPID"
	exit 1
}

################################################################################
getjson() {
	$CURL "$JSON" | jq "$@" | tr -d '"'
}

################################################################################
gettitle() {
	local STR=$1

	if [[ -z $TITLE ]] ; then
		TITLE="$(ready-for.sh -l 2>/dev/null \
			| grep "$STR" | sed -r "s/ *$STR - //")"
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
	if [[ -n $CODE && $CODE =~ ^[0-9a-z]+$ ]] ; then
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
		echo $CURL -H "$AUTH" -H "TYPE" -X POST "$API" -d "$DATA"
	else
		$CURL -H "$AUTH" -H "TYPE" -X POST "$API" -d "$DATA" | jq .id
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
	local NAME COMPANY LOCATION OTHER
	NAME="$(basename "$(pwd)")"
	# shellcheck disable=SC2034
	IFS=- read -r DATE COURSE COMPANY LOCATION OTHER <<<"$NAME"

	#-----------------------------------------------------------------------
	if [[ $DATE =~ ^[0-9]{2} ]] ; then
		info "Reading info from '$NAME'"
		warn "  Detecting date as $DATE"
	else
		DATE=
	fi

	if [[ -z $COURSE ]] ; then
		return 0
	fi
	gettitle "$COURSE"

	#-----------------------------------------------------------------------
	if [[ -n $COMPANY ]] ; then
		if [[ $COMPANY == "OE" ]] ; then
			OPENENROL=y
			warn "  Detecting Open Enrolment class"
		else
			warn "  Detecting Corporate class for $COMPANY"
		fi
	fi

	#-----------------------------------------------------------------------
	if [[ -n $LOCATION ]] ; then
		if [[ $LOCATION = "Virtual" ]] ; then
			warn "  Detecting Virtual class"
		else
			INPERSON=y
			warn "  Detecting In-person class in $LOCATION"
		fi
	fi
}

################################################################################
getdata_csv() {
	local FILE="${1:-$ROSTER}"
	[[ $FILE =~ csv$ && -f $FILE ]] || return 0

	[[ -n $DATE ]] || error "No date found"
	local MDY Y M D
	info "DATE:$DATE"
	IFS=. read -r Y M D <<<"$DATE"
	MDY="${M#0}[/]${D#0}[/]$Y"
	warn "Reading info from '$FILE'"
	info "DATE:$DATE MDY:$MDY $Y $M $D"

	[[ -n $REVISION ]] || REVISION="$(gawk -F\" "/$MDY/ {print \$22}" <"$FILE")"
	[[ -n $KEY ]] || KEY="$(gawk -F\" "/$MDY/ {print \$24}" <"$FILE")"
	[[ -n $EVAL ]] || EVAL="$(gawk -F\" "/$MDY/ {print \$26}" <"$FILE")"
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
	if [[ -n $OPENENROL ]] ; then
		info "Building Open Enrolment $COURSE"
		#shellcheck disable=SC2028
		echo '\CORPfalse{}'
	else
		warn "Building Corporate $COURSE (Add --oe to change)"
	fi

	#-----------------------------------------------------------------------
	if [[ -n $INPERSON ]] ; then
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
getdata_dir
parse_args "$@"
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
	[[ -z $COPY && -n $DESKTOPDIR ]] || cp $VERBOSE "$PDFFILE" "$DESKTOPDIR"
	info "Created ${PDFFILE##*/}"
	[[ -z $SHOW ]] || (nohup evince "${PDFFILE##*/}" >/dev/null 2>&1 &)
fi
