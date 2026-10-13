extends Node

# ---------------------------------------------------------------------------
# In-play HUD, laid out in HUD.tscn (instanced by Game.tscn) -- open that
# scene to see and edit it. This script only hands the scene its art and its
# buttons' targets (setup) and pushes the current numbers into it (update_stats).
#
# The solve screen -- the summary panel (EarningsPanel.tscn) with the Next Level /
# Continue button or waiting label stacked under it -- is a centered container in
# FrontRoot, so it stays centered on any window size with no code.
#
# Two CanvasLayers, deliberately:
#   BackLayer  (layer -1) -- the background and the icon row. These sit *under*
#              everything Game draws (board, entities, minimap) so the tutorial
#              hints, "+30s" popups and win confetti, which Game draws last,
#              still land on top of the HUD like they always have.
#   FrontLayer (layer  1) -- hamburger, combat status text and the solve /
#              defeat buttons: real controls that must sit above the board.
#
# Icon art comes from the textures AssetLoader already loads onto Game
# (icon_timer.png, icon_health.png, icon_weapon.png, icon_shield.png,
# icon_gold.png, background.png in res://assets/). Without a file, that icon
# is just its colored circle.
# ---------------------------------------------------------------------------

@onready var background_art: TextureRect = %BackgroundArt
@onready var timer_fill: ColorRect = %TimerFill
@onready var timer_label: Label = %TimerLabel
@onready var timer_texture: TextureRect = %TimerTexture
@onready var health_fill: ColorRect = %HealthFill
@onready var health_label: Label = %HealthLabel
@onready var health_texture: TextureRect = %HealthTexture
@onready var weapon_texture: TextureRect = %WeaponTexture
@onready var shield_texture: TextureRect = %ShieldTexture
@onready var gold_stat: Control = %GoldStat
@onready var gold_texture: TextureRect = %GoldTexture
@onready var gold_label: Label = %GoldLabel

@onready var hamburger_button: Button = %HamburgerButton
@onready var combat_status_label: Label = %CombatStatusLabel
@onready var next_level_button: Button = %NextLevelButton
@onready var continue_button: Button = %ContinueButton
@onready var continue_waiting_label: Label = %ContinueWaitingLabel
@onready var try_again_button: Button = %TryAgainButton
@onready var earnings_panel: Control = %EarningsPanel  # the post-level summary (EarningsPanel.tscn)

var game: Node2D

# Called once from GameUIManager._build_ui(). show_admin_buttons is true for
# singleplayer and the multiplayer host -- the only peers that can reset a
# board or generate the next one.
func setup(game_ref: Node2D, show_admin_buttons: bool) -> void:
	game = game_ref

	background_art.texture = game.background_texture
	background_art.visible = game.background_texture != null
	timer_texture.texture = game.icon_timer_texture
	health_texture.texture = game.icon_health_texture
	weapon_texture.texture = game.icon_weapon_texture
	shield_texture.texture = game.icon_shield_texture
	gold_texture.texture = game.icon_gold_texture
	gold_stat.visible = CampaignManager.is_campaign_active  # nothing earns gold outside the campaign

	hamburger_button.pressed.connect(game.pause_mgr._toggle_pause_menu)
	game.combat_status_label = combat_status_label
	game.earnings_panel = earnings_panel

	# Keep only the buttons this session can use; the rest are freed and the
	# matching Game field stays null, which is what the rest of the code
	# checks for ("if game.next_level_button != null", ...).
	var is_campaign: bool = CampaignManager.is_campaign_active
	game.try_again_button = _keep_if(try_again_button, show_admin_buttons)
	game.next_level_button = _keep_if(next_level_button, show_admin_buttons and is_campaign)
	game.continue_button = _keep_if(continue_button, show_admin_buttons and not is_campaign)
	game.continue_waiting_label = _keep_if(continue_waiting_label, not show_admin_buttons and not is_campaign)

	# The buttons the HUD shows on its own (Try Again, and the one under the
	# summary panel) get the green pixel-art look (see PixelButton); if
	# assets/buttons.png is missing they just keep the default button style.
	if game.try_again_button != null:
		try_again_button.pressed.connect(game._on_reset_pressed)
		PixelButton.apply(try_again_button)
	if game.next_level_button != null:
		next_level_button.pressed.connect(game._on_next_level_pressed)
		PixelButton.apply(next_level_button)
	if game.continue_button != null:
		continue_button.pressed.connect(game._on_continue_pressed)
		PixelButton.apply(continue_button)

	update_stats()

func _keep_if(node: Control, keep: bool) -> Control:
	if keep:
		return node
	node.queue_free()
	return null

# Called every frame from Game._process().
func update_stats() -> void:
	if game.my_player_index < 0 or game.my_player_index >= game.players.size():
		return

	var time_limit: float = game.current_level_time_limit
	var remaining: float = max(0.0, time_limit - game.level_timer)
	# The bar's fraction is remaining / current limit; a clue bonus raises both,
	# so the bar visibly nudges forward when you earn one (see PuzzleBoard).
	timer_fill.anchor_right = clamp(remaining / max(0.001, time_limit), 0.0, 1.0)
	timer_label.text = game.hud_mgr._format_timer(remaining)

	var health: int = game.players[game.my_player_index]["health"]
	health_fill.anchor_right = clamp(float(health) / float(max(1, game.COMBAT_MAX_HEALTH)), 0.0, 1.0)
	health_label.text = "%d/%d" % [health, game.COMBAT_MAX_HEALTH]

	if gold_stat.visible:
		gold_label.text = str(CampaignManager.gold)
