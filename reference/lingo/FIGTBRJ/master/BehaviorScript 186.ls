on exitFrame
  set the visible of sprite 93 to 1
  put value(the text of field "trynum" of castLib 1) + 1 into field "trynum"
  if value(the text of field "trynum" of castLib 1) > 2 then
    set the visible of sprite 10 to 1
  else
    set the visible of sprite 10 to 0
  end if
  go("goagain")
end
