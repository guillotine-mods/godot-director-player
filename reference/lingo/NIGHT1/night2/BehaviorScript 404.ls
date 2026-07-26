on exitFrame
  if not soundBusy(1) then
    go("path5go")
  else
    go(marker(0))
  end if
end
