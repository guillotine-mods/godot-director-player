on exitFrame
  if not soundBusy(1) then
    go(marker(0))
  else
    go(marker(0) + 1)
  end if
end
