source "https://rubygems.org"

gemspec

gem "film_scan", path: ENV.fetch("FILMSCAN_PATH", "toolkit")

group :development do
  # Minitest 6 pulls in prism, which a vendored bundle would build from source.
  gem "minitest", "~> 5.27"
  gem "rake", "~> 13.0"
end
