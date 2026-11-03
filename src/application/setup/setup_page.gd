class_name SetupPage
extends RefCounted
## One page of the setup screen: its title, and whether the player may move
## on from it or back, with the reason when not.
##
## Each concern of the setup has its own page model and its own view; a new
## concern adds a page to [SetupFlow]'s order. Page models hold plain state
## and never touch files, so their rules can be checked without a window.


## The page's heading.
func title() -> String:
	return ""


## Why the player cannot move on yet, or "" when they can.
func blocker() -> String:
	return ""


## Whether the player may move on to the next page.
func can_continue() -> bool:
	return blocker().is_empty()


## Whether the player may go back to the previous page.
func can_go_back() -> bool:
	return true
