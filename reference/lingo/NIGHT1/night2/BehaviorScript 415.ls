on mouseUp
  global soundspath, effectspath, movienamekeeper, stopornot
  if sprite(30).visible = 1 then
    put "ok" into item 2 of stopornot
    put "ok" into item 1 of stopornot
    window("map.dxr").windowType = 2
    tell window("map.dxr")
      set the centerStage to 1
    end tell
    tell window("map.dxr")
      go("nightmap")
    end tell
    open(window("map.dxr"))
    sound playFile 1, effectspath & "map.aif"
  else
    sound playFile 1, effectspath & "clik2.aif"
  end if
end
