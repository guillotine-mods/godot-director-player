on exitFrame
  if not soundBusy(1) then
    go(marker(1))
  else
    go(marker(0))
  end if
end
