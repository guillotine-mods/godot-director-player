on exitFrame
  if not soundBusy(1) then
    play done
    puppetSprite(13, 0)
  else
    go(marker(0))
  end if
end
