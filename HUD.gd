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
# The icon art (hourglass, heart, staff, hat, gold) is assigned directly on
# the nodes in HUD.tscn, and the background is just the Background ColorRect.
# ---------------------------------------------------------------------------

@onready var timer_fill: ColorRect = %TimerFill
@onready var timer_label: Label = %TimerLabel
@onready var health_fill: ColorRect = %HealthFill
@onready var health_label: Label = %HealthLabel
@onready var gold_stat: Control = %GoldStat
@onready var gold_label: Label = %GoldLabel

@onready var hamburger_button: Button = %HamburgerButton
@onready var combat_status_label: Label = %CombatStatusLabel
@onready var next_level_button: Button = %NextLevelButton
@onready var continue_button: Button = %ContinueButton
@onready var continue_waiting_label: Label = %ContinueWaitingLabel
@onready var shop_button: Button = %ShopButton
@onready var try_again_button: Button = %TryAgainButton
@onready var earnings_panel: Control = %EarningsPanel  # the post-level summary (EarningsPanel.tscn)

var game: Node2D

# Called once from GameUIManager._build_ui(). show_admin_buttons is true for
# singleplayer and the multiplayer host -- the only peers that can reset a
# board or generate the next one.
func setup(game_ref: Node2D, show_admin_buttons: bool) -> void:
	game = game_ref

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
	game.shop_button = _keep_if(shop_button, not is_campaign)  # everyone can shop, host or not

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
	if game.shop_button != null:
		shop_button.pressed.connect(game.shop_mgr.open_shop)
		PixelButton.apply(shop_button)

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

	gold_label.text = str(_current_gold())

# The local player's gold: the campaign's single wallet, or -- in Endless and
# multiplayer -- this player's own entry in Game.player_gold.
func _current_gold() -> int:
	if CampaignManager.is_campaign_active:
		return CampaignManager.gold
	if game.my_player_index < 0 or game.my_player_index >= game.player_gold.size():
		return 0
	return game.player_gold[game.my_player_index]
