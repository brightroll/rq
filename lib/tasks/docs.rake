

require 'erb'

desc 'Build docs'
task :build_docs do

  # go through each file in the directory
  doc_files = Dir["docs/*.txt"]

  doc_files.delete("docs/index.txt")

  File.open('docs/index.txt', 'w') do
    |f|
    f.write( "# Documentation\n\n" )
    doc_files.each { | doc |
      next if doc == "index.txt"
      name = doc.split("/").last.split(".txt")[0]
      f.write( "* ## » [#{name}](#{name}.html)\n" )
    }
  end

  doc_files << "docs/index.txt" if not doc_files.index("docs/index.txt")

  template = nil
  File.open('docs/template.erb', 'r') do
    |f|
    template = f.read
  end

  doc_files.each do
    |path|
    new_path = path.split(".txt")[0] + ".htmlcontent"
    `./vendor/discount-2.1.5a/markdown -ftoc #{path} > #{new_path}`

    content = nil
    File.open(new_path, 'r') do
      |f|
      content = f.read
    end

    params = { :name => path.split("/").last.split(".txt")[0] }
    result = ERB.new(template, nil, '>').result(binding)
    out_path = path.split(".txt")[0] + ".html"
    File.open(out_path, 'w') { |f| f.write(result) }
    puts ">> Created ERB output at: #{out_path} from: #{path}"
  end
end


