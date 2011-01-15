#!/bin/bash

function write_status {
  echo $1 $2 >&3
}

echo
echo
echo "A URL to test http://xxeo.com/ or http://www.brightroll.com/"
echo
echo

TESTDIR=`dirname $0`
ruby "${TESTDIR}/ansi_colors.rb"

echo
echo
echo "CHARACTERS THAT REQUIRE HTML/XML ESCAPES"
echo
echo " & &< < >  "
echo
echo


echo 'done'
write_status 'done' 'done sleeping'


