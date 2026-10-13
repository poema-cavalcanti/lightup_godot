# Steam multiplayer setup

The Steam transport is written against the GodotSteam 4.17.x docs but has **not
been run yet** -- treat the checklist below as the first test pass.

## 1. Install the extension (free, no Steam account needed to try it)
1. Get **GodotSteam GDExtension 4.4+** (Godot Asset Library, or the GodotSteam
   releases on Codeberg) and copy its `addons/godotsteam` folder into this
   project. Restart the editor.
2. If the project loads and the Lobby shows **Network: Steam**, the extension
   is working. If it shows "Steam isn't available (...)", the message tells you
   why (extension missing, or the Steam client isn't running / logged in).
   Without the extension the game still runs; it just offers LAN / direct IP.
3. Don't install a second Steam multiplayer-peer plugin alongside it; the
   GodotSteam author notes they conflict.

## 2. Test with Valve's shared test app (480)
`SteamBridge.APP_ID` is `480` ("Spacewar"). With the Steam client running:
- Steam allows one logged-in account per client, so a **real multiplayer test
  needs two Steam accounts** (two computers, or a friend). To test on one PC use
  the LAN / direct-IP option instead.
- Both accounts must be Steam friends (lobbies are friends-only).
- Host: Multiplayer > Host Game > **Invite Friends**. Joiner: accept the invite,
  or right-click the host in Steam > **Join Game**.
- The invite overlay can be flaky when the game is launched from the Godot
  editor; if it doesn't appear, export a build and launch that.

## 3. Before release
- Replace `APP_ID` in `SteamBridge.gd` with your real Steam app ID.
- Remove any `steam_appid.txt` from the build you upload to Steam.
- Include the GodotSteam extension files in your export presets.
- Optional: set `LOBBY_TYPE` to `0` (invite only) for a stricter lobby.

## 4. Checklist: things to verify when you first run it
- [ ] Host creates a lobby; the lobby screen shows a Lobby ID.
- [ ] Friend joins via invite / Join Game; both see the connected-players list.
- [ ] Start Game loads the same puzzle for everyone; movement and bulbs sync.
- [ ] A third Steam user cannot join after Start Game (lobby is locked).
- [ ] Host Leave / client Leave return to the lobby cleanly, and you can host or
      join again afterwards without restarting.
- [ ] Join with the host gone: you get a "couldn't connect" message within ~15 s.
- [ ] Peer IDs: `connected_peer_ids[0]` is `1` on the host, and each client's
      `my_player_index` matches their slot (the request-validation code relies
      on this).
- [ ] Disconnect one client mid-match; the others can still move.
- [ ] **Lobby-member check:** the host drops any peer that isn't in its Steam
      lobby, using `get_steam64_from_peer_id()`. Watch the Output panel on the
      host: if you see "Can't verify Steam peer", your plugin version doesn't
      expose that function and the check is NOT active. Then check the class
      reference for another way to confirm a peer's Steam ID, or whether the
      peer already refuses connections from non-lobby users.
- [ ] **IP privacy:** with a network monitor or Steam's networking docs, confirm
      whether players ever connect directly (peer-to-peer) rather than through
      Valve's relay. If they can, look up Steam's setting to force relay-only
      before telling players their IPs are hidden.

## Known unknowns
- `setLobbyJoinable(lobby_id, joinable)` and the `steamInitEx(app_id, true)`
  signature were taken from the current docs; if a call errors, check the
  GodotSteam class reference for your installed version.
- Not yet verified against Godot 4.7 specifically.
