on exitFrame
  if rollOver(22) then
    set the locV of sprite 25 to the locV of sprite 22
  end if
  if rollOver(23) then
    set the locV of sprite 25 to the locV of sprite 23
  end if
  if rollOver(24) then
    set the locV of sprite 25 to the locV of sprite 24
  end if
  updateStage()
  if not soundBusy(1) then
    go(marker(1))
  end if
end
