extends CanvasLayer

# ---------------------------------------------------------------------------
# INVENTORY / EQUIPMENT PANEL
#
# A drop-in overlay usable from any scene: instance InventoryPanel.tscn and
# add it as a child (see GameUIManager._build_ui() and Town.gd/_ready()) --
# it needs no back-reference to either, since everything it reads and
# writes (owned items, what's equipped) lives on the CampaignManager
# autoload -- unless a host swaps in its own data source (see get_inventory
# and friends below; Game does that for Endless / multiplayer).
#
# Toggled by its own 'I' key listener below, so nothing else needs to wire
# that up; host scenes only need to check is_open() to know whether to
# hold off on their own movement/attack/block input while it's up (see
# Game._input() and Town._input()/_tick_move_repeat()). A host can also set
# can_open (below) to veto opening -- Game uses that to keep it shut while
# the local player is defeated.
#
# Deliberately does NOT pause anything -- opening this never sets
# pause_menu_open or otherwise halts a level's _process()/combat, so
# enemies and the level timer keep going while the player browses their
# inventory. That's intentional per how it was asked for (browsing at a
# bad moment should carry some risk), not an oversight. It's also why the
# controls below are single-click: no select-then-confirm step.
#
# LAYOUT: everything fixed lives in the scenes, so it can be moved and
# restyled in the editor:
#   InventoryPanel.tscn -- the window (art, title, gold count, X, the two slot
#                          boxes, the scrolling item grid, the hint) over a dimmed backdrop
#   InventorySlot.tscn  -- one equipment box (icon, click area)
#   InventoryTile.tscn  -- one item in the grid (icon, badges, gold border)
# This script only fills them in: it adds a tile per owned item and keeps the
# slots/tiles in step with what's equipped. The art (referenced directly by the
# scene), the slot boxes and the grid area are positioned for
# assets/inventory_background.png (640x448): its left wing has two
# silhouette boxes -- the top one is the "armor" slot (hats), the bottom one
# the "weapon" slot (staffs), so an equipped item's icon is drawn on top of
# the silhouette to look worn/held. If the art is redrawn, move ArmorSlot,
# WeaponSlot and ItemScroll in InventoryPanel.tscn to match.
#
# CONTROLS (all single-click, no focus):
#   - click an item tile  -> equip it into its slot (replacing what's there);
#                            click an already-equipped tile -> unequip it
#   - click a slot box    -> unequip whatever's in it
# Tooltips (built-in Control.tooltip_text) carry the names/descriptions and
# say what a click will do, so there are no text labels cluttering the art.
# Buttons with nothing to do are simply disabled (an empty slot, an item with
# no slot) -- no hover tint, no pointer cursor, no click, tooltip still works.
# ---------------------------------------------------------------------------

const TILE_SCENE: PackedScene = preload("res://InventoryTile.tscn")

# The equipment slots, and the readable name each shows in its tooltip. Which
# box on screen each one is comes from the scene (ArmorSlot / WeaponSlot).
const SLOT_NAMES: Array[String] = ["armor", "weapon"]
const SLOT_LABELS: Dictionary = {"armor": "Armor", "weapon": "Weapon"}

@onready var close_button: Button = %CloseButton
@onready var gold_label: Label = %GoldLabel
@onready var item_scroll: ScrollContainer = %ItemScroll
@onready var items_grid: GridContainer = %ItemGrid
@onready var empty_label: Label = %EmptyLabel
@onready var slot_nodes: Dictionary = {"armor": %ArmorSlot, "weapon": %WeaponSlot}  # slot name -> InventorySlot instance

var tiles: Dictionary = {}  # item_id -> its InventoryTile (a Button)

# Optional gate a host scene can set to veto opening (e.g. Game blocks it while
# the local player is defeated -- see GameUIManager._build_ui()). Called with no
# arguments and must return a bool; left unset it never blocks, which is how
# Town.gd uses the panel. Only guards open(): closing is always allowed.
var can_open: Callable = Callable()

# Optional data source. Left unset, the panel reads and writes the CampaignManager
# globals (Campaign and Town). Game sets these for Endless / multiplayer so it shows
# the local player's own items and equipment instead (see LoadoutManager.gd):
#   get_inventory: () -> Dictionary        item_id -> quantity
#   get_equipped:  (slot: String) -> String
#   get_gold:      () -> int               the local player's gold
#   do_equip:      (item_id: String) -> void
#   do_unequip:    (slot: String) -> void
# do_equip / do_unequip may complete later (multiplayer asks the host); whoever
# applies the change then calls refresh().
var get_inventory: Callable = Callable()
var get_equipped: Callable = Callable()
var get_gold: Callable = Callable()
var do_equip: Callable = Callable()
var do_unequip: Callable = Callable()

func _ready() -> void:
	close_button.pressed.connect(close)
	for slot_name: String in SLOT_NAMES:
		var slot_button: Button = _slot_part(slot_name, "ClickButton")
		slot_button.pressed.connect(_on_slot_pressed.bind(slot_name))

func is_open() -> bool:
	return visible

func open() -> void:
	if can_open.is_valid() and not can_open.call():
		return
	# Owned items can't change while this is up (purchases happen in a shop
	# popup the player has to close first), so the grid is rebuilt just once
	# per open; equipping/unequipping only updates it in place afterwards.
	gold_label.text = str(_gold())
	_populate_items()
	_refresh_equipment()
	item_scroll.scroll_vertical = 0
	visible = true

func close() -> void:
	visible = false

# Re-reads what's equipped (in place). A no-op while hidden -- open() rebuilds everything.
func refresh() -> void:
	if visible:
		_refresh_equipment()

func _inventory() -> Dictionary:
	return get_inventory.call() if get_inventory.is_valid() else CampaignManager.inventory

func _gold() -> int:
	return int(get_gold.call()) if get_gold.is_valid() else CampaignManager.gold

# The gold count in the title bar is re-read every frame while the panel is up:
# in multiplayer a teammate solving the puzzle pays everyone out while this is
# open (the local player can't place bulbs with it open, but they can).
func _process(_delta: float) -> void:
	if visible:
		gold_label.text = str(_gold())

func _equipped_in(slot_name: String) -> String:
	return get_equipped.call(slot_name) if get_equipped.is_valid() else CampaignManager.get_equipped_item_id(slot_name)

func _equip(item_id: String) -> void:
	if do_equip.is_valid():
		do_equip.call(item_id)
	else:
		CampaignManager.equip_item(item_id)

func _unequip(slot_name: String) -> void:
	if do_unequip.is_valid():
		do_unequip.call(slot_name)
	else:
		CampaignManager.unequip_slot(slot_name)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		if visible:
			close()
		else:
			open()

func _slot_part(slot_name: String, part_name: String) -> Node:
	var slot: Node = slot_nodes[slot_name]
	return slot.get_node(part_name)

# --- Item grid -----------------------------------------------------------

func _populate_items() -> void:
	# remove_child first (not just queue_free) so the old tiles leave the
	# grid immediately instead of lingering until the end of the frame.
	for child in items_grid.get_children():
		items_grid.remove_child(child)
		child.queue_free()
	tiles.clear()

	var owned: Dictionary = _inventory()
	for item_id: String in owned.keys():
		var quantity: int = owned[item_id]
		if quantity <= 0:
			continue
		_add_tile(item_id, quantity)

	empty_label.visible = tiles.is_empty()

func _add_tile(item_id: String, quantity: int) -> void:
	var item: Dictionary = ItemData.get_item(item_id)
	if item.is_empty():
		return

	var tile: Button = TILE_SCENE.instantiate()
	tile.pressed.connect(_on_tile_pressed.bind(item_id))
	items_grid.add_child(tile)

	var icon_rect: TextureRect = tile.get_node("Icon")
	icon_rect.texture = ItemData.get_item_icon(item_id)
	# Quantity badge -- only when there's more than one.
	var quantity_label: Label = tile.get_node("QuantityLabel")
	quantity_label.text = "x%d" % quantity
	quantity_label.visible = quantity > 1

	tiles[item_id] = tile

# --- Refreshing (in place -- keeps the grid's scroll position) -----------

func _refresh_equipment() -> void:
	for slot_name: String in SLOT_NAMES:
		var item_id: String = _equipped_in(slot_name)
		var is_filled: bool = item_id != ""
		var item: Dictionary = ItemData.get_item(item_id)

		var icon_rect: TextureRect = _slot_part(slot_name, "Icon")
		icon_rect.texture = ItemData.get_item_icon(item_id) if is_filled else null

		# An empty slot has nothing to unequip, so its button is disabled.
		var button: Button = _slot_part(slot_name, "ClickButton")
		button.disabled = not is_filled
		if is_filled:
			button.tooltip_text = "%s (click to unequip)" % item.get("name", item_id)
		else:
			button.tooltip_text = "%s slot (empty)" % SLOT_LABELS.get(slot_name, slot_name)

	for item_id: String in tiles:
		_update_tile(item_id)

func _update_tile(item_id: String) -> void:
	var tile: Button = tiles[item_id]
	var item: Dictionary = ItemData.get_item(item_id)
	var slot_name: String = _equip_slot_of(item)
	var is_equipped: bool = slot_name != "" and _equipped_in(slot_name) == item_id

	var equipped_border: Control = tile.get_node("EquippedBorder")
	equipped_border.visible = is_equipped
	var equipped_badge: Label = tile.get_node("EquippedBadge")
	equipped_badge.visible = is_equipped
	tile.disabled = slot_name == ""  # nothing to do when clicked

	var lines: Array[String] = [item.get("name", item_id)]
	var description: String = item.get("description", "")
	if description != "":
		lines.append(description)
	if slot_name == "":
		lines.append("Can't be equipped")
	elif is_equipped:
		lines.append("Click to unequip")
	else:
		lines.append("Click to equip")
	tile.tooltip_text = "\n".join(lines)

# The slot an item can be equipped into -- "" if it has none, or names one
# this panel has no box for (either way the tile just isn't equippable here).
func _equip_slot_of(item: Dictionary) -> String:
	var slot_name: String = item.get("slot", "")
	return slot_name if SLOT_NAMES.has(slot_name) else ""

# --- Clicks ----------------------------------------------------------------

func _on_tile_pressed(item_id: String) -> void:
	var slot_name: String = _equip_slot_of(ItemData.get_item(item_id))
	if slot_name == "":
		return
	if _equipped_in(slot_name) == item_id:
		_unequip(slot_name)
	else:
		_equip(item_id)
	_refresh_equipment()

func _on_slot_pressed(slot_name: String) -> void:
	if _equipped_in(slot_name) == "":
		return
	_unequip(slot_name)
	_refresh_equipment()
