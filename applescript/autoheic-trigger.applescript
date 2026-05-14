-- autoheic Folder Action trigger.
-- Fired by macOS System Events when files are added to an attached folder.
-- Dispatches each HEIC/HEIF file to the autoheic per-file converter.
--
-- The __CONVERTER_PATH__ token is replaced by install.sh with the absolute
-- path to bin/heic-convert-one before this script is compiled with osacompile.

on adding folder items to this_folder after receiving added_items
	repeat with anItem in added_items
		set itemPath to POSIX path of anItem
		try
			set lcExt to do shell script "printf '%s' " & quoted form of itemPath & " | awk -F. '{print tolower($NF)}'"
			if lcExt is "heic" or lcExt is "heif" then
				do shell script quoted form of "__CONVERTER_PATH__" & " " & quoted form of itemPath
			end if
		end try
	end repeat
end adding folder items to
