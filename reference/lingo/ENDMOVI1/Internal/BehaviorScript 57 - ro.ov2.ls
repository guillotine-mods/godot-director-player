on exitFrame
  go(marker(0))
  if rollOver(41) then
    set the locV of sprite 44 to the locV of sprite 41
  end if
  if rollOver(42) then
    set the locV of sprite 44 to the locV of sprite 42
  end if
  if rollOver(43) then
    set the locV of sprite 44 to the locV of sprite 43
  end if
  updateStage()
end
