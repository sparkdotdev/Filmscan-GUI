require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

desc "Build Filmscan-GUI.app around this checkout (default ~/Applications/Filmscan-GUI.app)"
task :app, [:path] do |_, args|
  ruby "tools/make_app.rb", *[args[:path]].compact
end

namespace :toolkit do
  desc "Build the toolkit's optional macOS helpers"
  task :build do
    Dir.chdir(File.join(__dir__, "toolkit")) do
      sh({ "BUNDLE_GEMFILE" => File.join(__dir__, "Gemfile") },
         "bundle", "exec", "rake", "apple_engine", "apple_heic")
    end
  end
end
