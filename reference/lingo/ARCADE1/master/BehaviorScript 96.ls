on exitFrame
  global effectspath
  puppetSprite(12, 1)
  puppetSprite(13, 1)
  puppetSprite(5, 1)
  puppetSprite(6, 1)
  puppetSprite(7, 1)
  puppetSprite(8, 1)
  if sprite(96).visible = 0 then
    sprite(96).visible = 1
  else
    if sprite(95).visible = 0 then
      sprite(95).visible = 1
    else
      if sprite(94).visible = 0 then
        sprite(94).visible = 1
      end if
    end if
  end if
  set the keyDownScript to "keyys"
  x = item 7 of field "infos"
  put "1,0,0,1,0,0," & x into field "infos"
  put "1,ok,ok,ok,ok" into field "posi"
  sound playFile 2, effectspath & "action.aif"
end
