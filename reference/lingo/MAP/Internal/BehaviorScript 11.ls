on exitFrame
  if sprite(21).visible = 1 then
    sprite(21).visible = 0
    sprite(19).visible = 1
  else
    if sprite(20).visible = 1 then
      sprite(21).visible = 1
      sprite(20).visible = 0
    else
      if sprite(19).visible = 1 then
        sprite(19).visible = 0
        sprite(20).visible = 1
      end if
    end if
  end if
  go(marker(0))
end
