on exitFrame
  if not soundBusy(1) then
    go("instruct")
  else
    go(marker(0))
  end if
end
