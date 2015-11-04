#!/bin/sh
# moves all RQ errors into /rq/tmp

BASEDEST=/rq/tmp

if [ ! -d $BASEDEST ]
then
  echo "$BASEDEST does not exist"
  exit 1
fi

for fullqueue in `find /rq/current/queue/ -maxdepth 1 -not -wholename /rq/current/queue/ -type d`
do
  cd $fullqueue/err
  queue=`basename $fullqueue`
  DEST=$BASEDEST/$queue
  mkdir -p $DEST
  if [ -w $DEST ]
  then
    FINALDEST=$DEST
  else
    FINALDEST=$BASEDEST
  fi
  for i in `find . -maxdepth 1 -not -wholename . -type d`; do
    echo "moving $i to $FINALDEST/$i"
    mv $i $FINALDEST
  done
done

