class_name Constants
extends RefCounted

# ---------------------------------------------------------------------------
# Shared literal values that were previously copy-pasted across every
# standalone menu-style scene (Main Menu, Settings, How to Play, Stats,
# Lobby, Cutscene) -- window sizing above all, which is also why every one
# of those scenes ended up the same size in the first place. See also
# MenuScreen.gd, which builds on these for the boilerplate itself (window
# sizing, F11 toggle, Back behavior), not just the raw numbers.
#
# A plain class_name/RefCounted holder rather than an autoload, same as
# CampaignData -- nothing here needs per-instance state, so every value is
# reached directly as Constants.SOMETHING with no Constants.new() anywhere.
# ---------------------------------------------------------------------------

const DEFAULT_WINDOW_WIDTH: int = 1280
const DEFAULT_WINDOW_HEIGHT: int = 720

# For status_label.add_theme_color_override("font_color", ...) -- collapses
# what used to be several slightly-inconsistent one-off Color(...) literals
# (e.g. two different grays for the same "neutral" meaning) into one set.
const STATUS_SUCCESS_COLOR: Color = Color(0.2, 0.7, 0.2)
const STATUS_ERROR_COLOR: Color = Color(0.85, 0.3, 0.3)
const STATUS_WARNING_COLOR: Color = Color(0.85, 0.6, 0.2)
const STATUS_NEUTRAL_COLOR: Color = Color(0.85, 0.85, 0.85)

# The same meanings, darkened to stay readable on cream parchment -- the status
# text ("N / M white cells lit", "Correct!", ...) now lives in the pause menu's
# parchment panel, where the light colors above would wash out.
const STATUS_SUCCESS_ON_PARCHMENT: Color = Color(0.08, 0.42, 0.14)
const STATUS_ERROR_ON_PARCHMENT: Color = Color(0.68, 0.12, 0.12)
const STATUS_NEUTRAL_ON_PARCHMENT: Color = Color(0.24, 0.13, 0.10)  # the parchment panels' dark brown text color
