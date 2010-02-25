#!/bin/sh

if [ "X$RQ_PORT" = "X" ] ; then
  RQ_PORT=3333
  export RQ_PORT
fi

./bin/unicorn -D -l $RQ_PORT

