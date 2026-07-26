on exitFrame
  if not soundBusy(1) then
    play done
  else
    go(marker(0))
  end if
end
