rule "[mirror_processing_of_errors_with_delay]"
dest /\/old_queue_name$/
action :relay
route "http://mc34.btrll.com:3333/q/new_queue_name"
log true
