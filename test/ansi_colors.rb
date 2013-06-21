
#
# FROM
# http://kpumuk.info/ruby-on-rails/colorizing-console-ruby-script-output/
#
[0, 1].each do |attr|    # 0 == normal, 1 == bright
  puts '----------------------------------------------------------------'
  puts "ESC[#{attr};Foreground"
  30.upto(37) do |fg|
    0.upto(7) do |j|
      print "\033[#{attr};#{fg}m #{fg}  "
    end
    puts "\033[0m"
  end
end

[0, 1].each do |attr|    # 0 == normal, 1 == bright
  puts '----------------------------------------------------------------'
  puts "ESC[#{attr};Background"
  40.upto(47) do |bg|
    0.upto(7) do |j|
      print "\033[#{attr};#{bg}m #{bg}  "
    end
    puts "\033[0m"
  end
end

[0, 1].each do |attr|    # 0 == normal, 1 == bright
  puts '----------------------------------------------------------------'
  puts "ESC[#{attr};Foreground;Background"
  30.upto(37) do |fg|
    40.upto(47) do |bg|
      print "\033[#{attr};#{fg};#{bg}m #{fg};#{bg}  "
    end
    puts "\033[0m"
  end
end
