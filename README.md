# Generate a course introduction slide deck for teaching an LF class

## Install Instructions

### Quickstart

 1. Install packages: curl ghostscript jq make miller pdfgrep sed texlive
 2. git clone https://github.com/behanw/course-intro.git
 3. Install example-\* files into $HOME/.config/course-intro/ and customize
 4. Run course-intro.sh in the directory for a class to generate a slide deck

### Exact steps

You can install this tool with these exact steps:

 1. sudo apt install curl ghostscript jq make miller pdfgrep sed texlive
 2. cd to/some/directory
 3. git clone https://github.com/behanw/course-intro.git
 4. cd course-intro
 5. mkdir -p $HOME/bin/ $HOME/.config/course-intro/
 6. ln -s $(pwd)/course-intro.sh ~/bin/course-intro
 7. hash -r
 8. cp example-settings.conf $HOME/.config/course-intro/settings.conf
 9. cp example-settings.tex $HOME/.config/course-intro/settings.tex
 10. Edit the 2 files in $HOME/.config/course-intro/ to add your own information
 11. cd to/a/directory/where/you/keep/class/information
 12. mkdir YYYY.MM.DD-LFD450-OE-Virtual
 13. cd YYYY.MM.DD-LFD450-OE-Virtual
 14. course-intro --info
 15. Edit intro.conf (this and the preceding step are optional)
 15. course-intro

## Global Configuration

Make sure you adequately fill in *settings.conf* and *settings.tex* in your
*$HOME/.config/course-intro/* directory.

### *settings.conf*

 * *ROSTER* needs to point to where your *Class Roster.csv* is saved from email. (No default)
 * *TEMPLATE* needs to point to the directory you checked out from github which has the latex files in it. (No default)
 * *BITLY_TOKEN* is your [bitly API TOKEN](https://support.bitly.com/hc/en-us/articles/230647907-How-do-I-generate-an-OAuth-access-token-for-the-Bitly-API-) (No default)
 * *DESKTOPDIR* points to the directory where you want the resulting PDF copied with --copy (Defaults to *$HOME/Desktop*)

### *settings.tex*

 * \myname should be set to your name (and/or nickname)
 * \myemail should be set to your email address
 * \myeblurb should be set to any extra information about you
 * \myclasstime should be set to your default class times
 * \myclasstz should be set to your default time zone

## Individual Class metadata

The script will try to guess information about the class from a number of sources.
It does it's best not to have ferret out information from various files.

    my_classes_dir
    |-- Class Roster.csv
    |-- 2020.09.07-LFD435-Acme_Anvils-Virtual
    |   |-- Code.pdf
    |   |-- course-intro.pdf
    |   |-- intro.conf
    |   `-- meta.json
    |-- 2020.09.14-LFD430-OE-Virtual
    |   |-- Code.pdf
    |   |-- course-intro.pdf
    |   `-- meta.json
    `-- 2020.09.28-LFD5426-Sprocket_Corp-Tokyo
        `-- meta.json

 1. From the specially named directory: *Date-Code-Customer-Location*
 2. From a per-class *Code.pdf* file (email from the LF course coordinator printed to a PDF)
 4. From *Class Roster.csv* which you received in email (a file which lists all upcoming classes)
 3. From a per-class *meta.json* file (which caches information per class from the CSV file which changes over time)
 5. From the prep page: *https://training.linuxfoundation.org/cm/prep/data/ready-for.json*
 6. From a per-class settings in a file called *intro.conf* you put 
 7. From arguments passed to the script

### The Directory structure

The assumption is that each class has a Date-Code-Customer-Location structure.
For instance:

 * 2020.07.01-LFD450-OE-Virtual
 * 2020.10.31-LFS426-Acme_Anvils-Reykjavik

 1. The date needs to be in YYYY.MM.DD format (which sorts properly)
 2. The course needs to be a valid LF course code
 3. The customer can be and name (with underscores) or "OE" for Open Enrolment.
 4. The location can be "Virtual" or any city name (with underscores)

### *Code.pdf*

If you print the email of the course confirmation from the course coordinator
to a file called *Code.pdf*, the script can use pdfgrep to extract information
from this file (if the email is formatted the way it was when this was written).
The lines from the file which will be parsed:

    Subject: LFD435 Acme Corp Month Day, Year - Training info
    Version: v5.5
    Reg #: acmecoursekey
    Surveymonkey: https://www.surveymonkey.com/r/CODE?course=LFD435_Date

### *Class Roster.csv*

This comma-seperated-values file is sent by the course coordinator and records
all of an instructor's upcoming classes. This file contains which course, location,
zoom links, course keys, evaluation survey links and more. The script will read
the appropriate meta data from this file if available.

However this file won't show past classes. As a result, it will automatically
extract the metadata for this class and store it as meta.json file in each class
directory.

### *meta.json*

This file contains the metadata for the class in this directory. It is created
by the script to cache information about the class from the *Class Roster.csv*
file. Since the CSV file only shows future classes, the meta.json file largley
holds information for past classes. This file is consulted before the CSV file
if it exists.

### Prep page JSON

The script will look up things in the following JSON file like the title of the course,
and whether the class has a SOLUTIONS file, RESOURCES file, or both.

    https://training.linuxfoundation.org/cm/prep/data/ready-for.json

### *intro.conf*

Sometimes one can't effectively guess information nor rely on default configuration
to get class specifics. As a result you can use this configuration file to override
any of the automatically detected values. All of these settings are optional, and
override all values described above.

    INSTRUCTOR="My Name (nickname)"
    EMAIL="My@email.address"
    DATE="YYYY-MM-DD"
    TIME="9am-5pm"
    ZONE="CST"
    INPERSON=y
    OPENENROL=y
    COMPANY=Acme
    LOCATION=Vancouver_Island
    COURSE=LFDXXX
    TITLE="The title of the course"
    REVISION="V5.10"
    KEY="C0URS3K3Y"
    EVAL="https://surveymonkey/url"

### Command line options

Using the command-line will allow you to override all values specified in files
above this section.

    Usage: course-intro.sh [options]
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
        -U --noupdate                Don't check for course-intro updates
        -h --help                    This help
        -C --copy                    Copy the resulting PDF to /home/behanw/Host/Desktop
        -q --quiet                   Turn off most output
        -S --show                    View PDF with evince
        -u --update                  Update course-intro
        -v --verbose                 Show latex build output
        -V --version                 Show version of the script

## Example of running the script

    $ cd 2020.09.07-LFD435-Sprocket_Corp-Mohave_Desert
    $ ls
    Code.pdf     intro.conf
    $ course-intro

    I: Reading info from '2020.09.07-LFD435-Sprocket_Corp-Mohave_Desert' 
    I:   Detecting date as 2020.09.07
    I:   Detecting Corporate class for Sprocket_Corp
    I:   Detecting In-person class in Mohave_Desert
    I: Reading info from 'Code.pdf' 
    I: Reading info from '$HOME/Expenses/Class Roster.csv' 
    I: Reading info from 'intro.conf' 
    I: Name:      'Wile E. Coyote (Genius)' 
    I: Email:     'wile.e.coyote@acme.desert' 
    I: OpenEnrol: 'n' 
    I: InPerson:  'y' 
    I: Course:    'LFD435' 
    I: Title:     'Embedded Linux Device Drivers' 
    I: Revision:  'V5.8' 
    I: Time:      '9am-5pm' 
    I: TimeZone:  'MST' 
    I: Key:       'sprocket2020' 
    I: Eval:      'https://www.surveymonkey.com/r/SPROCKET?course=LFD435_20200907_CORP' 
    W: Building Corporate class for Sprocket_Corp (Add --oe to change) 
    W: Building In-person class in Mohave_Desert
    I: Spellchecking course-intro.tex
    I: Building course-intro.tex
    I: Compressing course-intro.pdf
    I: Created course-intro.pdf 
