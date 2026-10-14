extends RefCounted

# ---------------------------------------------------------------------------
# LOADOUT (Endless / multiplayer): what each player has equipped.
#
# Session-only, like gold and purchases: game.player_equipped is one
# {slot: item_id} dictionary per player (index == player_index), kept OUT of
# players[i] because those get rebuilt on Reset / new puzzle / respawn.
# In the campaign everything still lives on CampaignManager, so the queries
# below just defer to it and nothing else about the campaign changes.
#
# Equipping follows the same host-authoritative shape as purchasing
# (ShopManager.gd): the player asks (_request_equip), the host validates
# (owned item, matching slot, rate limit) and broadcasts the absolute result
# (_sync_equipped), applied on every peer so teammates see each other's gear.
# The RPC entry points are thin wrappers in Game.gd.
# ---------------------------------------------------------------------------

const EQUIP_SLOTS: Array[String] = ["armor", "weapon"]
const EQUIP_MIN_INTERVAL: float = 0.1

var game: Node

func _init(game_ref: Node) -> void:
	game = game_ref

static func empty_loadout() -> Dictionary:
	var loadout: Dictionary = {}
	for slot: String in EQUIP_SLOTS:
		loadout[slot] = ""
	return loadout

# --- Queries (any peer) ------------------------------------------------------

# Campaign: the global. Otherwise: that player's synced entry.
func equipped_item_id(player_index: int, slot: String) -> String:
	if CampaignManager.is_campaign_active:
		return CampaignManager.get_equipped_item_id(slot)
	if player_index < 0 or player_index >= game.player_equipped.size():
		return ""
	return game.player_equipped[player_index].get(slot, "")

func my_equipped_item_id(slot: String) -> String:
	return equipped_item_id(game.my_player_index, slot)

func my_inventory() -> Dictionary:
	if CampaignManager.is_campaign_active:
		return CampaignManager.inventory
	if game.my_player_index < 0 or game.my_player_index >= game.player_inventory.size():
		return {}
	return game.player_inventory[game.my_player_index]

# The inventory's can_open gate: not while defeated, and not under the shop.
func can_open_inventory() -> bool:
	return game.player_mgr._is_local_player_alive() and not game.shop_mgr.is_open()

# --- Local player's actions (what the InventoryPanel calls) -----------------------

func equip(item_id: String) -> void:
	var slot: String = ItemData.get_item(item_id).get("slot", "")
	if slot == "":
		return
	_ask(slot, item_id)

func unequip(slot: String) -> void:
	_ask(slot, "")

func _ask(slot: String, item_id: String) -> void:
	if CampaignManager.is_campaign_active:
		# Singleplayer by definition; CampaignManager validates and saves.
		if item_id == "":
			CampaignManager.unequip_slot(slot)
		else:
			CampaignManager.equip_item(item_id)
		return
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		game.rpc_id(1, "_request_equip", game.my_player_index, slot, item_id)
	else:
		_request_equip(game.my_player_index, slot, item_id)

# --- Host side ---------------------------------------------------------------

func _request_equip(player_index: int, slot: String, item_id: String) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		return  # only the host may approve changes
	if not NetworkManager.validate_request(player_index, game.players.size(), "equip", EQUIP_MIN_INTERVAL):
		return
	if player_index >= game.player_equipped.size() or player_index >= game.player_inventory.size():
		return
	if not EQUIP_SLOTS.has(slot):
		return
	if item_id != "":
		if ItemData.get_item(item_id).get("slot", "") != slot:
			return
		if int(game.player_inventory[player_index].get(item_id, 0)) <= 0:
			return  # can only wear what you own
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_equipped", player_index, slot, item_id)
	else:
		_sync_equipped(player_index, slot, item_id)

# --- Every peer ----------------------------------------------------------------

func _sync_equipped(player_index: int, slot: String, item_id: String) -> void:
	if player_index < 0 or player_index >= game.player_equipped.size() or not EQUIP_SLOTS.has(slot):
		return
	game.player_equipped[player_index][slot] = item_id
	if player_index == game.my_player_index and game.inventory_panel != null:
		game.inventory_panel.refresh()
	game.queue_redraw()  # teammates' hats
