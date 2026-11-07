# Filmscan-GUI

Filmscan-GUI is a desktop app for reviewing and correcting lab scans of film.
It runs Filmscan-CLI from a pinned submodule and uses Ruby and wxRuby3 for
the desktop interface.

## Features

Browse rolls and try a film profile or a setting on a single frame or a
contact sheet. Match colour and tone to a roll shot in similar light. Use the
render queue to produce trial or final copies and compare a trial with the
previous result.

The desktop app stores per-frame overrides and matching references in the
toolkit's YAML formats. It supports a folder per roll and libraries grouped
by trip. [Filmscan-CLI](https://github.com/sparkdotdev/Filmscan-CLI)

## Build and run

You need Ruby 4.0 and libvips (`brew install vips` on macOS).
Clone with the pinned toolkit submodule:

```sh
git clone --recurse-submodules https://github.com/sparkdotdev/Filmscan-GUI.git
cd Filmscan-GUI
```

wxRuby3 publishes packages for macOS 14, 15 and 26. On a newer macOS, name
the macOS 26 package before installing:

```sh
bundle config set --local build.wxruby3 "package=https://github.com/mcorino/wxRuby3/releases/download/v1.8.1/wxruby3_macosx_26_ruby40-1.8.1-arm64-darwin.pkg"
```

Then run `bundle install`. If you cloned without submodules, first run
`git submodule update --init --recursive`. The toolkit lives in `toolkit/`;
set `FILMSCAN_PATH` to use another checkout during development.

On macOS, `bundle exec rake toolkit:build` builds the optional Metal and
hardware encoder helpers with Xcode's command line tools.

```sh
bundle exec bin/filmscan-gui
```

On a Mac, `bundle exec rake app` makes `~/Applications/Filmscan-GUI.app`, which
runs this checkout with its own name and icon in the Dock.

## Configuration

The first time, the app asks for the folder that holds your scans and how
rolls are laid out in it. Two layouts come ready:

- Beside each roll: rolls anywhere under the folder, renders written next to
  each roll as the toolkit does by default.
- Trip folders: each trip holds an `Original TIFFs` folder of rolls, with
  renders in `Corrected HEICs` and trial renders in `Matched HEICs`.

Every path is a template you can change in Settings, using `{trip}`,
`{path}`, `{roll}`, `{id}`, `{source}`, `{date}` and `{workspace}`.

## How it works

Each open roll gets a worker process that keeps the roll's analysis and a
1500px copy of every frame, and renders previews through the toolkit's own
pipeline. The window never computes pixels, so it stays responsive while a
frame renders.

A slider's marker says what moving it costs. Filled is exact at once. Half
filled is shown at once from the roll's last measurement and becomes exact
after a re-measure. A ring needs the roll measured again first.

Renders run the toolkit's command line from a queue, with the same arguments
you would type, so the files you keep are exactly what the command line
makes. "Copy command line" in the Edit menu gives that command.

Your choices are kept as the toolkit's own files: per-frame settings in the
overrides YAML that `--overrides` reads, and siblings in `sessions.yml`.
Edits keep the comments in both. Verdicts, the queue and the app's own
settings live in the workspace folder.

## Keys

| Key | Does |
| --- | --- |
| Up, Down, Left, Right | Previous or next frame |
| Space (hold) | Show the previous settings |
| Cmd 1, 2, 3 | Frame, contact sheet, review |
| Cmd Alt 1 to 6 | Split, side by side, lab scan, corrected, now, sibling |
| Cmd 0, Cmd = | Fit, actual size |
| Cmd R | Re-measure the roll |
| Cmd K | Check the frame at full size |
| Cmd M | Match siblings |
| Cmd T, Shift Cmd T | Trial render, final render |
| 1, 2, 3 in review | Better, worse, too close to call |
| Cmd J, Cmd L | Render queue, library |

## Tests

```sh
bundle exec rake
```

`tools/snapshots.rb` walks through the app on a library and saves what each
window shows, for checking the look without anyone at the screen.

## Licence

PolyForm Strict 1.0.0 with the Spark Film Software Addendum 1.1.0 covers
non-commercial use of the unmodified software. Commercial and business use
requires separate written permission from Spark Software Development, LLC.
[Full licence and addendum](LICENSE.MD#spark-film-software-addendum-110)

## Forking and contributions

The Spark Contribution Agreement gives contributors and reviewers limited
permission to copy, modify and test the software for a contribution. Read and
accept it before submitting a change. Contributors retain ownership and grant
Spark the right to use and commercially relicense submissions, including under
proprietary terms, even if a submission is declined or withdrawn.
[Contribution policy and agreement](CONTRIBUTING.md)
