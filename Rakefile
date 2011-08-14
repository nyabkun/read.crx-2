SRC = "src"
DBG = "debug"

def haml(src, output)
  sh "haml -q #{src} #{output}"
end

def sass(src, output)
  sh "sass --style compressed --no-cache #{src} #{output}"
end

def coffee(src, output)
  sh "cat #{src} | coffee -cbsp > #{output}"
end

rule ".html" => "%{^#{DBG}/,#{SRC}/}X.haml" do |t|
  haml(t.prerequisites, t.name)
end

rule ".css" => "%{^#{DBG}/,#{SRC}/}X.sass" do |t|
  sass(t.prerequisites, t.name)
end

rule ".js" => "%{^#{DBG}/,#{SRC}/}X.coffee" do |t|
  coffee(t.prerequisites, t.name)
end

rule ".png" => "#{SRC}/image/svg/%{_\\d+x\\d+$,}n.svg" do |t|
  /_(\d+)x(\d+)\.png$/ =~ t.name
  sh "convert\
    -background transparent\
    -resize #{$1}x#{$2}\
    #{t.prerequisites} #{t.name}"
end

p_coffee = proc do |t|
  coffee(t.prerequisites.join(" "), t.name)
end

task :clean do
  sh "rm -r #{DBG}"
end

task :default => [
  DBG,
  "#{DBG}/manifest.json",
  "#{DBG}/lib",
  "#{DBG}/app.js",
  "#{DBG}/app_core.js",
  "#{DBG}/cs_addlink.js",
  "#{DBG}/cs_search.js",
  :img,
  :ui,
  :view,
  :zombie,
  :write,
  :test
]

directory DBG

file "#{DBG}/manifest.json" => "#{SRC}/manifest.json" do |t|
  sh "cp #{t.prerequisites} #{t.name}"
end

desc "ライブラリをコピー"
file "#{DBG}/lib" => FileList["#{SRC}/lib/**/*"] do |t|
  sh "rm -rf #{DBG}/lib"
  sh "cp -r #{SRC}/lib #{DBG}"
end

file "#{DBG}/app_core.js" => FileList["#{SRC}/core/*.coffee"], &p_coffee

file "#{DBG}/cs_search.js" => [
  "#{SRC}/app.coffee",
  "#{SRC}/core/url.coffee",
  "#{SRC}/cs_search.coffee"
], &p_coffee

#img
lambda {
  task :img => [
    "#{DBG}/img",
    "#{DBG}/img/read.crx_128x128.png",
    "#{DBG}/img/read.crx_48x48.png",
    "#{DBG}/img/read.crx_16x16.png",
    "#{DBG}/img/close_16x16.png",
    "#{DBG}/img/star_19x19.png",
    "#{DBG}/img/star2_19x19.png",
    "#{DBG}/img/link_19x19.png",
    "#{DBG}/img/search2_19x19.png",
    "#{DBG}/img/reload_19x19.png",
    "#{DBG}/img/pencil_19x19.png",
    "#{DBG}/img/arrow_19x19.png",
    "#{DBG}/img/dummy_1x1.png"
  ]

  directory "#{DBG}/img"

  file "#{DBG}/img/read.crx_128x128.png" => "#{SRC}/image/svg/read.crx.svg" do |t|
    sh "convert\
      -background transparent\
      -resize 96x96\
      -extent 128x128-16-16\
      #{SRC}/image/svg/read.crx.svg #{t.name}"

    sh "convert\
      -background transparent\
      -resize 90x90\
      -extent 128x128-50-92.5\
      #{SRC}/image/svg/alpha_badge.svg #{DBG}/img/tmp_alpha_badge.png"

    sh "convert\
      -background transparent\
      -composite #{DBG}/img/read.crx_128x128.png\
      #{DBG}/img/tmp_alpha_badge.png\
      #{DBG}/img/read.crx_128x128.png"

    sh "rm #{DBG}/img/tmp_alpha_badge.png"
  end
}.call()

#ui
lambda {
  task :ui => ["#{DBG}/ui.css", "#{DBG}/ui.js"]

  file "#{DBG}/ui.css" => FileList["#{SRC}/common.sass"].include("#{SRC}/ui/*.sass") do |t|
    sass("#{SRC}/ui/ui.sass", t.name)
  end

  file "#{DBG}/ui.js" => FileList["#{SRC}/ui/*.coffee"], &p_coffee
}.call()

#View
lambda {
  directory "#{DBG}/view"

  view = [
    "#{DBG}/view",
    "#{DBG}/view/app_proxy.js",
    "#{DBG}/view/module.js"
  ]

  FileList["#{SRC}/view/*.haml"].each {|x|
    tmp = x.sub(/^#{SRC}\//, "#{DBG}/").sub(/\.haml$/, "")
    view.push(tmp + ".html")
    view.push(tmp + ".js")
    view.push(tmp + ".css")
    sass_path = x.sub(/\.haml$/, ".sass")
    file tmp + ".css" => ["#{SRC}/common.sass", sass_path] do |t|
      sass(sass_path, t.name)
    end
  }

  task :view => view
}.call()

#Zombie
lambda {
  task :zombie => ["#{DBG}/zombie.html", "#{DBG}/zombie.js"]

  file "#{DBG}/zombie.js" => [
    "#{SRC}/core/url.coffee",
    "#{SRC}/core/cache.coffee",
    "#{SRC}/core/read_state.coffee",
    "#{SRC}/core/history.coffee",
    "#{SRC}/core/bookmark.coffee",
    "#{SRC}/zombie.coffee"
  ], &p_coffee
}.call()

#Write
lambda {
  task :write => [
    "#{DBG}/write",
    "#{DBG}/write/write.html",
    "#{DBG}/write/write.css",
    "#{DBG}/write/write.js",
    "#{DBG}/write/cs_write.js"
  ]

  directory "#{DBG}/write"

  file "#{DBG}/write/write.js" => [
    "#{SRC}/core/url.coffee",
    "#{SRC}/write/write.coffee"
  ], &p_coffee

  file "#{DBG}/write/cs_write.js" => [
    "#{SRC}/app.coffee",
    "#{SRC}/core/url.coffee",
    "#{SRC}/write/cs_write.coffee"
  ], &p_coffee
}.call()

#Test
lambda {
  task :test => [
    "#{DBG}/test",
    "#{DBG}/test/qunit",
    "#{DBG}/test/test.html",
    "#{DBG}/test/test.js"
  ]

  directory "#{DBG}/test"

  file "#{DBG}/test/qunit" => FileList["#{SRC}/test/qunit/**/*"] do
    sh "rm -rf #{DBG}/test/qunit"
    sh "cp -r #{SRC}/test/qunit #{DBG}/test"
  end

  file "#{DBG}/test/test.html" => "#{SRC}/test/test.html" do |t|
    sh "cp #{t.prerequisites} #{t.name}"
  end

  file "#{DBG}/test/test.js" => FileList["#{SRC}/test/test_*.js"] do |t|
    sh "cat #{t.prerequisites.join(" ")} > #{t.name}"
  end
}.call()