module FilmscanGUI
  # Every setting the toolkit's command line takes, grouped and ordered as
  # --help has them, with a range for its slider and what changing it costs.
  #
  # Costs follow from how the toolkit caches a roll's analysis. The tuning
  # renders frames through the whole pipeline, so the cache key holds nearly
  # every setting. Strengths applied after the stored fits load are live; a
  # setting that changes what is measured needs a re-measure before a preview
  # means anything; everything else previews at once from the old analysis,
  # approximately.
  module Schema
    Setting = Struct.new(:key, :label, :group, :kind, :min, :max, :step, :digits, :tier, :common,
                         :frame, :help, keyword_init: true) do
      def flag = "--#{key.to_s.tr('_', '-')}"
      def live? = tier == :live
    end

    GROUPS = ["Colour", "Tone", "Grain", "Beyond the film", "Output"].freeze

    def self.setting(key, label, group, kind = :float, min: 0.0, max: 1.0, step: 0.01, digits: 2, tier: :approx,
                     common: false, frame: true, help: nil)
      Setting.new(key: key, label: label, group: group, kind: kind, min: min, max: max, step: step, digits: digits,
                  tier: tier, common: common, frame: frame, help: help)
    end

    # frame: false marks settings the toolkit applies once for the whole
    # roll, so a per-frame override of them would be ignored.
    SETTINGS = [
      setting(:match_strength, "Match strength", "Colour", tier: :live, common: true, frame: false,
              help: "How much of the matched rolls' look to carry over."),
      setting(:look_strength, "Film look", "Colour", tier: :live, common: true, frame: false,
              help: "How much of the film's own look, from its profile, to carry over when the roll matches no siblings."),
      setting(:frame_balance, "Frame balance", "Colour", common: true,
              help: "Strength of each frame's own balance toward the reference, after the roll's."),
      setting(:lamp_guard, "Lamp guard", "Colour", common: true,
              help: "How much of a lamp lit frame's warmth the frame balance leaves."),
      setting(:keep_warmth, "Keep warmth", "Colour", common: true,
              help: "Share of the frame balance's warm to cool move to leave out, for golden hour."),
      setting(:roll_balance, "Roll balance", "Colour", common: true,
              help: "Strength of the balance toward the reference."),
      setting(:roll_tone, "Roll tone", "Colour", tier: :live, common: true, frame: false,
              help: "Strength of the roll's tone curve toward the reference's tones."),
      setting(:target_saturation, "Target saturation", "Colour", max: 0.8, common: true,
              help: "Boost each frame toward this mean saturation."),
      setting(:saturation, "Fixed vibrance", "Colour", :optional, max: 3.0,
              help: "Fixed vibrance for every frame in place of a target. Off uses the target."),
      setting(:max_vibrance, "Max vibrance", "Colour", min: 1.0, max: 4.0, help: "Ceiling on the vibrance boost."),
      setting(:knee, "Knee", "Colour", max: 0.6, help: "Chroma at which the boost halves. Lower protects colourful subjects."),
      setting(:roll_balance_limit, "Roll balance limit", "Colour", max: 3.0, step: 0.05, tier: :remeasure, frame: false,
              help: "How far a roll may drift from its film's measured cast, in stops."),
      setting(:frame_balance_limit, "Frame balance limit", "Colour", max: 4.0, step: 0.05,
              help: "How far the frame balance may move a frame, in stops."),
      setting(:roll_fit, "Roll fit", "Colour", tier: :live, frame: false, help: "Strength of the whole-roll colour fit."),
      setting(:wb, "White balance", "Colour", help: "Per-frame white balance strength. 0 disables it."),
      setting(:wb_clamp, "WB clamp", "Colour", min: 1.0, max: 3.0, help: "Cap on any single channel gain."),
      setting(:shadow_wb, "Shadow balance", "Colour", help: "Strength of the separate shadow balance."),
      setting(:neutral, "Grey world", "Colour", help: "Grey-world share. Usually best left at 0."),

      setting(:contrast, "Contrast", "Tone", max: 0.4, step: 0.005, digits: 3, common: true, help: "S-curve amount."),
      setting(:black, "Black", "Tone", max: 5.0, step: 0.05, common: true, help: "Black clip percentile."),
      setting(:white, "White", "Tone", min: 95.0, max: 100.0, step: 0.05, common: true, help: "White clip percentile."),
      setting(:max_stretch, "Max stretch", "Tone", min: 1.0, max: 6.0, step: 0.05, common: true,
              help: "Most a frame's range may be stretched."),

      setting(:chroma, "Chroma", "Grain", common: true, help: "Colour noise reduction. Luma grain is left alone."),
      setting(:chroma_radius, "Chroma radius", "Grain", :optional_int, max: 64, step: 1, digits: 0, common: true,
              help: "Colour blur radius in pixels. Off scales with image width."),

      setting(:fix, "Fixes", "Beyond the film", :fixes, tier: :remeasure, common: true, frame: false,
              help: "Corrections about the camera, the scanner or the frame."),
      setting(:crop, "Crop borders", "Beyond the film", :bool, tier: :live, common: true, frame: false,
              help: "Take off the film borders and the scanner's overscan."),
      setting(:recovery, "Recovery", "Beyond the film", common: true, help: "Strength of the shadow and highlight recovery."),
      setting(:sky_floor, "Sky floor", "Beyond the film", max: 2.0, common: true,
              help: "How far a sky that came out warm may be brought back toward neutral, in stops."),
      setting(:sharpness, "Sharpness", "Beyond the film", common: true, help: "Strength of the sharpening."),
      setting(:flat_field, "Flat field", "Beyond the film", tier: :live, frame: false,
              help: "Strength of the lift in the corners. Needs the flat fix."),
      setting(:sky_headroom, "Sky headroom", "Beyond the film", max: 3.0, help: "Highlight headroom for frames with a sky, in stops."),
      setting(:sky_neutral, "Sky out of neutral", "Beyond the film", :bool, tier: :remeasure, frame: false,
              help: "Keep a detected sky out of the frame's neutral estimate."),
      setting(:highlight_headroom, "Highlight headroom", "Beyond the film", max: 3.0,
              help: "How far a pixel may be darkened when a gain would take it past white, in stops."),
      setting(:lost_colour, "Lost colour", "Beyond the film", help: "Ease toward grey where a channel has nothing left to say."),
      setting(:chroma_shape, "Chroma shape", "Beyond the film", help: "Bend the film's colour onto the reference's shape."),

      setting(:format, "Format", "Output", :choice, tier: :live, common: true, frame: false),
      setting(:bits, "Bits", "Output", :choice, tier: :live, common: true, frame: false),
      setting(:quality, "Quality", "Output", :int, min: 50, max: 100, step: 1, digits: 0, tier: :live, common: true, frame: false)
    ].freeze

    BY_KEY = SETTINGS.to_h { |s| [s.key, s] }.freeze
    FORMATS = %w[heic tiff jpeg png jp2].freeze

    module_function

    def [](key) = BY_KEY.fetch(key.to_sym)
    def in_group(group) = SETTINGS.select { |s| s.group == group }

    # What a change to these settings costs, the worst of them.
    def tier_of(keys)
      tiers = keys.map { |key| BY_KEY[key.to_sym]&.tier || :remeasure }
      %i[remeasure approx live].find { |tier| tiers.include?(tier) } || :live
    end
  end
end
