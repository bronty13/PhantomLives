-- set_descriptions.applescript <tsv-path>
-- Reads a UTF-8 TSV of  <playlist name>\t<description>  (one per line) and sets
-- each library playlist's description. AppleScript can update a playlist
-- description (the REST API cannot — PATCH returns 401); the change syncs to iCloud.
on run argv
	set tsvPath to item 1 of argv
	set txt to read (POSIX file tsvPath) as «class utf8»
	set okCount to 0
	set failCount to 0
	set AppleScript's text item delimiters to tab
	tell application "Music"
		repeat with ln in paragraphs of txt
			set ln to ln as text
			if ln is not "" then
				set parts to text items of ln
				if (count of parts) ≥ 2 then
					set plName to item 1 of parts
					set plDesc to item 2 of parts
					try
						set description of user playlist plName to plDesc
						set okCount to okCount + 1
					on error
						set failCount to failCount + 1
					end try
				end if
			end if
		end repeat
	end tell
	return ("ok=" & okCount & " fail=" & failCount)
end run
