on exitFrame
  if not soundBusy(1) then
    sprite(27).visible = 1
    sprite(28).visible = 1
    sprite(29).visible = 1
    set the cursor of sprite 6 to [1, 1]
    play done
  else
    go(marker(0))
  end if
end
