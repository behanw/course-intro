#!/usr/bin/env bash
# Copyright (c) 2020-2021 Behan Webster <behanw@converseincode.com>
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

VERSION=1.9

#===============================================================================
# Global constants
CMD="$(basename "$0")"
CACHEDIR="$HOME/.cache/${CMD%.sh}"
CONFIGDIR="$HOME/.config/${CMD%.sh}"
CONF="$CONFIGDIR/settings.conf"
CONFTEX="$CONFIGDIR/settings.tex"
MYPID="$$"

#===============================================================================
# Global settings
BITLY_TOKEN=
CODEPDF="Code.pdf"
CURL="curl -s"
DESKTOPDIR="$HOME/Desktop"
LFCMURL="https://training.linuxfoundation.org/cm"
LFOPTS="--location-trusted"
LFPASS=""
LFUSER=""
LOCALCONF="intro.conf"
METAFILE="meta.json"
PDFNAME="course-intro"
PDFVIEWER="evince"
READYFOR="ready-for.sh"
READYJSON="https://training.linuxfoundation.org/cm/prep/data/ready-for.json"
ROSTER="../Class Roster.csv"
TEMPLATE=

#===============================================================================
# Per class settings
BITLY_LINK=
COMPANY=
COURSE=
DATE=
EMAIL=
EVAL=
GDRIVE=
GTR=
INPERSON=n
INSTRUCTOR=
KEY=
LOCATION=
MATERIALS=
OPENENROL=n
RCLONE=
REVISION=
TIME=
TITLE=
ZONE=

#===============================================================================
# Command line argument flags
COPY=
DEBUG=
FILE=
FORCE=
NOCACHE=
NOUPDATE=
QUIET=
SHOW=
TEST=
UPDATE=
VERBOSE=

#===============================================================================
# JSON Key names
#JSON_INSTR="Session Instructor"
#JSON_PASSWORD="Session Zoom Password"
#JSON_SKU="Session SKU"
#JSON_USERNAME="Session Zoom Username"
#JSON_ZOOM="Session Zoom Link"
JSON_BITLY="Survey Short URL"
JSON_CODE="Session Course Code"
JSON_COMPANY="Company"
JSON_DATE="Session Start Date"
JSON_DAYS="Course Days"
JSON_FILES="Course Materials"
JSON_GTR="Session GTR"
JSON_KEY="Session Class Key"
JSON_LOC="Session Location"
JSON_STUDENTS="# of Learners"
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
	info "  GTR:       '$GTR'"
	info "  Time:      '$TIME'"
	info "  TimeZone:  '$ZONE'"
	info "  Key:       '$KEY'"
	info "  Eval:      '$EVAL'"
	info "  Bitly Link:'$BITLY_LINK'"
	info "  Materials: '$MATERIALS'"
}

################################################################################
# Read data from a supplied JSON file
DATECMD="$(command -v gdate)" || DATECMD="$(command -v date)" || error "No date found. Try installing gdate."
get_json() {
	local JSON=$1 NAME=$2 OPTION=${3:-} DATA

	if [[ -z $JSON || ! -e $JSON ]] ; then
		warn "Read JSON: $JSON not found for $NAME"
		return
	fi

	DATA="$(jq --raw-output ".\"$NAME\"" "$JSON" | sed -e 's/\\n/\n/g')"

	case "$OPTION" in
		Date) [[ ! $DATA =~ / ]] || DATA="$($DATECMD -d "$DATA" "+%Y.%m.%d")";;
	esac

	[[ $DATA == null ]] || echo "$DATA"
}

################################################################################
# Read entry from local JSON file
read_json() {
	local NAME=$1 OPTION=${2:-}

	get_json "$METAFILE" "$NAME" "$OPTION"
}

################################################################################
# Add data to a JSON file
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
# Store entry in local JSON file
save_json() {
	local NAME=$1 DATA=${2:-}

	[[ -n $DATA ]] || return 0
	add_json "$METAFILE" "$NAME" "$DATA"
}

################################################################################
# Store one entry from a CSV file as a JSON file
csv_to_json() {
	local DIR=$1 CSV=$2 MDY=$3 NAME DATA
	local META="$DIR/$METAFILE"
	local NEW="$DIR/${METAFILE/.json/-new.json}"

	mlr --c2j --jlistwrap cat <<<"$(tr -d '"' <"$CSV")" \
		| jq ".[] | select(.\"$JSON_DATE\" | contains(\"$MDY\"))" \
		| sed -e 's/"false",/false,/' -e 's/"0",/0,/' -e 's/"v/"V/' \
		>"$NEW"
	if [[ ! -s $NEW ]] ; then
		debug rm -f "$NEW"
	elif [[ -e $META ]] ; then
		for NAME in "$JSON_COMPANY" "$JSON_DAYS" "$JSON_GTR" "$JSON_LOC" "$JSON_STUDENTS" ; do
			DATA="$(get_json "$META" "$NAME")"
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
	rm -f "$NEW"
}

################################################################################
# Query data from ready-for.json
query_ready_json() {
	local JSON="$CACHEDIR/${READYJSON##*/}" DATA
	mkdir -p "$CACHEDIR"
	if [[ -n $NOCACHE || ! -f $JSON ]] ; then
		$CURL "$READYJSON" >"$JSON"
	fi
	DATA="$(jq --raw-output "$@" "$JSON" 2>/dev/null || true)"
	[[ $DATA == null ]] || echo "$DATA"
}

################################################################################
# Lookup or generate a bit.ly link
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
		echo "$CURL -H \"$AUTH\" -H \"$TYPE\" -X POST \"$API\" -d '$JSON'" >&2
	else
		local DATA
		DATA="$($CURL -H "$AUTH" -H "$TYPE" -X POST "$API" -d "$JSON" | jq --raw-output .id)"
		[[ $DATA == null ]] || echo "$DATA"
	fi
}

################################################################################
# Get the course material files
getcm() {
	local FILES=
	debug "getcm"
	FILES="$(read_json "$JSON_FILES" | tr '\n' ' ')"
	[[ -n ${FILES% } ]] || FILES="$(query_ready_json ".activities | .$COURSE | .materials | .[]" | tr '\n' ' ')"
	if [[ -z ${FILES% } ]] ; then
		# shellcheck disable=SC2086
		FILES="$($CURL --user $LFUSER:$LFPASS $LFOPTS "$LFCMURL/$COURSE/" \
			| grep "${COURSE}_$REVISION" \
			| sed 's/^.*href="//; s/".*$//' \
			| tr '\n' ' ')"
	fi
	FILES="${FILES% }"
	[[ -z $FILES ]] || save_json "$JSON_FILES" "$FILES"
	info "getcm: $FILES"
	echo "$FILES"
}

################################################################################
# Get the course number
getcourse() {
	local STR=$1 NAME

	NAME="$(sed -r 's/^.*(LF[A-Z][0-9]+).*$/\1/' <<<"$STR")"
	if [[ -z $COURSE && -n $NAME ]] ; then
		COURSE="$NAME"
		debug "getcourse: '$COURSE'"
		gettitle "$COURSE"
	fi
}

################################################################################
# Get the course date
getdate() {
	local STR=$1

	if [[ -z $DATE && $STR =~ ^[0-9.]{8,10} ]] ; then
		DATE="$STR"
		debug "getdate: '$DATE'"
	fi
}

################################################################################
# Get the course evaluation survey URL
getevaluation() {
	local STR=$1 URL

	if [[ -z $EVAL ]] ; then
		URL="$(sed -r 's/^.*http/http/' <<<"$STR")"
		if [[ -n $URL ]] ; then
			[[ $URL =~ https?:// ]] || error "Invalid eval URL: '$EVAL'"
			EVAL="${URL//[$'\t\r\n']/}"
			debug "getevaluation: '$EVAL'"
		fi
	elif [[ $STR =~ course= && ! $EVAL =~ course= ]] ; then
		EVAL+="${STR//[$'\t\r\n']/}"
		warn "Evaluation URL found on 2 lines: $EVAL"
	fi
}

################################################################################
# Get the course registration key code
getkey() {
	local STR=$1 CODE

	CODE="$(sed -r 's/^.*: *//' <<<"$STR")"
	if [[ -z $KEY && -n $CODE ]] ; then
		[[ $CODE =~ ^[0-9A-Za-z]+$ ]] || error "Invalid course key: '$CODE'"
		KEY="$CODE"
		debug "getkey: '$KEY'"
	fi
}

################################################################################
# Get the course location as a city name, or Virtual
getlocation() {
	local LOC=$1
	if [[ -n $LOC && -z $LOCATION ]] ; then
		if [[ $LOC =~ ^[A-Z][SD]T$ ]] ; then
			if [[ -z $ZONE ]] ; then
				ZONE="$LOC"
			fi
			LOC="Virtual"
		fi
		LOCATION="$LOC"
		debug "getlocation: '$LOCATION'"
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
# Get the company name or mark Open Enrolment (OE)
getopenenrol() {
	local CORP=$1
	if [[ -n $CORP && -z $COMPANY ]] ; then
		COMPANY="$CORP"
		debug "getopenenrol: '$CORP'"
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
# Get the version of the course materials
getrevision() {
	local STR=$1 REV

	REV="$(sed -r 's/^.*(v[0-9.]+).*$/\1/' <<<"$STR")"
	if [[ -z $REVISION && -n $REV ]] ; then
		REVISION="${REV% *}"
		debug "getrevision: '$REVISION'"
	fi
	if [[ -n $REVISION && ! $REVISION =~ ^V ]] ; then
		REVISION="$(sed -e 's/^v//I' -e 's/^/V/' <<<"$REVISION")"
	fi
}

################################################################################
# Get the status of a course
getstatus() {
	local STR=$1

	if [[ -z $GTR && -n $STR ]] ; then
		case "$STR" in
			GTR|y|Y|true|True|TRUE) GTR=true;;
		esac
		debug "getstatus: '$GTR'"
	fi
}

################################################################################
# Get the time of a course
gettime() {
	local STR=$1

	if [[ -z $TIME && -n $STR ]] ; then
		TIME=$STR
		debug "gettime: '$TIME'"
	fi
}

################################################################################
# Get the timezone of a course
getzone() {
	local STR=$1

	if [[ -z $ZONE && -n $STR ]] ; then
		ZONE=$STR
		debug "getzone: '$ZONE'"
	fi
}

################################################################################
# Get the course title
gettitle() {
	local STR=$1 

	if [[ -z $TITLE && -e $METAFILE ]] ; then
		TITLE="$(read_json "$JSON_TITLE")"
		debug "gettitle: from JSON: '$TITLE'"
	fi
	if [[ -z $TITLE ]] && command -v "$READYFOR" >/dev/null ; then
		TITLE="$("$READYFOR" -l 2>/dev/null \
			| grep "$STR" | sed -r -e "s/ *$STR - //")"
		debug "gettitle: from $READYFOR: '$TITLE'"
	fi
	if [[ -z $TITLE ]] ; then
		TITLE="$(query_ready_json ".activities | .$COURSE | .title")"
		debug "gettitle: from URL: '$TITLE'"
	fi
	save_json "$JSON_TITLE" "$TITLE"
}

################################################################################
# Check for updates of this script
check_git_updates() {
	debug "check_git_updates"
	if [[ -z $NOUPDATE && -d $TEMPLATE/.git ]] ; then
		info "Checking for available updates"
		(cd "$TEMPLATE"
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
# Save class metadata to local JSON cache file
savedata_json() {
	[[ -f "$METAFILE" ]] || return 0
	debug "savedata_json: $METAFILE"
	info "Saving info to './$METAFILE'"

	save_json "$JSON_DATE" "$DATE"
	save_json "$JSON_COMPANY" "$COMPANY"
	save_json "$JSON_LOC" "$LOCATION"
	save_json "$JSON_CODE" "$COURSE"
	save_json "$JSON_TITLE" "$TITLE"
	save_json "$JSON_VERSION" "$REVISION"
	save_json "$JSON_TIME" "$TIME"
	save_json "$JSON_ZONE" "$ZONE"
	save_json "$JSON_KEY" "$KEY"
	save_json "$JSON_SURVEY" "$EVAL"

	[[ -z $GTR ]] || save_json "$JSON_GTR" 'true'
	[[ -z $BITLY_LINK ]] || save_json "$JSON_BITLY" "$BITLY_LINK"
}

################################################################################
# Look up class metadata from local JSON cache file
getdata_json() {
	[[ -f "$METAFILE" ]] || return 0
	debug "getdata_json: $METAFILE"
	info "Reading info from './$METAFILE'"

	getdate "$(read_json "$JSON_DATE" 'Date')"
	getcourse "$(read_json "$JSON_CODE")"
	getrevision "$(read_json "$JSON_VERSION")"
	getstatus "$(read_json "$JSON_GTR")"
	gettime "$(read_json "$JSON_TIME")"
	getzone "$(read_json "$JSON_ZONE")"
	getkey "$(read_json "$JSON_KEY")"
	getevaluation "$(read_json "$JSON_SURVEY")"

	getopenenrol "$(read_json "$JSON_COMPANY")"
	getlocation "$(read_json "$JSON_LOC")"
}

################################################################################
# Warn about invalid directory naming convention
WARN_DIR_STRUCTURE=
dir_warning() {
	if [[ -n $WARN_DIR_STRUCTURE ]] ; then
		warn "The directory is not in the form of DATE-CODE-CUSTOMER-LOCATION"
	fi
}

################################################################################
# Look up class metadata from directory name
getdata_dir() {
	local NAME CORP LOC STAT
	NAME="$(basename "$(pwd)")"
	debug "getdata_dir: $NAME"
	# shellcheck disable=SC2034
	local NDATE NCOURSE CORP LOC STAT <<<"$NAME"
	IFS=- read -r NDATE NCOURSE CORP LOC STAT <<<"$NAME"

	debug "  getdata_dir: DATE:$NDATE COURSE:$NCOURSE CORP:$CORP LOC:$LOC STAT:$STAT"

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

	#-----------------------------------------------------------------------
	getstatus "${STAT:-GTR}"
}

################################################################################
# Change the format of date from YYYY.MM.DD to MM/DD/YYYY for CSV lookup
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
# Try to find useful information in random lines of text in the input PDF
makeguess() {
	local LINE="$1" MDY="$2" STUDENTS DELIVERY NOD

	DELIVERY="$(cut -c149-167 <<<"$LINE" | sed -e 's/ //g; s/0016/2020/')"
	#DELIVERY="${LINE:151,23}"
	if [[ -n $DELIVERY && $DELIVERY == "$MDY" ]] ; then
		debug "  $COURSE is delivered on '$DELIVERY'"
	else
		return 0
	fi

	STUDENTS="$(cut -c127-147 <<<"$LINE" | sed -re 's/^ *//; s/([0-9]+).*$/\1/')"
	#STUDENTS="$(sed -re 's/^([0-9]+).*$/\1/' <<<"${LINE:129,21}")"
	if [[ -n $STUDENTS && $STUDENTS =~ [0-9] ]] ; then
		debug "  $COURSE has '$STUDENTS' students"
		save_json "$JSON_STUDENTS" "$STUDENTS"
	fi

	NOD="$(cut -c169-182 <<<"$LINE" | sed -e 's/ //g')"
	#NOD="${LINE:175,16}"
	if [[ -n $NOD && $NOD =~ [0-9] ]] ; then
		debug "  $COURSE is '$NOD' days long"
		save_json "$JSON_DAYS" "$NOD"
	fi

	debug "makeguess: STUDENTS:$STUDENTS DELIVERY:$DELIVERY NOD:$NOD"
}

################################################################################
# Look up class metadata from local printed confirmation email as a PDF
getdata_pdf() {
	local FILE="${1:-$CODEPDF}" LINE MDY
	debug "getdata_pdf: $FILE"
	[[ $FILE =~ pdf$ && -f $FILE ]] || FILE="$CODEPDF"
	[[ -f $FILE ]] || return 0
	info "Reading info from './$FILE'"
	MDY="$(ymd_to_mdy "$DATE")"

	while IFS='' read -r LINE ; do
		[[ -n $LINE ]] || continue
		# shellcheck disable=SC2001
		LINE="$(sed 's/^[ 	]*//' <<<"$LINE")"
		#debug "getdata_pdf: $LINE"
		case "$LINE" in
			Subject:*LF*) getcourse "$LINE";;
			*Book:*v[0-9]*) getrevision "$LINE";;
			*LF[CDSW][0-9]*:*v[0-9]*) getrevision "$LINE";;
			Version:*v[0-9]*) getrevision "$LINE";;
			Registration*URL:*) continue;;
			Registration*Code:*) getkey "$LINE";;
			Reg*:*) getkey "$LINE";;
			Survey*:*) getevaluation "$LINE";;
			Evaluation:*) getevaluation "$LINE";;
			course=*) getevaluation "$LINE";;
			*) makeguess "$LINE" "$MDY";;
		esac
	done <<<"$(pdfgrep . "$FILE")"
}

################################################################################
# Look up class metadata from weekly CSV file
getdata_csv() {
	local FILE="${1:-$ROSTER}" MDY
	debug "getdata_csv: $FILE"
	[[ $FILE =~ csv$ && -f $FILE ]] || FILE="$ROSTER"
	[[ -f $FILE ]] || return 0
	info "Reading info from '$FILE'"

	MDY="$(ymd_to_mdy "$DATE")"
	csv_to_json "$(pwd)" "$FILE" "$MDY"

	local D R K E
	IFS=, read -r D K R E <<<"$(mlr --csv cut -f \
		"$JSON_DATE,$JSON_KEY,$JSON_VERSION,$JSON_SURVEY" <"$FILE" \
		| grep "$DATE")"
		#<<<"$(tr -d '"' <"$FILE" | grep -E "^Session|$DATE")")"
	#info "MDY:$MDY DATE:$D REV:$R KEY:$K EVAL:$E"

	getrevision "$R"
	getkey "$K"
	getevaluation "$E"
}

################################################################################
# Look up other class metadata
getdata_other() {
	debug "getdata_other"

	[[ -n $BITLY_LINK ]] || BITLY_LINK="$(read_json "$JSON_BITLY")"
	[[ -n $BITLY_LINK ]] || BITLY_LINK="$(getbitly "$EVAL")"

	MATERIALS="$(getcm)"
}

################################################################################
# Generate the tex code for the metadata for this class
maketex() {
	debug "maketex"
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
		info "Building Open Enrolment class"
		#shellcheck disable=SC2028
		echo '\CORPfalse{}'
	else
		warn "Building Corporate class ${CORP:+for $CORP} (Use --oe to change)"
	fi

	#-----------------------------------------------------------------------
	if [[ $INPERSON == y ]] ; then
		info "Building In-person class ${LOCATION:+in $LOCATION}"
		#shellcheck disable=SC2028
		echo '\VIRTUALfalse{}'
	else
		warn "Building Virtual class (Use --inperson to change)"
	fi

	#-----------------------------------------------------------------------
	local FILE
	for FILE in $MATERIALS ; do
		#shellcheck disable=SC2028
		FILE="$(sed -r -e "s/V[0-9.]+/$REVISION/;" -e 's/_/\\_/g' <<<"$FILE")"
		#shellcheck disable=SC2028
		case "$FILE" in
			*SOLUTIONS*) echo "\\renewcommand{\\solutions}{\\item $FILE}";;
			*RESOURCES*) echo "\\renewcommand{\\resources}{\\item $FILE}";;
		esac
	done

	#-----------------------------------------------------------------------
	echo "\\renewcommand{\\lfuser}{$LFUSER}"
	echo "\\renewcommand{\\lfpass}{$LFPASS}"
}

################################################################################
# Build the PDF slide deck for this class
makepdf() {
	debug "makepdf"
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
# Copy the PDF slide deck for this class to the appropriate places
copypdf() {
	local PDF=$1 NEW=$2
	debug "copypdf"
	# shellcheck disable=SC2086
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
getrclonefiles() {
	info "rclone ls '$DIR'"
	rclone ls "$DIR" \
		| grep -r -E "${COURSE}_$REVISION.pdf$|SLIDES|SOLUTIONS|RESOURCES|WM" \
		| awk '{print $4}'
}

################################################################################
rclonefiles() {
	[[ -n ${RCLONE:-} ]] || return 0

	local DOCDIR='.'
	if [[ -n ${COPY:-} && -n ${DESKTOPDIR:-} ]] ; then
		DOCDIR="$DESKTOPDIR"
	fi

	if [[ -n ${GDRIVE_LOCAL:-} ]] ; then
		local DIR="$GDRIVE_LOCAL/${COURSE:0:3}/$COURSE/$REVISION"
		if [[ ${COURSE:3:1} = "5" ]] ; then
			DIR="$(echo "$GDRIVE_LOCAL"/CUSTOM/"$COURSE"*/"$REVISION")"
		fi
		info "DIR=$DIR"
		rsync -v "$DIR"/*{"${COURSE}_$REVISION.pdf",SLIDES,SOLUTIONS,RESOURCES,WM}* "$DOCDIR"
		chmod go+rX "$DOCDIR"/*{"${COURSE}_$REVISION.pdf",SLIDES,SOLUTIONS,RESOURCES,WM}*
		return
	fi

	if [[ -z ${GDRIVE:-} ]] ; then
		warn "No drive specified for rclone"
	else
		local FILES='' FILE
		local DIR="$GDRIVE/${COURSE:0:3}/$COURSE/$REVISION"
		if [[ ${COURSE:3:1} = "5" ]] ; then
			DIR="$GDRIVE/CUSTOM/$COURSE-*/$REVISION"
		fi
		while [[ -z $FILES ]] ; do
			FILES="$(getrclonefiles "$DIR")"
			sleep 2
		done
		# shellcheck disable=SC2086
		info "rclone" $FILES
		for FILE in $FILES ; do
			info "rclone copy '$DIR/$FILE' '$DOCDIR'"
			if [[ ! -f $DOCDIR ]] ; then
				while true ; do
					rclone copy "$DIR/$FILE" "$DOCDIR" && break
					sleep 3
				done
			fi
		done
	fi
}

################################################################################
# Optionally show the PDF slide deck
showpdf() {
	local PDF=$1
	debug "showpdf"
	if [[ -n $TEST && -n $SHOW ]] ; then
		echo $PDFVIEWER "$PDF"
	elif [[ -n $SHOW ]] ; then
		nohup $PDFVIEWER "$PDF" >/dev/null 2>&1 &
	fi
}

################################################################################
# Read global and local config files
read_config() {
	debug "read_config"
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
	else
		info "No config found. Default $LOCALCONF installed"
		copy_intro_conf .
	fi

	# Link tex config file
	[[ -n $TEMPLATE ]] || error "No TEMPLATE specified in $CONF"
	local TEMPTEX="$TEMPLATE/${CONFTEX##*/}"
	if [[ ! -e "$TEMPTEX" ]] ; then
		warn "Creating $TEMPTEX"
		rm -f "$TEMPTEX"
		ln -s "$CONFTEX" "$TEMPTEX"
	fi
}

################################################################################
copy_intro_conf() {
	local DIR=${1:-.}
	local INTRO="$DIR/$LOCALCONF" EXAMPLE="$CONFIGDIR/example-$LOCALCONF"
	debug "copy_intro_conf: EXAMPLE=$EXAMPLE DIR=$DIR INTRO=$INTRO"
	if [[ -z $FORCE && -f $INTRO ]] ; then
		error "$INTRO already exists"
	elif [[ -f $EXAMPLE ]] ; then
		$TEST cp -v "$EXAMPLE" "$INTRO"
	else
		error "No $EXAMPLE found"
	fi
}

################################################################################
# Help text
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
	    --intro-conf                 Create intro.conf from template
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
	    1. From command line arguments
	    2. From $LOCALCONF (overrides all previous metadata)
	    3. From $METAFILE
	    4. The directory name Date-Code-Customer-Location
	    5. From text parsed from $CODEPDF
	    6. From $ROSTER
	    7. From $READYJSON
	HELP
	exit 1
}

################################################################################
# Parse early CLI arguments
parse_early_args() {
	while [[ $# -gt 0 ]] ; do
		case "$1" in
			-D|--debug) DEBUG=y;;
			-q|--quiet) QUIET=y;;
			-R|--trace) set -x ;;
			-T|--test) TEST="echo";;
			-v|--verbose) VERBOSE="-v";;
			-h|--help) usage ;;
		esac
		shift
	done
}

################################################################################
# Parse CLI arguments
parse_args() {
	debug "parse_args"
	while [[ $# -gt 0 ]] ; do
		case "$1" in
			-a|--all*) COPY=true; RCLONE=true;;
			-c|--cou*) shift; getcourse "${1:-}";;
			-C|--copy) COPY=y;;
			-d|--date*) shift; getdate "${1:-}";;
			-D|--debug) DEBUG=y;;
			-e|--eval*) shift; getevaluation "${1:-}";;
			-f|--file*) shift; FILE="${1:-}";;
			-F|--force) FORCE=y;;
			-g|--gtr) GTR=true;;
			-G|--notgtr) GTR=false;;
			--intro*) copy_intro_conf "${2:-.}"; exit 0;;
			-i|--in*) shift; getlocation "${1:-}";;
			-I|--virtual) getlocation "Virtual";;
			-k|--key*) shift; getkey "${1:-}";;
			-m|--mail) shift; EMAIL="${1:-}";;
			-n|--name) shift; INSTRUCTOR="${1:-}";;
			-N|--nocache) NOCACHE=y;;
			-o|--oe*) getopenenrol "OE";;
			-O|--corp*) shift; getopenenrol "${1:-}";;
			-q|--quiet) QUIET=y;;
			-r|--rev*) shift; getrevision "${1:-}";;
			-R|--rclone) RCLONE=y;;
			-s|--start*|--time) shift; TIME="${1:-}";;
			-S|--show) SHOW=y;;
			-t|--tit*) shift; TITLE="${1:-}";;
			-T|--test) TEST="echo";;
			--trace) set -x ;;
			-u|--update) UPDATE=y;;
			-U|--noupdate) NOUPDATE=y;;
			-z|--tz|--timezone|--zone) shift; ZONE="${1:-}";;
			-v|--verbose) VERBOSE="-v";;
			-V|--version) echo "$CMD v$VERSION"; exit 0;;
			-h|--help) usage ;;
			*) usage "$@" ;;
		esac
		shift
	done
}

################################################################################
parse_early_args "$@"
read_config
check_git_updates
getdata_json
parse_args "$@"
getdata_dir
getdata_pdf "$FILE"
getdata_csv "$FILE"
getdata_other
rclonefiles &
RPID="${!:-}"
metadata
savedata_json

################################################################################
TEXFILE="${TEXFILE:-$TEMPLATE/course.tex}"
rm -f "$TEXFILE"
maketex > "$TEXFILE"
[[ -z $DEBUG ]] || cat "$TEXFILE"

PDFFILE="${PDFFILE:-$TEMPLATE/$PDFNAME.pdf}"
makepdf "$PDFFILE"

NEWFILE="$PDFNAME-$DATE-$COURSE-$REVISION-$COMPANY-$LOCATION.pdf"
copypdf "$PDFFILE" "$NEWFILE"

info "Created $NEWFILE"
showpdf "$NEWFILE"

wait "$RPID"
