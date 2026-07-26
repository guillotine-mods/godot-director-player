on exitFrame
  sprite(93).visible = 1
  put value(the text of field "trynum") + 1 into field "trynum"
  updateStage()
  if value(the text of field "trynum") > 2 then
    sprite(10).visible = 1
  else
    sprite(10).visible = 0
  end if
  go("goagain")
end
