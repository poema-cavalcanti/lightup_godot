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

# Scenes reached with get_tree().change_scene_to_file(). Cutscene -> Game ->
# Town -> Cutscene is the campaign loop; MainMenu fans out to the rest.
const SCENE_MAIN_MENU: String = "res://MainMenu.tscn"
const SCENE_GAME: String = "res://Game.tscn"
const SCENE_CUTSCENE: String = "res://Cutscene.tscn"
const SCENE_TOWN: String = "res://Town.tscn"
const SCENE_LOBBY: String = "res://Lobby.tscn"
const SCENE_SETTINGS: String = "res://Settings.tscn"
const SCENE_HOW_TO_PLAY: String = "res://HowToPlay.tscn"
const SCENE_STATS: String = "res://Stats.tscn"

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

const TITLE_BAR_HEIGHT: float = 36.0  # the green bar, in both pieces of art

# Text colors that read well on the cream parchment / green bar.
const TEXT_COLOR: Color = Color(0.24, 0.13, 0.10)
const TITLE_TEXT_COLOR: Color = Color(0.10, 0.16, 0.16)
const GOLD_TEXT_COLOR: Color = Color(0.62, 0.38, 0.05)

# Palette sampled from the art, used for the no-image fallback.
const BORDER_COLOR: Color = Color(96.0 / 255.0, 57.0 / 255.0, 40.0 / 255.0)
const PARCHMENT_COLOR: Color = Color(229.0 / 255.0, 214.0 / 255.0, 161.0 / 255.0)
const TITLE_BAR_COLOR: Color = Color(80.0 / 255.0, 169.0 / 255.0, 120.0 / 255.0)

# --- Puzzle grid ---------------------------------------------------------
const CELL_SIZE: int = 64
const CELL_WHITE: int = 0
const CELL_BLACK: int = 1
enum CellType { WHITE, BLACK }

# The four edge-adjacent neighbors of a cell, as [row_delta, col_delta].
const GRID_NEIGHBOR_OFFSETS: Array = [[-1, 0], [1, 0], [0, -1], [0, 1]]

# --- Shared gameplay tuning ------------------------------------------------
# Used by both the in-level player (Player.gd) and the Town walker (Town.gd),
# which are kept visually identical on purpose.
const MOVE_ANIMATION_DURATION: float = 0.15  # one grid hop; also the hold-to-move repeat interval
const GENERATOR_DENSITY: float = 0.22  # black-cell density for generated puzzles (Endless, multiplayer)
const ATTACK_FLASH_DURATION: float = 0.25  # swing/hit flash for players and enemies; enemy attack animations are stretched to match it

# P1..P4 colors (Player.gd draws everyone with these; Town.gd's walker is always P1).
const PLAYER_COLORS: Array[Color] = [
	Color(0.15, 0.65, 0.95),  # P1 blue
	Color(0.90, 0.25, 0.55),  # P2 pink
	Color(0.25, 0.80, 0.35),  # P3 green
	Color(0.95, 0.60, 0.10),  # P4 orange
]
const PLAYER_OFFSETS: Array[Vector2] = [
	Vector2(-6, -6), Vector2(6, -6), Vector2(-6, 6), Vector2(6, 6),
]

# --- Player sprite sheets (Player.gd in levels, Town.gd in town) -------------
const PLAYER_SHEET_FRAME_WIDTH: int = 32
const PLAYER_SHEET_FRAME_HEIGHT: int = 32
const PLAYER_SHEET_DIRECTION_ROWS: Dictionary = {
	"down": 0, "right": 2, "up": 4,
	# "left" isn't a row of its own -- the sheet only has one side view
	# (row 2, "right"); facing left reuses that same row and gets flipped
	# horizontally at draw time instead.
}
const PLAYER_ANIMATION_FRAME_DURATION: float = 0.12  # walk cycle
const PLAYER_IDLE_FRAME_DURATION: float = 0.25  # slower, restful pace for standing still

const PLAYER_SHEET_FRAME_COUNT: int = 4
const PLAYER_IDLE_SHEET_FRAME_COUNT: int = 4
const PLAYER_RUN_SHEET_FRAME_COUNT: int = 6
const PLAYER_INTERACT_SHEET_FRAME_COUNT: int = 4
const PLAYER_ATTACK_SHEET_FRAME_COUNT: int = 7

# Equipped-armor overlay placement. How many *source* pixels above the body
# frame's own top edge the overlay art's (0, 0) pixel lands depends on which
# body sheet is showing, since each sheet poses the head at a slightly
# different height. Attack is 0 for when its own art exists; for now it
# borrows run's art (see ItemData's OVERLAY_ART_FALLBACK) but keeps this 0.
# Body frame counts are here so an overlay strip with a different count
# (attack's 7 body frames vs run's 6 hat frames) can be mapped proportionally
# instead of running off its end. Town only ever uses walk/idle/run.
const OVERLAY_TOP_OFFSET_PIXELS: Dictionary = {"walk": 1, "idle": 2, "interact": 0, "run": 2, "attack": 0}
const OVERLAY_BODY_FRAME_COUNTS: Dictionary = {"walk": 4, "idle": 4, "interact": 4, "run": 6, "attack": 7}
