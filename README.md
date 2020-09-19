# Generate a course introduction slide deck for teaching an LF class

You can install this tool as follows:

1. apt install curl gawk jq make sed texlive
1. cd to/some/directory
1. git clone https://github.com/behanw/course-intro.git
1. cd course-intro
1. mkdir -p $HOME/bin/ $HOME/.config/course-intro/
1. ln -s $(pwd)/course-intro.sh ~/bin/course-intro
1. hash -r
1. cp example-settings.conf $HOME/.config/course-intro/settings.conf
1. cp example-settings.tex $HOME/.config/course-intro/settings.tex
1. Edit the 2 files in $HOME/.config/course-intro/ to add your own information
1. cd to/a/directory/where/you/keep/class/information
1. mkdir YYYY.MM.DD-LFD450-OE-Virtual
  * You can replace the course number with any valid LF course code
  * Instead of "OE" for Open Enrolment, you can substitute a company name
  * Instead of "Virtual" you can substitute the city for in-person course
1. mkdir YYYY.MM.DD-LFD450-OE-Virtual
1. course-intro

The script will try to guess information about the course from the directory
name, from a pdf called Code.pdf (found in the dated directroy created above,
which would be the print to PDF of the course information from the LF course
coordinator), or from the "Class Roster.csv" file which you received in email.

Make sure you adequately fill in settings.conf and settings.tex in your
$HOME/.config/course-intro directory.

## Command line options

Usage: course-intro.sh [options]
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
