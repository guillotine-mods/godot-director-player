on exitFrame
  global zigi
  zigi = zigi - 1
  if zigi = 0 then
    set the memberNum of sprite 7 to the number of member "gundefault" of castLib 1
    set the locH of sprite 7 to 175
    set the locV of sprite 7 to 237
    updateStage()
  end if
end
