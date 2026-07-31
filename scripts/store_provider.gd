class_name StoreProvider
extends Node
## The billing seam: purchase, restore, price lookup.
##
## A Node, not a RefCounted, because a real provider has to survive across frames
## and receive signals from an Android plugin singleton.
##
## The null behaviour below is the LOCAL default and it is deliberately honest:
## `available()` is false and `purchase()` fails, so every caller already takes
## the "cannot buy" path. A stub that returned success would mint currency and
## grant entitlements for free — the single most damaging thing a fake provider
## can do, because it is invisible until someone audits the ledger.

## Calls back with (ok, receipt). A real provider validates server-side first.
func purchase(_product_id: String, cb: Callable) -> void:
	cb.call(false, "")

func restore(cb: Callable) -> void:
	cb.call([])

func available() -> bool:
	return false

## Localised price string from the live store, or "" to use the fallback.
func price_string(_product_id: String) -> String:
	return ""
