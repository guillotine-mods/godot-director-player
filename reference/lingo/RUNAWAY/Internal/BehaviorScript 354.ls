on exitFrame
  if not soundBusy(4) then
    go(marker(1))
  else
    go(marker(0) + 1)
  end if
end
