on exitFrame
  global zigi
  zigi = zigi - 1
  if zigi = 0 then
    set the memberNum of sprite 7 to the number of member "gundefault" of castLib 1
    updateStage()
  end if
end
