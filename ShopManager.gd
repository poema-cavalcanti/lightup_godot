extends RefCounted

# ---------------------------------------------------------------------------
# Shopping in Endless Mode and multiplayer (the campaign shops in Town.tscn
# with CampaignManager's own gold and inventory). Split out of Game.gd like the
# other managers -- operates on shared state via the `game` back-reference,
# and Game.gd holds the thin @rpc wrappers that call into here.
#
# The shop is a window (ShopPanel.tscn) opened from the Shop button on the
# post-solve summary screen. Every player has their OWN gold and items
# (game.player_gold / game.player_inventory, index == player_index): the
# level's earnings are paid to everyone in full, but a purchase only ever
# touches the buyer.
#
# Purchases are host-authoritative, like everything else shared:
#   1. The buyer's click -> _on_purchase_requested() sends the request to the
#      host (or handles it directly if this peer IS the host / singleplayer).
#   2. The host re-checks everything (_request_purchase) -- the item is for
#      sale, the board is solved, the buyer can afford it -- since the panel's
#      own "Not enough gold!" is only a convenience for honest clients.
#   3. If it's valid, the host broadcasts the buyer's new gold and item count
#      (_sync_purchase), applied on every peer. Absolute values, not deltas, so
#      a repeated message can't double-charge. If it's not, only the buyer is
#      told why (_purchase_rejected).
# Items are only recorded here for now: equipping them and their effects are
# not wired up outside the campaign yet.
# ---------------------------------------------------------------------------

const SHOP_PANEL_SCENE: PackedScene = preload("res://ShopPanel.tscn")
const SHOP_TITLE: String = "Shop"
const PURCHASE_MIN_INTERVAL: float = 0.2  # seconds between accepted requests from one player

var game: Node2D
var panel: CanvasLayer = null

func _init(game_ref: Node2D) -> void:
	game = game_ref

# Called once from GameUIManager._build_ui(), only for Endless / multiplayer.
func build_panel() -> void:
	panel = SHOP_PANEL_SCENE.instantiate()
	game.add_child(panel)
	panel.setup(_my_gold, _my_quantity)
	panel.purchase_requested.connect(_on_purchase_requested)

func open_shop() -> void:
	if panel != null and game.was_solved:
		panel.open(SHOP_TITLE, ItemData.all_shop_item_ids())

func close_shop() -> void:
	if panel != null:
		panel.close()

func is_open() -> bool:
	return panel != null and panel.is_open()

# --- This peer's own wallet (what the panel displays) -----------------------

func _my_gold() -> int:
	if game.my_player_index < 0 or game.my_player_index >= game.player_gold.size():
		return 0
	return game.player_gold[game.my_player_index]

func _my_quantity(item_id: String) -> int:
	if game.my_player_index < 0 or game.my_player_index >= game.player_inventory.size():
		return 0
	return int(game.player_inventory[game.my_player_index].get(item_id, 0))

# --- Buyer side --------------------------------------------------------------

func _on_purchase_requested(item_id: String) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		game.rpc_id(1, "_request_purchase", game.my_player_index, item_id)
	else:
		_request_purchase(game.my_player_index, item_id)

# --- Host side ---------------------------------------------------------------

func _request_purchase(player_index: int, item_id: String) -> void:
	if NetworkManager.is_multiplayer and not game.multiplayer.is_server():
		return  # only the host may approve purchases
	if not NetworkManager.validate_request(player_index, game.players.size(), "purchase", PURCHASE_MIN_INTERVAL):
		return
	var sender_peer_id: int = game.multiplayer.get_remote_sender_id() if NetworkManager.is_multiplayer else 0

	if not ItemData.all_shop_item_ids().has(item_id):
		_reject(sender_peer_id, item_id, "That item isn't for sale.")
		return
	if not game.was_solved:
		_reject(sender_peer_id, item_id, "The shop is closed right now.")
		return
	var cost: int = int(ItemData.get_item(item_id).get("cost", 0))
	var gold: int = game.player_gold[player_index]
	if gold < cost:
		_reject(sender_peer_id, item_id, "Not enough gold!")
		return

	var new_gold: int = gold - cost
	var new_quantity: int = int(game.player_inventory[player_index].get(item_id, 0)) + 1
	if NetworkManager.is_multiplayer:
		game.rpc("_sync_purchase", player_index, item_id, new_gold, new_quantity)
	else:
		_sync_purchase(player_index, item_id, new_gold, new_quantity)

# Tells just the buyer why a request was refused (the host itself is peer 0
# here -- a direct local call).
func _reject(sender_peer_id: int, item_id: String, message: String) -> void:
	if sender_peer_id == 0:
		_purchase_rejected(item_id, message)
	else:
		game.rpc_id(sender_peer_id, "_purchase_rejected", item_id, message)

# --- Every peer ----------------------------------------------------------------

func _sync_purchase(player_index: int, item_id: String, new_gold: int, new_quantity: int) -> void:
	if player_index < 0 or player_index >= game.player_gold.size() or player_index >= game.player_inventory.size():
		return
	game.player_gold[player_index] = new_gold
	game.player_inventory[player_index][item_id] = new_quantity
	if player_index == game.my_player_index and panel != null:
		panel.show_result(item_id, true, "Purchased!")
		panel.refresh()

func _purchase_rejected(item_id: String, message: String) -> void:
	if panel != null:
		panel.show_result(item_id, false, message)
		panel.refresh()
