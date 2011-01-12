

rule "[test1]"
src /^dru$/
action :relay
route "cf.btrll.com", "statsfe.stage.btrll.com"
log true

rule "[test2]"
dest /./
action :relay
route "http://giao.btrll.com:3333/q/cleaner"
log true

rule "default"
action :err


