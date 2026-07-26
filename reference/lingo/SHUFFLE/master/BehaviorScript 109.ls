on exitFrame
  global effectspath
  if not soundBusy(2) then
    sound playFile 2, effectspath & "arcade.aif"
  end if
  go("strtmtch")
  set the locH of sprite 4 to 197
  set the locV of sprite 4 to 360
  set the locH of sprite 11 to 197
  set the locV of sprite 11 to 360
  put the locH of sprite 4 into item 1 of sfl2
  put the locV of sprite 4 into item 2 of sfl2
  put 0 into item 3 of sfl
  updateStage()
end
