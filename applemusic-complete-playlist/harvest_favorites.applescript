-- harvest_favorites.applescript
-- Idempotently copy every Favorited (♥) library track into "My Picks [PL]".
-- The 2024 Music redesign renamed the old `loved` flag to `favorited`. A track's
-- `persistent ID` is stable across playlists, so comparing it against what's
-- already in My Picks makes re-runs add only NEW favorites (no duplicates).
on run
	tell application "Music"
		set mpName to "My Picks [PL]"
		try
			set mp to (some playlist whose name is mpName)
		on error
			return "ERROR playlist not found: " & mpName
		end try
		set existingIDs to {}
		try
			set existingIDs to (get persistent ID of every track of mp)
		end try
		set favs to (every track of library playlist 1 whose favorited is true)
		set addedN to 0
		repeat with t in favs
			set pid to (persistent ID of t)
			if existingIDs does not contain pid then
				duplicate t to mp
				set addedN to addedN + 1
			end if
		end repeat
		return "OK favorited=" & (count of favs) & " added=" & addedN & " mypicks_total=" & (count of tracks of mp)
	end tell
end run
