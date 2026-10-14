class_name ItemData
extends RefCounted

# ---------------------------------------------------------------------------
# Pure data: every purchasable item, and which shop(s) sell it. Mirrors
# CampaignData's role for levels -- a stateless lookup table. What the
# player actually *owns* lives in CampaignManager.inventory, and what's
# currently *equipped* in CampaignManager.equipped; this is just the
# catalog both read item names/descriptions/costs/slots/art from by id.
#
# "slot" (optional) is which of InventoryPanel.gd's equipment slots an item
# can go in ("weapon" or "armor" -- see InventoryPanel.SLOT_NAMES); an item
# with no "slot" key just isn't equippable (shows in the inventory list
# with no Equip button).
#
# "icon" (optional) is a res://assets/ filename shown for the item in the
# shop and inventory panels -- see get_item_icon(). An item with no "icon"
# (or whose file is missing) shows its slot's default icon instead -- see
# DEFAULT_ICON_BY_SLOT below -- so placeholder gear still gets a picture.
#
# "overlays" (optional, armor only) is how the item looks equipped on the
# character, drawn over the player sprite by Player.gd/Town.gd: a
# dictionary of sheet kind -> direction -> res://assets/ filename, e.g.
# overlays["idle"]["right"]. Sheet kinds are "walk", "idle", "interact",
# "run", and "attack"; directions are
# "down", "right", "up" -- there's no "left", "right" gets mirrored, same
# as the player sheets themselves. Each file is a single-row strip of
# 32-pixel-wide frames (any height), one frame per column, matching that
# body sheet's frame count (4 for walk/idle/interact, 6 for run). A kind
# with no entry -- "attack", for now -- falls back to OVERLAY_ART_FALLBACK
# (attack borrows run's art). How far above the body frame's top edge each
# kind's art anchors is a property of the body sheets, not the item, and
# lives in Player.gd/Town.gd (OVERLAY_TOP_OFFSET_PIXELS).
# ---------------------------------------------------------------------------

const ITEMS: Dictionary = {
	"sample_weapon": {
		"name": "Sample Weapon",
		"description": "A placeholder weapon -- real gear replaces this later.",
		"cost": 1,
		"slot": "weapon",
	},
	"sample_armor": {
		"name": "Sample Armor",
		"description": "A placeholder armor piece -- real gear replaces this later.",
		"cost": 1,
		"slot": "armor",
	},
	"hat_0": {
		"name": "Wizard Hat",
		"description": "A pointed hat that reduces melee damage taken by 20%.",
		"cost": 30,
		"slot": "armor",
		"melee_damage_reduction": 0.2,
		"icon": "hat_0_store_icon.png",
		"overlays": {
			"walk": {"down": "hat_0_walk_down.png", "right": "hat_0_walk_side.png", "up": "hat_0_walk_up.png"},
			"idle": {"down": "hat_0_idle_down.png", "right": "hat_0_idle_side.png", "up": "hat_0_idle_up.png"},
			"interact": {"down": "hat_0_interact_down.png", "right": "hat_0_interact_side.png", "up": "hat_0_interact_up.png"},
			"run": {"down": "hat_0_run_down.png", "right": "hat_0_run_side.png", "up": "hat_0_run_up.png"},
		},
	},
}

# Which item ids each shop (keyed by Town.gd's shop "name") offers, in
# listing order.
const SHOP_ITEM_IDS: Dictionary = {
	"Weapons Shop": ["sample_weapon"],
	"Shields Shop": ["sample_armor", "hat_0"],
}

static func get_item(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})

# Every item any shop sells, each listed once, in shop order. The post-solve shop
# (Endless / multiplayer) lists these, and the host only accepts purchase requests
# for them.
static func all_shop_item_ids() -> Array:
	var item_ids: Array = []
	for shop_item_ids: Array in SHOP_ITEM_IDS.values():
		for item_id: String in shop_item_ids:
			if not item_ids.has(item_id):
				item_ids.append(item_id)
	return item_ids

# Fallback icon per equipment slot, used when an item has no icon art of its
# own: every armor piece is a hat and every weapon a staff, so these double as
# "generic hat" / "generic staff". Files under res://assets/.
const DEFAULT_ICON_BY_SLOT: Dictionary = {
	"armor": "default_hat_store_icon.png",
	"weapon": "default_staff_store_icon.png",
}

# The item's own icon if it has one, otherwise its slot's default icon, or
# null if neither exists (an item with no slot and no icon -- callers show
# the item's name as text instead).
static func get_item_icon(item_id: String) -> Texture2D:
	var texture: Texture2D = _load_item_asset(item_id, "icon")
	if texture != null:
		return texture
	var default_filename: String = DEFAULT_ICON_BY_SLOT.get(get_item(item_id).get("slot", ""), "")
	if default_filename == "":
		return null
	return AssetLoader.load_texture("res://assets/" + default_filename)

# Which sheet kind's overlay art to borrow when an item has none of its own
# for a given kind -- attack has no dedicated hat art yet, so it uses run's.
const OVERLAY_ART_FALLBACK: Dictionary = {"attack": "run"}

# sheet_kind is "walk", "idle", "interact", "run", or "attack"; direction is
# "down", "right", or "up" (pass "right" for a left-facing player too, and
# mirror the drawing -- there's no separate "left" art).
static func get_item_overlay_texture(item_id: String, sheet_kind: String, direction: String) -> Texture2D:
	var overlays: Dictionary = get_item(item_id).get("overlays", {})
	var resolved_kind: String = sheet_kind
	if not overlays.has(resolved_kind):
		resolved_kind = OVERLAY_ART_FALLBACK.get(sheet_kind, sheet_kind)
	var filename: String = overlays.get(resolved_kind, {}).get(direction, "")
	if filename == "":
		return null
	return AssetLoader.load_texture("res://assets/" + filename)

static func _load_item_asset(item_id: String, field: String) -> Texture2D:
	var filename: String = get_item(item_id).get(field, "")
	if filename == "":
		return null
	return AssetLoader.load_texture("res://assets/" + filename)
