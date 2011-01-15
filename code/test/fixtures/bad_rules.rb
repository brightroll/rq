
rule "[mirror_processing_of_errors_with_delay]"
dest /\/barrier_process_err$/
action :relay
route "brxlog-be-halb01.btrll.com", "stats.btrll.com"
delay 10 

rule "[old_data_center_route]"
dest "flarby"
action 'relay'
route == "http://host1.btrll.com:3333/q/foobar"
log TRUE

action :err
