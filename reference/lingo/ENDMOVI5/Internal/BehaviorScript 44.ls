on exitFrame
  go(marker(0))
  if rollOver(61) then
    set the locV of sprite 63 to the locV of sprite 61
  end if
  if rollOver(62) then
    set the locV of sprite 63 to the locV of sprite 62
  end if
  updateStage()
end
