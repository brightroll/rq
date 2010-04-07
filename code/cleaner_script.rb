#!/bin/bash

set -e

function write_status {
  echo $1 $2 >&3
  echo `/bin/date` $1 $2
}

write_status 'run'  "starting clean"

if [ "X$RQ_PARAM1" == "X" ]; then
  echo "Empty queue name for cleaner script"
  write_status 'err' "empty RQ_PARAM1"
  exit 0
fi

cd "../../../../$RQ_PARAM1" 
write_status 'run'  "changed dir"
pwd
date '+%Y%m%d.%H:%M'

write_status 'run'  "rotating log files"

set +e
mv queue.log queue.log.`date '+%Y%m%d.%H:%M'`
set -e
find . -maxdepth 1 -name 'queue.log*' -type f -mtime +2 -printf "old log - %f\n"
find . -maxdepth 1 -name 'queue.log*' -type f -mtime +2 -exec /bin/rm -rf {} \;

write_status 'run'  "cleaning err"
cd err
find . -maxdepth 1 -type d -mtime +3 -name '??*' | wc -l
find . -maxdepth 1 -type d -mtime +3 -name '??*' -exec /bin/rm -rf {} \;
cd ..

write_status 'run'  "cleaning done"
cd done
find . -maxdepth 1 -type d -mtime +2 -name '??*' | wc -l
find . -maxdepth 1 -type d -mtime +2 -name '??*' -exec /bin/rm -rf {} \;
cd ..

write_status 'run'  "cleaning prep"
cd prep
find . -maxdepth 1 -type d -mtime +1 -name '??*' | wc -l
find . -maxdepth 1 -type d -mtime +1 -name '??*' -exec /bin/rm -rf {} \;
cd ..

write_status 'run'  "cleaning relayed"
cd relayed
find . -maxdepth 1 -type d -mtime +1 -name '??*' | wc -l
find . -maxdepth 1 -type d -mtime +1 -name '??*' -exec /bin/rm -rf {} \;
cd ..

date '+%Y%m%d.%H:%M'
echo "FINISHED"
write_status 'done' "done cleaning"

