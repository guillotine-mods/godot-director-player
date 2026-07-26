on exitFrame
  global dubi
  if dubi < 2 then
    sprite(22).visible = 1
    sprite(23).visible = 1
    sprite(24).visible = 1
    sprite(29).visible = 1
    sprite(29).visible = 1
    sprite(21).visible = 1
    sprite(14).visible = 1
    go("warehouse1")
  else
    sprite(22).visible = 1
    sprite(23).visible = 1
    sprite(24).visible = 1
    sprite(29).visible = 1
    sprite(21).visible = 1
    sprite(14).visible = 1
    if dubi = 2 then
      go("dubisurprise")
    else
      go("warehouse3")
    end if
  end if
end
