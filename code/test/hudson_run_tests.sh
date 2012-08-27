#!/bin/sh

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
export PATH

RQ_PORT=4444
export RQ_PORT

mkdir -p tmp
TMPDIR=`pwd`/tmp

STAT=0

echo "Running in "
pwd

echo "***** Stopping web_server being run by Hudson, if running..."
pkill -9 -u $USER -f web_server.rb

echo "***** Configuring web_server..."
mkdir -p config
echo "{\"env\":\"production\",\"port\":\"4444\",\"host\":\"127.0.0.1\",\"addr\":\"0.0.0.0\",\"tmpdir\":\"$TMPDIR\"}" > config/config.json
echo "***** Config file written"

echo "***** Starting test web_server..."
cp /dev/null /tmp/webserver.log
ruby bin/web_server.rb > /tmp/webserver.log 2>&1 &

echo "***** Sleeping a bit to let the web_server start up..."
sleep 8

echo "***** Deleting old queues and configs..."
/bin/rm -rf queue queue.noindex

echo "***** Running tests..."
./code/test/run_tests.sh
if [ $? -ne 0 ] ; then
	echo "***** FAILED!"
	STAT=1
fi

echo "***** Stopping queue mgr..."
bin/queuemgr_ctl stop

echo "***** Stopping test web_server..."
pkill -9 -u $USER -f web_server.rb

echo "***** Starting system web_server again..."
/rq/current/bin/web_server.rb server

if [ $STAT == 1 ]; then
    exit 1
fi