on mouseUp
  global soundspath, effectspath, movienamekeeper, stopornot, cdsavepath
  if sprite(30).visible = 1 then
    put "ok" into item 2 of stopornot
    put "ok" into item 1 of stopornot
    window(cdsavepath & "saveload.dxr").windowType = 2
    tell window(cdsavepath & "saveload.dxr")
      set the centerStage to 1
    end tell
    open(window(cdsavepath & "saveload.dxr"))
    tell window(cdsavepath & "saveload.dxr")
      go("savegame")
    end tell
    sound playFile 1, effectspath & "saveload.aif"
  end if
end
