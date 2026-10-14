extends RefCounted
# UI logic: window sizing/centering, layout on resize/fullscreen, and the
# status label + win/lose button visibility (the not-solved -> solved
# transition itself, which hands off to HUDManager for the actual win
# animation). Split out of Game.gd -- operates on shared board/combat state
# via the `game` back-reference.
#
# The in-play HUD's fixed controls -- background, icon row, hamburger, combat
# text, and the "solve screen" (the post-level summary panel with the Next
# Level / Continue button under it, centered by a container) plus Try Again --
# are laid out in HUD.tscn and EarningsPanel.tscn, driven by HUD.gd and
# EarningsPanel.gd. What's still drawn in code -- minimap, error flash, timer
# popups, tutorial hints, win animation, level-timer tick -- lives in
# HUDManager.gd; the pause menu lives in PauseMenuManager.gd (laid out in
# PauseMenu.tscn).

var game: Node2D

func _init(game_ref: Node2D) -> void:
	game = game_ref

const MIN_PLAY_COLS: int = 8   # smallest play-area window the initial window size guarantees
const MIN_PLAY_ROWS: int = 6

func _build_ui() -> void:
	# A placeholder: _update_status() and the check/advance code write this
	# label's text and color from the moment the level starts, but its real home
	# -- a label in PauseMenu.tscn -- only exists once the pause menu is first
	# opened. PauseMenuManager._setup_main_view() hands what it holds over to
	# the scene's own label at that point.
	game.status_label = Label.new()

	# Everything else is in HUD.tscn: the hamburger, combat status text, the
	# icon row, the post-solve summary panel with its Next Level / Continue
	# button (or waiting label), and Try Again. This just tells it which of
	# those buttons apply to this session -- every mode gets the summary panel;
	# the button under it is Next Level in the campaign, Continue in Endless /
	# for the multiplayer host, and a waiting label for clients.
	#
	# Reset / Check Answer / New Puzzle / Next Level mutate the shared board
	# (or just reveal a centered prompt), so they live in the pause menu rather
	# than a bottom bar sitting over the scrollable play area -- see
	# PauseMenuManager._setup_main_view(). Reset is host-only in multiplayer;
	# Check Answer is available to everyone.
	var show_admin_buttons: bool = (not NetworkManager.is_multiplayer) or game.multiplayer.is_server()
	game.hud.setup(game, show_admin_buttons)

	# The shop window for Endless / multiplayer (the campaign shops in Town.tscn instead).
	if not CampaignManager.is_campaign_active:
		game.shop_mgr.build_panel()

	# Inventory/equipment overlay -- its own top-level CanvasLayer rather than
	# part of the HUD: it's meant to work the same way in Town.tscn too (see
	# Town.tscn), and it doesn't pause anything (see InventoryPanel.gd) --
	# enemies and the level timer keep going while it's open, only player
	# input is held off, in Game._input(). In the campaign it reads the
	# CampaignManager globals; in Endless / multiplayer it's pointed at the
	# local player's own items and equipment (LoadoutManager.gd).
	game.inventory_panel = preload("res://InventoryPanel.tscn").instantiate()
	game.inventory_panel.can_open = game.loadout_mgr.can_open_inventory  # not while defeated or shopping
	if not CampaignManager.is_campaign_active:
		game.inventory_panel.get_inventory = game.loadout_mgr.my_inventory
		game.inventory_panel.get_equipped = game.loadout_mgr.my_equipped_item_id
		game.inventory_panel.do_equip = game.loadout_mgr.equip
		game.inventory_panel.do_unequip = game.loadout_mgr.unequip
	game.add_child(game.inventory_panel)

func _resize_window() -> void:
	# Sets the OS window to fit a sensible minimum play area, then lays
	# everything out. The play area itself always stretches to fill
	# whatever window/viewport size results (see HUDManager._compute_view_window),
	# scrolling for puzzles bigger than the visible window -- so unlike
	# before, this no longer sizes the window to the puzzle's own
	# dimensions. Only call this when the window SIZE itself needs to
	# change (initial load). For reacting to a size that already changed
	# (user drag, fullscreen, monitor change), call _update_layout()
	# directly instead -- it must never re-request a size, or it fights
	# the very resize it is reacting to.
	var content_width: int = game.MARGIN * 2 + MIN_PLAY_COLS * Constants.CELL_SIZE
	var content_height: int = game.HUD_HEIGHT + game.MARGIN * 2 + MIN_PLAY_ROWS * Constants.CELL_SIZE
	SettingsManager.apply_window_size(content_width, content_height)
	_update_layout()

func _update_layout() -> void:
	# Reacts to a window size that already changed (user drag, fullscreen,
	# monitor change); never re-requests a size, which would fight the very
	# resize it's reacting to. The solve screen centers itself (it's a
	# container in HUD.tscn), and the board's own offset/scroll is recomputed
	# fresh every _draw() call (see HUDManager._compute_view_window), so all
	# that's left is a redraw.
	game.queue_redraw()

# The one control sitting under the summary panel on the solve screen: Next
# Level (campaign), Continue (Endless / multiplayer host), or -- for
# multiplayer clients, who can't advance -- the "waiting for host" label.
func _solve_action_control() -> Control:
	if game.next_level_button != null:
		return game.next_level_button
	if game.continue_button != null:
		return game.continue_button
	return game.continue_waiting_label

# ---------------------------------------------------------------------------
# Status label + win/lose button visibility -- watches the board/combat
# state every time it changes (called from PuzzleBoard.recompute_state) and
# reacts to the not-solved -> solved transition. The actual celebration
# (confetti + banner) is HUDManager._play_win_animation(); this just
# detects the moment and hands off to it.
# ---------------------------------------------------------------------------

func _update_status() -> void:
	var lit_count: int = 0
	var white_count: int = 0
	for row in range(game.rows):
		for col in range(game.cols):
			if game.grid[row][col]["type"] == Constants.CellType.WHITE:
				white_count += 1
				if game.lit[row][col]:
					lit_count += 1

	var solved_now: bool = game.puzzle_mgr._is_solved()

	if solved_now:
		game.status_label.text = "Solved! All cells lit, no conflicts, all clues satisfied."
		game.status_label.add_theme_color_override("font_color", Constants.STATUS_SUCCESS_ON_PARCHMENT)
	else:
		var status_message: String = "%d / %d white cells lit." % [lit_count, white_count]
		if not game.conflicting_bulbs.is_empty():
			status_message += " Some bulbs are lighting each other (red)."
		game.status_label.text = status_message
		game.status_label.add_theme_color_override("font_color", Constants.STATUS_NEUTRAL_ON_PARCHMENT)

	# Every mode gets the same solve screen: the summary panel plus a button
	# (Next Level / Continue) that's the only way forward -- nothing advances
	# on its own. Multiplayer clients just see a waiting message instead.
	var action_control: Control = _solve_action_control()
	if action_control != null:
		action_control.visible = solved_now
	if game.shop_button != null:
		game.shop_button.visible = solved_now
	if not solved_now:
		game.shop_mgr.close_shop()  # the board was un-solved under an open shop
	if game.earnings_panel != null:
		game.earnings_panel.visible = solved_now

	# Puzzle complete: give that moment a clean screen of its own -- hide
	# everything else so the centered summary and its button are the
	# only things showing.
	if game.earnings_panel != null:
		if game.status_label != null:
			game.status_label.visible = not solved_now
		if game.combat_status_label != null:
			game.combat_status_label.visible = not solved_now
		if game.reset_button != null:
			game.reset_button.visible = not solved_now
		if game.check_button != null:
			game.check_button.visible = not solved_now

	if solved_now and not game.was_solved:
		game.hud_mgr._play_win_animation()
		# Earnings are paid once per board. Picking a bulb back up and re-placing it
		# un-solves and re-solves the board, which would otherwise pay out again
		# (game.earnings_credited is re-armed only when a new puzzle loads).
		if CampaignManager.is_campaign_active:
			if not game.earnings_credited:
				game.earnings_credited = true
				var remaining_seconds: float = max(0.0, game.current_level_time_limit - game.level_timer)
				game.level_earnings = CampaignManager.credit_level_earnings(remaining_seconds, game.boss_killed_this_level, game.enemies_killed_this_level)
			game.earnings_panel.populate(game.level_earnings)
		elif (not NetworkManager.is_multiplayer or game.multiplayer.is_server()) and not game.earnings_credited:
			game.earnings_credited = true
			var solve_remaining: float = max(0.0, game.current_level_time_limit - game.level_timer)
			var solve_breakdown: Dictionary = CampaignManager.calculate_level_earnings(solve_remaining, game.boss_killed_this_level, game.enemies_killed_this_level)
			if NetworkManager.is_multiplayer:
				game.rpc("_show_solve_summary", solve_breakdown)
			else:
				game._show_solve_summary(solve_breakdown)
		game.enemies.clear()  # solving the puzzle clears the board of any game.enemies
	game.was_solved = solved_now
