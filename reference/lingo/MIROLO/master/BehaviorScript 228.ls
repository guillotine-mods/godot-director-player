on exitFrame
  if rollOver(61) then
    set the locV of sprite 64 to the locV of sprite 61
  end if
  if rollOver(62) then
    set the locV of sprite 64 to the locV of sprite 62
  end if
  if rollOver(63) then
    set the locV of sprite 64 to the locV of sprite 63
  end if
  updateStage()
end
