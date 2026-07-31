class_name BackendProvider
extends RefCounted
## The backend seam: auth, cloud save, leaderboards.
##
## Lifted out of backend.gd because it was an inner class, and a GDScript inner
## class cannot be extended from another file — so the "provider seam" the
## architecture claimed could not actually be implemented by anything. The null
## behaviour below is the LOCAL default: honest failures, never faked success.

## Calls back with (ok, account_id, display_name).
func sign_in(guest: bool, cb: Callable) -> void:
	cb.call(true, "guest-local", "")
func sign_out() -> void:
	pass
## Calls back with the remote payload, or {} when there is none.
func load_cloud(cb: Callable) -> void:
	cb.call({})
func save_cloud(_payload: Dictionary, cb: Callable) -> void:
	cb.call(true)
func submit_score(_score: int, cb: Callable) -> void:
	cb.call(true)
func fetch_board(_scope: int, cb: Callable) -> void:
	cb.call([])
func available() -> bool:
	return false

## --- friends ---------------------------------------------------------------
##
## Local default is "cannot", not "empty". A friends feature that silently
## reports success with nobody in it looks identical to a friends feature that
## works and has no friends yet, and the player has no way to tell which they are
## looking at.
func friends_available() -> bool:
	return false
## Calls back with (ok, friend_name, reason). `reason` is a UI key, not prose.
func add_friend(_code: String, cb: Callable) -> void:
	cb.call(false, "", "offline")
## Calls back with an Array of {name, score}.
func list_friends(cb: Callable) -> void:
	cb.call([])
