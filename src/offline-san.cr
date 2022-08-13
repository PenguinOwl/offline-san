require "lexbor"
require "http"
require "uri"

def safe_web_get(url)
  begin
    return HTTP::Client.get(url).body
  rescue e
    puts "Failed: #{e.message}, retrying..."
    sleep 10
    return safe_web_get(url)
  end
end

url = ARGV[0]

STYLE = {{ read_file("src/style.css")}}

chapters = [] of NamedTuple(id: Int32, link: String, title: String)
content = Lexbor::Parser.new(safe_web_get(url + "?toc=1"))
chapter_count = content.css(".cnt_toc").first.inner_text.to_i
title = content.css(".fic_title").first.inner_text
author = content.css(".auth_name_fic").first.inner_text
synopsis = content.css(".wi_fic_desc").first.inner_html
img_url = URI.parse(content.css(".fic_image").first.scope.nodes(:img).first["src"])
chapters += content.css(".toc_ol .toc_w").map{|node| {id: node["order"].to_i, link: node.scope.nodes(:a).first["href"], title: node.scope.nodes(:a).first.inner_text}}

base_path = Path["~/.offline-san/books/#{title}"].expand(home: true)
finished_path = Path["~/.offline-san/finished/"].expand(home: true)
Dir.mkdir_p(base_path)
Dir.mkdir_p(finished_path)

unless File.exists?(base_path / "style.css")
  File.write(base_path / "style.css", STYLE)
end

puts "Found webnovel #{title}, retrieving chapters"
puts "Scanned first page, found #{chapter_count} chapters."

title_page = <<-HERE
<p>#{chapter_count} chapters.</p>

<p>Compiled #{Time.local} by offline-san.</p>

<p>Available online at <a href="#{url}">#{url}</a>.</p>
<div style="page-break-after: always"></div><br>
<b>Synopsis:</b>
<br>
#{synopsis}
<div style="page-break-after: always"></div><br>
<body>
HERE
File.write(base_path / "title.html", title_page)
puts "Generated title page."

ending_page = <<-HERE
</body>
HERE
File.write(base_path / "end.md", ending_page)
puts "Generated end page."

img_extension = img_url.path.match(/\.\w+$/).not_nil![0]
img_path = base_path / ("cover" + img_extension)
unless File.exists?(img_path)
  File.write(img_path, safe_web_get(img_url))
end
puts "Downloaded cover image."

(2..(chapter_count // 15 + 1)).each do |index|
  content = Lexbor::Parser.new(safe_web_get(url + "?toc=" + index.to_s))

  chapter_count = content.css(".cnt_toc").first.inner_text.to_i

  chapters += content.css(".toc_ol .toc_w").map{|node| {id: node["order"].to_i, link: node.scope.nodes(:a).first["href"], title: node.scope.nodes(:a).first.inner_text}}
  puts "Scanned page #{index} of #{(chapter_count // 15 + 1)}."
end

chapter_files = [] of NamedTuple(id: Int32, path: String)

chapters.each do |chapter|
  path = base_path / "#{chapter[:id].to_s.rjust(5, '0')}.html"
  chapter_files << {id: chapter[:id], path: path.to_s}
  next if File.exists?(path)
  content = Lexbor::Parser.new(safe_web_get(chapter[:link]))
  raw = content.css(".chp_raw").first.inner_html
  data = "<h1>#{chapter[:title]}</h1>" + raw + "<div style=\"page-break-after: always\"></div><br>\n\n"
  File.write(path, data)
  puts "Downloaded chapter #{chapter[:id]}, \"#{chapter[:title]}\""
end

puts "Compiling epub..."
export = (base_path / "#{title}.epub")
system "pandoc --epub-chapter-level 1 \"#{(base_path / "title.html")}\" \"#{chapter_files.sort_by{|e| e[:id]}.map{|e| e[:path].to_s}.join("\" \"")}\" \"#{(base_path / "end.md")}\" -o \"#{export}\" --epub-cover-image \"#{img_path}\" --metadata title=\"#{title}\" --metadata author=\"#{author}\" -c \"#{base_path / "style.css"}\""

File.copy((base_path / "#{title}.epub"), (finished_path / "#{title}.epub"))
puts "Finished compiling #{title} to #{export}."
