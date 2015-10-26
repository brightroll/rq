#!/bin/sh

q=$1

cd /rq/current/config
host=`sed 's/,/\n/g' config.json | grep host | awk -F: '{print $NF}' | tr -d '\"'`
echo hostname is $host
#read junk

cd /rq/current/queue

if [ "x$q" = "x" ] ; then
        echo "Usage: $0 <queuename>"
        exit 1
fi

if [ ! -d $q ] ; then
        echo "Bad queue name: $q"
        exit 1
fi

cd /rq/current/queue/$q/err

c=`ls -1 | wc -l`

if [ $c -lt 1 ] ; then
        echo "nothing to clone here"
        exit 0
fi

mkdir -p /rq/tmp/$q > /dev/null 2>&1

for i in * ; do
        (cd /rq/current/ ; bin/rq clone --msg_id http://${host}:3333/q/${q}/${i} ) \
        && mv $i /rq/tmp/${q} || mv $i /rq/tmp/
done

