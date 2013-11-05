#!/bin/bash

if [ "x${RQ_PORT}" = "x" ] ; then
  rq_port=3333
else
  rq_port=${RQ_PORT}
fi

./bin/check_rq -p $rq_port
