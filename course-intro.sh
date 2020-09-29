#!/bin/bash
# Copyright (c) 2020 Behan Webster <behanw@converseincode.com>
# License: GPL
#
# The following packages need installing:
#      bash, curl, ghostscript, jq, make, miller, pdfgrep, sed, texlive
# With homebrew on MacOS you will also need to install:
#      gdate
# The following packages are recommended:
#      aspell, evince

set -e
set -u

VERSION=1.6

#===============================================================================
CMD="$(basename "$0")"
CACHEDIR="$HOME/.cache/${CMD%.sh}"
CONFIGDIR="$HOME/.config/${CMD%.sh}"
CONF="$CONFIGDIR/settings.conf"
CONFTEX="settings.tex"
MYPID="$$"

#===============================================================================
BITLY_LINK=
BITLY_TOKEN=
CODEPDF="Code.pdf"
COPY=
COMPANY="OE"
COURSE=
CURL="curl -s"
DATE=
DEBUG=
DESKTOPDIR="$HOME/Desktop"
EMAIL=
EVAL=
FILE=
INPERSON=n
INSTRUCTOR=
KEY=
LOCALCONF="intro.conf"
LOCATION="Virtual"
METAFILE="meta.json"
NOCACHE=
NOUPDATE=
OPENENROL=n
PDFNAME="course-intro"
PDFVIEWER="evince"
QUIET=
READYFOR="ready-for.sh"
READYJSON="https://training.linuxfoundation.org/cm/prep/data/ready-for.json"
REVISION=
ROSTER="../Class Roster.csv"
SHOW=
TEMPLATE=
TEST=
TIME=
TITLE=
UPDATE=
VERBOSE=
ZONE=

#JSON_GTR="Session GTR"
#JSON_INSTR="Session Instructor"
#JSON_PASSWORD="Session Zoom Password"
#JSON_SKU="Session SKU"
#JSON_STUDENTS="# of Learners"
#JSON_USERNAME="Session Zoom Username"
#JSON_ZOOM="Session Zoom Link"
JSON_BITLY="Survey Short URL"
JSON_CODE="Session Course Code"
JSON_COMPANY="Company"
JSON_DATE="Session Start Date"
JSON_FILES="Course Materials"
JSON_KEY="Session Class Key"
JSON_LOC="Session Location"
JSON_SURVEY="Survey URL"
JSON_TIME="Course Time"
JSON_TITLE="Course Title"
JSON_VERSION="Session Course Material Version"
JSON_ZONE="Course Timezone"

#===============================================================================
RED="\e[0;31m"
GREEN="\e[0;32m"
YELLOW="\e[0;33m"
CYAN="\e[0;36m"
#BLUE="\e[0;34m"
BACK="\e[0m"

################################################################################
metadata() {
	info "Metadata for this course:"
	info "  Instructor:'$INSTRUCTOR'"
	info "  Email:     '$EMAIL'"
	info "  Date:      '$DATE'"
	info "  OpenEnrol: '$OPENENROL'"
	info "  Company:   '$COMPANY'"
	info "  InPerson:  '$INPERSON'"
	info "  Location:  '$LOCATION'"
	info "  Course:    '$COURSE'"
	info "  Title:     '$TITLE'"
	info "  Revision:  '$REVISION'"
	info "  Time:      '$TIME'"
	info "  TimeZone:  '$ZONE'"
	info "  Key:       '$KEY'"
	info "  Eval:      '$EVAL'"
	info "  Bitly Link:'$BITLY_LINK'"

	add_json "$METAFILE" "$JSON_DATE" "$DATE"
	add_json "$METAFILE" "$JSON_COMPANY" "$COMPANY"
	add_json "$METAFILE" "$JSON_LOC" "$LOCATION"
	add_json "$METAFILE" "$JSON_CODE" "$COURSE"
	add_json "$METAFILE" "$JSON_TITLE" "$TITLE"
	add_json "$METAFILE" "$JSON_VERSION" "$REVISION"
	add_json "$METAFILE" "$JSON_TIME" "$TIME"
	add_json "$METAFILE" "$JSON_ZONE" "$ZONE"
	add_json "$METAFILE" "$JSON_KEY" "$KEY"
	add_json "$METAFILE" "$JSON_SURVEY" "$EVAL"
	add_json "$METAFILE" "$JSON_BITLY" "$BITLY_LINK"
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
	[[ -n $QUIET ]] || echo -e "${YELLOW}W:" "$@" "$BACK" >&2
}

################################################################################
error() {
	echo -e "${RED}E:" "$@" "$BACK" >&2
	kill -9 "$MYPID"
	exit 1
}

################################################################################
DATECMD="$(command -v gdate)" || DATECMD="$(command -v date)" || error "No date found. Try installing gdate."
read_json() {
	local JSON=$1 NAME=$2 META=${3:-} DATA

	[[ -n $JSON && -e $JSON ]] || error "Read JSON: $JSON not found"

	DATA="$(jq --raw-output ".\"$NAME\"" "$JSON" | sed -e 's/\\n/\n/g')"

	case "$META" in
		Date) [[ ! $DATA =~ / ]] || DATA="$($DATECMD -d "$DATA" "+%Y.%m.%d")";;
	esac

	[[ $DATA == null ]] || echo "$DATA"
}

################################################################################
add_json() {
	local JSON=$1 NAME=$2 DATA=$3
	local NEW="${JSON/.json/-tmp.json}"

	if [[ ! -s "$JSON" ]] ; then
		echo '{}' >"$JSON"
	fi
	if [[ $DATA != null ]] ; then
		jq ".\"$NAME\"=\"$DATA\"" "$JSON" > "$NEW"
		if [[ -s $NEW ]] ; then
			mv "$NEW" "$JSON"
		else
			warn "$NEW is empty"
			rm -f "$NEW"
		fi
	fi
}

################################################################################
save_json() {
	local DIR=$1 CSV=$2 MDY=$3 NAME DATA
	local META="$DIR/$METAFILE"
	local NEW="$DIR/${METAFILE/.json/-new.json}"

	mlr --c2j --jlistwrap cat <<<"$(tr -d '"' <"$CSV")" \
		| jq ".[] | select(.\"$JSON_DATE\" | contains(\"$MDY\"))" \
		>"$NEW"
	if [[ ! -s $NEW ]] ; then
		rm -f "$NEW"
	elif [[ -e $META ]] ; then
		for NAME in "$JSON_COMPANY" "$JSON_LOC" ; do
			DATA="$(read_json "$META" "$NAME")"
			add_json "$NEW" "$NAME" "$DATA"
		done
		if cmp --quiet "$META" "$NEW" ; then
			rm -f "$NEW"
		else
			mv "$NEW" "$META"
		fi
	else
		mv "$NEW" "$META"
	fi
}

################################################################################
query_json() {
	local JSON="$CACHEDIR/${READYJSON##*/}" DATA
	mkdir -p "$CACHEDIR"
	if [[ -n $NOCACHE || ! -f $JSON ]] ; then
		$CURL "$READYJSON" >"$JSON"
	fi
	DATA="$(jq --raw-output "$@" "$JSON")"
	[[ $DATA == null ]] || echo "$DATA"
}

################################################################################
getbitly() {
	local URL=$1 API AUTH TYPE JSON
	API='https://api-ssl.bitly.com/v4/shorten'
	AUTH="Authorization: Bearer $BITLY_TOKEN"
	TYPE="Content-Type: application/json"
	JSON="{\"long_url\":\"$URL\"}"

	if [[ -z $BITLY_TOKEN ]] ; then
		warn "No BITLY_TOKEN specified in $CONF"
		warn "Disabling bit.ly links for evals"
		return 0
	elif [[ -z $URL ]] ; then
		error "No evaluation URL specified for $COURSE (Use --evaluation to fix)"
	elif [[ -n $TEST ]] ; then
		echo "$CURL -H \"$AUTH\" -H \"$TYPE\" -X POST \"$API\" -d \"$JSON\"" >&2
	else
		local DATA
		DATA="$($CURL -H "$AUTH" -H "$TYPE" -X POST "$API" -d "$JSON" | jq --raw-output .id)"
		[[ $DATA == null ]] || echo "$DATA"
	fi
}

################################################################################
getcm() {
	local FILES
	FILES="$(read_json "$METAFILE" "$JSON_FILES")"
	[[ -n $FILES ]] || FILES="$(query_json ".activities | .$COURSE | .materials | .[]")"
	[[ -z $FILES ]] || add_json "$METAFILE" "$JSON_FILES" "$FILES"
	echo "$FILES"
}

################################################################################
getcourse() {
	local STR=$1 NAME

	NAME="$(sed -r 's/^.*(LF[A-Z][0-9]+).*$/\1/' <<<"$STR")"
	if [[ -z $COURSE && -n $NAME ]] ; then
		COURSE="$NAME"
		gettitle "$COURSE"
	fi
}

################################################################################
getdate() {
	local STR=$1

	if [[ $STR =~ ^[0-9.]{8,10} && -z $DATE ]] ; then
		DATE="$STR"
		debug "  Detecting date as $DATE"
	fi
}

################################################################################
getevaluation() {
	local STR=$1

	EVAL="$(sed -r 's/^.*http/http/' <<<"$STR")"
	if [[ -n $EVAL ]] ; then
		[[ $EVAL =~ https?:// ]] || error "Invalid eval URL: '$EVAL'"
	fi
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
getlocation() {
	LOC="$(read_json "$METAFILE" "$JSON_LOC")"
	if [[ -n $LOC && $LOC != null ]] ; then
		LOCATION="$LOC"
		if [[ $LOC = "Virtual" ]] ; then
			INPERSON=n
			debug "  Detecting Virtual class"
		else
			INPERSON=y
			debug "  Detecting In-person class in $LOC"
		fi
	fi
}

################################################################################
getopenenrol() {
	local CORP=$1
	if [[ -n $CORP && $CORP != null ]] ; then
		COMPANY="$CORP"
		if [[ $CORP == "OE" ]] ; then
			OPENENROL=y
			debug "  Detecting Open Enrolment class"
		else
			OPENENROL=n
			debug "  Detecting Corporate class for $CORP"
		fi
	fi
}

################################################################################
getrevision() {
	local STR=$1 REV

	REV="$(sed -r 's/^.*(v[0-9.]+).*$/\1/' <<<"$STR")"
	if [[ -n $REV && -z $REVISION ]] ; then
		REVISION="$(sed -e 's/^v//I' -e 's/^/V/' <<<"$REV")"
		debug "getrevision: REVISION=$REVISION"
	fi
}

################################################################################
gettitle() {
	local STR=$1 

	if [[ -z $TITLE && -e $METAFILE ]] ; then
		TITLE="$(read_json "$METAFILE" "$JSON_TITLE")"
	fi
	if [[ -z $TITLE ]] && command -v "$READYFOR" >/dev/null ; then
		TITLE="$("$READYFOR" -l 2>/dev/null \
			| grep "$STR" | sed -r -e "s/ *$STR - //")"
	fi
	if [[ -z $TITLE ]] ; then
		TITLE="$(query_json ".activities | .$COURSE | .title")"
	fi
	add_json "$METAFILE" "$JSON_TITLE" "$TITLE"
}

################################################################################
check_git_updates() {
	if [[ -z $NOUPDATE && -d $TEMPLATE/.git ]] ; then
		info "Checking for available updates"
		(cd $TEMPLATE
		git remote update >/dev/null
		if ! git status -uno | grep -q "Your branch is up to date" ; then
			if [[ -z $UPDATE ]] ; then
				warn "There is an update for CMD (Use --update to update)"
			else
				$TEST git pull >/dev/null
				warn "Updated $CMD"
				exit 0
			fi
		fi)
	fi
}

################################################################################
getdata_json() {
	[[ -f "$METAFILE" ]] || return 0
	info "Reading info from './$METAFILE'"

	[[ -n $DATE ]] || getdate "$(read_json "$METAFILE" "$JSON_DATE" 'Date')"
	[[ -n $COURSE ]] || getcourse "$(read_json "$METAFILE" "$JSON_CODE")"
	[[ -n $REVISION ]] || getrevision "$(read_json "$METAFILE" "$JSON_VERSION")"
	[[ -n $TIME ]] || TIME="$(read_json "$METAFILE" "$JSON_TIME")"
	[[ -n $ZONE ]] || ZONE="$(read_json "$METAFILE" "$JSON_ZONE")"
	[[ -n $KEY ]] || getkey "$(read_json "$METAFILE" "$JSON_KEY")"
	[[ -n $EVAL ]] || getevaluation "$(read_json "$METAFILE" "$JSON_SURVEY")"

	getopenenrol "$(read_json "$METAFILE" "$JSON_COMPANY")"
	getlocation "$(read_json "$METAFILE" "$JSON_LOC")"
}

################################################################################
WARN_DIR_STRUCTURE=
dir_warning() {
	if [[ -n $WARN_DIR_STRUCTURE ]] ; then
		warn "The directory is not in the form of DATE-CODE-CUSTOMER-LOCATION"
	fi
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
	if [[ -n $NCOURSE ]] ; then
		info "Reading info from '$NAME'"
		getcourse "$NCOURSE"
	else
		dir_warning
	fi
	[[ -n $COURSE ]] || return 0

	#-----------------------------------------------------------------------
	if [[ $NDATE =~ ^[0-9.]{8,}$ ]] ; then
		getdate "$NDATE"
	else
		dir_warning
	fi

	#-----------------------------------------------------------------------
	getopenenrol "$CORP"

	#-----------------------------------------------------------------------
	getlocation "$LOC"
}

################################################################################
getdata_pdf() {
	local FILE=$1 LINE
	local FILE="${1:-$CODEPDF}" LINE
	[[ $FILE =~ pdf$ && -f $FILE ]] || return 0
	info "Reading info from './$FILE'"

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
ymd_to_mdy() {
	local YMD=$1 Y M D MDY
	[[ -n $YMD ]] || error "No date found (use --date to fix)"
	if [[ $YMD =~ \. ]] ; then
		IFS=. read -r Y M D <<<"$YMD"
	elif [[ $YMD =~ - ]] ; then
		IFS=- read -r Y M D <<<"$YMD"
	elif [[ $YMD =~ / ]] ; then
		IFS=- read -r M D Y <<<"$YMD"
	elif [[ $YMD =~ 20[0-9]{6} ]] ; then
		IFS=- read -r Y M D <<<"$(sed -re 's/([0-9]{4})([0-9]{2})([0-9]{2})/\1-\2-\3/' <<<"$YMD")"
	fi
	[[ -n $D ]] || error "Date format not recognized: $YMD"
	MDY="${M#0}/${D#0}/$Y"
	debug "ymd_to_mdy: DATE:$YMD Y:$Y M:$M D:$D MDY:$MDY"
	echo "$MDY"
}

################################################################################
getdata_csv() {
	local FILE="${1:-$ROSTER}" MDY
	[[ $FILE =~ csv$ && -f $FILE ]] || return 0
	info "Reading info from '$FILE'"

	MDY="$(ymd_to_mdy "$DATE")"

	save_json "$(pwd)" "$FILE" "$MDY"

	local D R K E
	IFS=, read -r D R K E <<<"$(mlr --csv cut -f \
		"\"$JSON_DATE\",\"$JSON_VERSION\",\"$JSON_KEY\",\"$JSON_SURVEY\"" \
		<<<"$(tr -d '"' <"$FILE")" | grep "^$MDY")"

	[[ -n $REVISION ]] || getrevision "$R"
	[[ -n $KEY ]] || getkey "$K"
	[[ -n $EVAL ]] || getevaluation "$E"
}

################################################################################
getdata_other() {
	[[ -n $BITLY_LINK ]] || BITLY_LINK="$(read_json "$METAFILE" "$JSON_BITLY")"
	[[ -n $BITLY_LINK ]] || BITLY_LINK="$(getbitly "$EVAL")"
}

################################################################################
maketex() {
	#-----------------------------------------------------------------------
	if [[ -n $COURSE ]] ; then
		#shellcheck disable=SC2028
		echo "\\renewcommand{\\mycourse}{$COURSE}"
	else
		error "No course found (Use --course to fix)"
	fi

	#-----------------------------------------------------------------------
	if [[ -n $TITLE ]] ; then
		#shellcheck disable=SC2028
		echo "\\renewcommand{\\mytitle}{$TITLE}"
	else
		error "No title found for $COURSE (Use --title to fix)"
	fi

	#-----------------------------------------------------------------------
	if [[ -n $REVISION ]] ; then
		#shellcheck disable=SC2028
		echo "\\renewcommand{\\myversion}{$REVISION}"
	else
		error "No version found for $COURSE (Use --revision to fix)"
	fi

	#-----------------------------------------------------------------------
	if [[ -n $KEY ]] ; then
		#shellcheck disable=SC2028
		echo "\\renewcommand{\\mykey}{$KEY}"
	elif [[ $OPENENROL == n ]] ; then
		error "No registration key found for $COURSE (Use --key to fix)"
	fi

	#-----------------------------------------------------------------------
	if [[ -n $EVAL ]] ; then
		#shellcheck disable=SC2028
		echo "\\renewcommand{\\myevaluation}{$EVAL}"
	else
		error "No evaluation URL found for $COURSE (Use --evaluation to fix)"
	fi

	#-----------------------------------------------------------------------
	#shellcheck disable=SC2028
	[[ -z $TIME ]] || echo "\\renewcommand{\\myclasstime}{$TIME}"
	#shellcheck disable=SC2028
	[[ -z $ZONE ]] || echo "\\renewcommand{\\myclasstz}{$ZONE}"
	#shellcheck disable=SC2028
	[[ -z $INSTRUCTOR ]] || echo "\\renewcommand{\\myname}{$INSTRUCTOR}"
	#shellcheck disable=SC2028
	[[ -z $EMAIL ]] || echo "\\renewcommand{\\myemail}{$EMAIL}"

	#-----------------------------------------------------------------------
	if [[ -n $BITLY_LINK && $BITLY_LINK != null ]] ; then
		#shellcheck disable=SC2028
		echo "\\renewcommand{\\myeval}{$BITLY_LINK}"
	else
		warn "No bit.ly link generated. Disabling short links for eval"
		echo '\BITLYfalse{}'
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
	local FILE
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
makepdf() {
	if [[ -n $VERBOSE || -n $TEST ]] ; then
		$TEST make -C "$TEMPLATE" clean all
	else
		make -s -C "$TEMPLATE" clean spell
		if [[ -z $QUIET ]] ; then
			make -s -C "$TEMPLATE" >/dev/null
		else
			make -s -C "$TEMPLATE" >/dev/null 2>&1
		fi
	fi
}

################################################################################
copypdf() {
	local PDF=$1 NEW=$2
	$TEST cp $VERBOSE "$PDF" "$NEW"
	if [[ -n $COPY && -n $DESKTOPDIR ]] ; then
		if [[ -d $DESKTOPDIR ]] ; then
			$TEST cp -v "$PDF" "$DESKTOPDIR/$NEW"
		else
			warn "$DESKTOPDIR not found, so not copying there"
		fi
	fi
}

################################################################################
showpdf() {
	local PDF=$1
	if [[ -n $TEST && -n $SHOW ]] ; then
		echo $PDFVIEWER "$PDF"
	elif [[ -n $SHOW ]] ; then
		nohup $PDFVIEWER "$PDF" >/dev/null 2>&1 &
	fi
}

################################################################################
read_config() {
	# Read config file
	if [[ -e $CONF ]] ; then
		info "Reading config from '$CONF'"
		# shellcheck disable=SC1090
		source "$CONF"
	fi
	if [[ -e $LOCALCONF ]] ; then
		info "Reading config from './$LOCALCONF'"
		# shellcheck disable=SC1090
		source "$LOCALCONF"
	fi

	# Link tex config file
	[[ -n $TEMPLATE ]] || error "No TEMPLATE specified in $CONF"
	if [[ ! -e "$TEMPLATE/$CONFTEX" ]] ; then
		warn "Creating $TEMPLATE/$CONFTEX"
		rm -f "$TEMPLATE/$CONFTEX"
		ln -s "$CONFIGDIR/$CONFTEX" "$TEMPLATE/$CONFTEX"
	fi
}

################################################################################
usage() {
	if [[ $# -gt 0 ]] ; then
		echo -e "${RED}E: Invalid argument:" "$@" "$BACK"
	fi
	cat <<-HELP
	Version v$VERSION
	Usage: $CMD [options]
	    -c --course <course>         LFD/LFS course code/number
	    -d --date <YYYY.MM.DD>       Year.Month.Day of class
	    -e --evaluation <eval url>   The evaluation survey URL
	    -f --file <file>             The file from which to read metadata
	    -i --inperson <City>         An in-person class (default Virtual)
	    -I --virtual                 A virtual class
	    -k --key <key>               Registration code for OE class
	    -m --mail <email>            Instructor email
	    -n --name "<name>"           Instructor name
	    -o --oecourse                An Open Enrolment course (default Corporate)
	    -O --corporate <Company>     An Corporate course at Company
	    -r --revision <revision>     Version number of the course (e.g. V5.10)
	    -s --time <start-end times>  Daily start and end time of the class
	    -t --title "<title>"         Title of the course
	    -z --timezone <TZ>           Time zone of for the daily class times
	    -N --nocache                 Don't use cached versions of files
	    -U --noupdate                Don't check for $CMD updates
	    -h --help                    This help
	    -C --copy                    Copy the resulting PDF to $DESKTOPDIR
	    -D --debug                   Show debugging messages
	    -q --quiet                   Turn off most output
	    -R --trace                   Show code trace
	    -S --show                    View PDF with $PDFVIEWER
	    -T --test                    Test output
	    -u --update                  Update $CMD
	    -v --verbose                 Show latex build output
	    -V --version                 Show version of the script

	  $CMD will try to read metadata from the following sources:
	    1. The directory name Date-Code-Customer-Location
	    2. From text parsed from $CODEPDF
	    3. From $ROSTER
	    4. From $METAFILE
	    5. From $READYJSON
	    6. From $LOCALCONF (overrides all previous metadata)
	    7. From command line arguments as listed above (overrides previous)
	HELP
	exit 1
}

################################################################################
parse_args() {
	while [[ $# -gt 0 ]] ; do
		case "$1" in
			-c|--cou*) shift; getcourse "$1";;
			-C|--copy) COPY=y;;
			-d|--date*) shift; getdate "$1";;
			-D|--debug) DEBUG=y;;
			-e|--eval*) shift; getevaluation "$1";;
			-f|--file*) shift; FILE="$1";;
			-i|--in*) shift; getlocation "$1";;
			-I|--virtual) getlocation "Virtual";;
			-k|--key*) shift; getkey "$1";;
			-m|--mail) shift; EMAIL="$1";;
			-n|--name) shift; INSTRUCTOR="$1";;
			-N|--nocache) NOCACHE=y;;
			-U|--noupdate) NOUPDATE=y;;
			-o|--oe*) getopenenrol "OE";;
			-O|--corp*) shift; getopenenrol "$1";;
			-q|--quiet) QUIET=y;;
			-r|--rev*) shift; getrevision "$1";;
			-s|--start*|--time) shift; TIME="$1";;
			-S|--show) SHOW=y;;
			-t|--tit*) shift; TITLE="$1";;
			-R|--trace) set -x ;;
			-T|--test) TEST="echo";;
			-u|--update) UPDATE=y;;
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
read_config
parse_args "$@"
check_git_updates
getdata_json
getdata_dir
getdata_pdf "$FILE"
getdata_csv "$FILE"
getdata_other
[[ -n $QUIET ]] || metadata

################################################################################
if [[ -n $DEBUG ]] ; then
	maketex
else
	TEXFILE="${TEXFILE:-$TEMPLATE/course.tex}"
	rm -f "$TEXFILE"
	maketex > "$TEXFILE"

	PDFFILE="${PDFFILE:-$TEMPLATE/$PDFNAME.pdf}"
	makepdf "$PDFFILE"

	NEWFILE="$PDFNAME-$DATE-$COURSE-$REVISION-$COMPANY-$LOCATION.pdf"
	copypdf "$PDFFILE" "$NEWFILE"

	info "Created $NEWFILE"
	showpdf "$NEWFILE"
fi
