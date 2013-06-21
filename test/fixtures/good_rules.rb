
#rule "[blackhole_testhost]"
#src /^http:\/\/testhost\.stage\.btrll\.com/
#action :blackhole

rule "[mirror_processing_of_errors_with_delay]"
dest /\/barrier_process_err$/
action :relay
route "brxlog-be-halb01.btrll.com", "stats.btrll.com"
delay 10 

rule "[even_numbers_relay_host0]"
src /^http:\/\/barrier\d[02468]\.btrll\.com:3333/
action (ENV["BR_ENV"] == "prod" ? :relay : :done)
route "host0.btrll.com"
log true

rule "[odd_numbers_relay_host1]"
src /^http:\/\/barrier\d[13579]\.btrll\.com:3333/
action :relay
route ["brxlog-be-halb01.btrll.com", "brxlog-be-halb02.btrll.com"], ["stats1.btrll.com", "stats2.btrll.com"]

rule "[traffic_relay_host1]"
src /^checkin_v1$/
dest /^http:\/\/barrier\d[13579]\.btrll\.com:3333/
action :balance
route "brxlog-be-halb01.btrll.com", "stats.btrll.com"

rule "[old_data_center_route]"
dest /^http:\/\/host\.btrll\.com:3333/
action :relay
route "http://host1.btrll.com:3333/q/foobar"
log true

#rule "[manipulate_message]"
#dest /parse_logs/
#action :process
#processor "/br/reporting/current/rq/dispatch.rb"
#log true

rule "default"
action :err


