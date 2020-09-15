#!/bin/bash
# Copyright (c) 2020 Behan Webster
# License: GPL

set -e
set -u

VERSION=1.2

CMD="$(basename "$0")"
CONFIGDIR="$HOME/.config/${CMD#.sh}"
CONF="$CONFIGDIR/settings.conf"
MYPID="$$"

BITLY_TOKEN=
COPY=
COURSE=
DATE=
DEBUG=
EMAIL=
EVAL=
FILE=
INPERSON=
KEY=
NAME=
OPENENROL=
QUIET=
REVISION=
SHOW=
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
gettitle() {
	local STR=$1

	[[ -n $TITLE ]] || TITLE="$(ready-for.sh -l 2>/dev/null \
		| grep "$STR" | sed -r "s/ *$STR - //")"
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
getkey() {
	local STR=$1 CODE

	CODE="$(sed -r 's/^.*: *//' <<<"$STR")"
	if [[ -n $CODE && $CODE =~ ^[0-9a-z]+$ ]] ; then
		KEY="$CODE"
	fi
}

################################################################################
getbitly() {
	local URL=$1
	[[ -n $BITLY_TOKEN ]] || error "No BITLY_TOKEN specified in $CONF"
	local API='https://api-ssl.bitly.com/v4/shorten'
	curl -s \
	-H "Authorization: Bearer $BITLY_TOKEN" \
	-H "Content-Type: application/json" \
	-X POST $API \
	-d "{\"long_url\":\"$URL\"}" \
	| jq .id
}

################################################################################
getevaluation() {
	local STR=$1

	EVAL="$(sed -r 's/^.*http/http/' <<<"$STR")"
	[[ $EVAL =~ https?:// ]] || error "Invalid eval URL: $EVAL"
}

################################################################################
getdata_dir() {
	local OTHER
	info "Reading info from directory name"
	# shellcheck disable=SC2034
	IFS=- read -r DATE COURSE OTHER <<<"$(basename "$(pwd)")"
	gettitle "$COURSE"
}

################################################################################
getdata_csv() {
	local FILE="${1:-../Class Roster.csv}"
	[[ $FILE =~ csv$ && -f $FILE ]] || return 0
	info "Reading info from $FILE"

	[[ -n $DATE ]] || error "No date found"
	local MDY Y M D
	IFS=. read -r Y M D <<<"$DATE"
	MDY="${M#0}[/]${D#0}[/]$Y"

	[[ -n $REVISION ]] || REVISION="$(awk -F\" "/$MDY/ {print \$22}" <"$FILE")"
	[[ -n $KEY ]] || KEY="$(awk -F\" "/$MDY/ {print \$24}" <"$FILE")"
	[[ -n $EVAL ]] || EVAL="$(awk -F\" "/$MDY/ {print \$26}" <"$FILE")"
}

################################################################################
getdata_pdf() {
	local FILE=$1 LINE
	local FILE="${1:-Code.pdf}" LINE
	[[ $FILE =~ pdf$ && -f $FILE ]] || return 0
	info "Reading info from $FILE"

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
	local BITLY

	[[ -n $COURSE ]] || error "No course found"
	[[ -n $TITLE ]] || error "No title found"
	[[ -n $REVISION ]] || error "No version found"
	[[ -n $KEY ]] || error "No registration key found"
	[[ -n $EVAL ]] || error "No evaulation url found"

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

	if [[ -z $BITLY_TOKEN ]] ; then
		warn "No BITLY_TOKEN specified in $CONF"
		warn "Disabling bit.ly links for evals"
		echo '\BITLYfalse'
	else
		BITLY="$(getbitly "$EVAL" | sed -r 's/\"//g' )"
		#shellcheck disable=SC2028
		echo "\\renewcommand{\\myeval}{$BITLY}"
	fi

	if [[ -n $OPENENROL ]] ; then
		info "Building Open Enrolment $COURSE"
		#shellcheck disable=SC2028
		echo '\CORPfalse'
	else
		info "Building Coporporate $COURSE (Add --oe to change)"
	fi

	if [[ -n $INPERSON ]] ; then
		info "Building In-person $COURSE"
		#shellcheck disable=SC2028
		echo '\VIRTUALfalse'
	else
		info "Building Virtual $COURSE (add --inperson to change)"
	fi
}

################################################################################
usage() {
	if [[ $# -gt 0 ]] ; then
		echo -e "${RED}E: Invalid argument:" "$@" "$BACK"
	fi
	cat <<-HELP
	Version v$VERSION
	Usage: $CMD [options] [course] [YYYY.MM.DD]
	    --course <course>
	    --date <date>
	    --evaluation <evaluation url>
	    --file <file>
	    --inperson
	    --key <key>
	    --mail <email>
	    --name <name>
	    --name <name>
	    --oe-course
	    --revision <revision>
	    --time <start-end times>
	    --timezone <TZ>
	    --title "<title>"
	    --debug
	    --help
	    --quiet
	    --show
	    --trace
	    --verbose
	HELP
	exit 1
}

################################################################################
if [[ -e $CONF ]] ; then
	# shellcheck disable=SC1090
	source "$CONF"
fi
TEXFILE="${TEXTFILE:-$TEMPLATE/course.tex}"
PDFFILE="${PDFTFILE:-$TEMPLATE/course-intro.pdf}"
SETTINGS="${SETTINGS:-CONFIGDIR/settings.tex}"
if [[ ! -e "$TEMPLATE/${SETTINGS##*/}" ]] ; then
	warn "Creating $TEMPLATE/${SETTINGS##*/}"
	ln -s $SETTINGS $TEMPLATE
fi
getdata_dir

################################################################################
while [[ $# -gt 0 ]] ; do
	case "$1" in
		--debug) DEBUG=y;;
		-c|--cou*) shift; COURSE="$1";;
		--copy) COPY=y;;
		-d|--date*) shift; DATE="$1";;
		-e|--eval*) shift; EVAL="$1";;
		-f|--file*) shift; FILE="$1";;
		-i|--in*) INPERSON=y;;
		-k|--key*) shift; KEY="$1";;
		-m|--mail) shift; EMAIL="$1";;
		-n|--name) shift; NAME="$1";;
		-o|--oe*) OPENENROL=y;;
		--quiet) QUIET=y;;
		-r|--rev*) shift; getrevision "$1";;
		-s|--start*|--time) shift; TIME="$1";;
		--show) SHOW=y;;
		--trace) set -x ;;
		-t|--tit*) shift; TITLE="$1";;
		-tz|--timezone|--zone) shift; ZONE="$1";;
		-v|--verbose) VERBOSE="-v";;
		-V|--Version) echo "$CMD v$VERSION"; exit 0;;
		-h|--help) usage ;;
		*) usage "$1" ;;
	esac
	shift
done

################################################################################
debug "Date for $COURSE is $DATE"
getdata_pdf "$FILE"
getdata_csv "$FILE"
LOCALCONF="intro.conf"
if [[ -e $LOCALCONF ]] ; then
	# shellcheck disable=SC1090
	source "$LOCALCONF"
fi

################################################################################
if [[ -n $DEBUG ]] ; then
	printdata
else
	rm -f "$TEXFILE"
	printdata > "$TEXFILE"

	if [[ -n $VERBOSE ]] ; then
		make -C "$TEMPLATE" clean all
	else
		make -C "$TEMPLATE" clean all >/dev/null
	fi
	cp $VERBOSE "$PDFFILE" .
	[[ -z $COPY && -n $DESKTOPDIR ]] || cp $VERBOSE "$PDFFILE" "$DESKTOPDIR"
	info "Created ${PDFFILE##*/}"
	[[ -z $SHOW ]] || (nohup evince "${PDFFILE##*/}" >/dev/null 2>&1 &)
fi
