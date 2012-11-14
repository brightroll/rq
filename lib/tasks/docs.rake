

require 'erb'

desc 'Build docs'
task :build_docs do

  template = nil
  File.open('docs/template.erb', 'r') do
    |f|
    template = f.read
  end

  ["README.md"].each do
    |path|
    new_path = path.split(".md")[0] + ".htmlcontent"
    `./vendor/discount-2.1.5a/markdown -ftoc #{path} > #{new_path}`

    content = nil
    File.open(new_path, 'r') do
      |f|
      content = f.read
    end

    params = { :name => path.split("/").last.split(".md")[0] }
    result = ERB.new(template, nil, '>').result(binding)
    out_path = path.split(".md")[0] + ".html"
    File.open(out_path, 'w') { |f| f.write(result) }
    puts ">> Created ERB output at: #{out_path} from: #{path}"
  end
end


