#!/bin/bash

function write_status {
  echo $1 $2 >&3
}

echo
echo
echo "A URL to test http://xxeo.com/ or http://www.brightroll.com/"
echo
echo

if [ "$RQ_PARAM1" == "slow" ]; then
  sleep 2
fi

TESTDIR=`dirname $0`
ruby "${TESTDIR}/ansi_colors.rb"

if [ "$RQ_PARAM1" == "slow" ]; then
  sleep 2
  ruby "${TESTDIR}/ansi_colors.rb"
  sleep 2
  ruby "${TESTDIR}/ansi_colors.rb"
fi

echo
echo
echo "CHARACTERS THAT REQUIRE HTML/XML ESCAPES"
echo
echo " & &< < >  "
echo
echo

if [ "$RQ_PARAM1" == "slow" ]; then
  sleep 2
fi

echo 'done'
write_status 'done' 'done sleeping'


